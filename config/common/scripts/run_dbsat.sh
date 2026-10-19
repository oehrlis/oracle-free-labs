#!/bin/bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: run_dbsat.sh
# Author.....: Stefan Oehrli (oes), stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026.10.19
# Revision...: v1.1.0
# Purpose....: Run the Oracle Database Security Assessment Tool (DBSAT)
#              collector and reporter inside a lab container.
# Notes......: - DBSAT is NOT shipped with this repository (Oracle license).
#                Place the downloaded dbsat*.zip in config/common/data/dbsat/
#                on the host (= /opt/oracle/data/dbsat in the container).
#                Without it the script stops with exit 4 and says what to do.
#              - Collects as a dedicated account (create_dbsat_user.sql), not
#                as SYS. Password from an environment variable (-e).
#              - The image has no zip binary: collect and report run with -n
#                (output not encrypted), which DBSAT offers for this case.
#              - DBSAT 4.x report needs Java 17+. The image ships JDK 11 in
#                $ORACLE_HOME/jdk, which the launcher rejects. JAVA_HOME is set
#                to -j DIR, else to the first of $JAVA_HOME,
#                /opt/oracle/oradata/tools/jre21, /tmp/jre21 with Java 17+.
#                scripts/provide_jre.sh on the host copies a JRE 21 there
#                (make dbsat-seclab and make dbsat do this). Without Java 17+
#                the collection still runs, then the script stops with exit 5
#                and names the command that provides Java.
#              - Output: <out-dir>/dbsat_<pdb>.json and the reports
#                dbsat_<pdb>_report.{html,txt,xlsx,json}. Old files of the
#                same name are removed first and the removal is reported.
#              - Exit codes: 0 collect + report done, 1 error, 4 no DBSAT zip,
#                5 collection done, but no Java 17+ for the report.
# Usage......: run_dbsat.sh -s SERVICE [-p PDB] [-u USER] [-e VAR] [-o DIR] [-j DIR] [-n]
# Reference..: https://www.oracle.com/database/technologies/security/dbsat.html
# License....: Apache License Version 2.0, January 2004 as shown
#              at http://www.apache.org/licenses/
# ------------------------------------------------------------------------------
set -euo pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly COMMON_DIR="${COMMON_SCRIPTS_DIR:-/opt/oracle/common/scripts}"
readonly DBSAT_URL="https://www.oracle.com/database/technologies/security/dbsat.html"
# keep in sync with MIN_JAVA in scripts/provide_jre.sh
readonly MIN_JAVA=17
# keep in sync with default_target in scripts/provide_jre.sh
readonly JRE_CANDIDATES="/opt/oracle/oradata/tools/jre21 /tmp/jre21"
ZIP_DIR="/opt/oracle/data/dbsat"
OUT_DIR="/opt/oracle/oradata/dbsat"
WORK_DIR="/tmp/dbsat"
SERVICE=""
PDB=""
DBSAT_USER="DBSAT_USER"
PWD_VAR="DBSAT_PWD"
JAVA_DIR=""
JAVA_OK=false
DRY_RUN=false

# ------------------------------------------------------------------------------
# Function...: usage
# Purpose....: Print usage and exit
# ------------------------------------------------------------------------------
usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} -s SERVICE [options]

Run DBSAT collect + report against a PDB of this container.

Options:
  -s, --service NAME  Listener service of the PDB (required)
  -p, --pdb PDB       PDB for the collector account (default: SERVICE)
  -u, --user NAME     Collector account (default: ${DBSAT_USER})
  -e, --env VAR       Environment variable holding its password (default: ${PWD_VAR})
  -z, --zip-dir DIR   Directory with dbsat*.zip (default: ${ZIP_DIR})
  -o, --out-dir DIR   Output directory (default: ${OUT_DIR})
  -j, --java-home DIR Java ${MIN_JAVA}+ for dbsat report (default: the first of
                      $(java_search_list) with Java ${MIN_JAVA}+)
  -n, --dry-run       Check prerequisites only, run nothing
  -h, --help          Show this help

Exit codes: 0 done, 1 error, 4 no DBSAT zip, 5 collected but no Java ${MIN_JAVA}+ for the report
EOF
    exit "${1:-0}"
}

# ------------------------------------------------------------------------------
# Function...: missing_dbsat
# Purpose....: Explain how to provide DBSAT, exit 4
# ------------------------------------------------------------------------------
missing_dbsat() {
    cat >&2 << EOF
ERROR: no dbsat*.zip found in ${ZIP_DIR}
       DBSAT is not part of this repository (Oracle license terms).
       1. Download DBSAT (Oracle account required): ${DBSAT_URL}
       2. Copy the zip on the host to: config/common/data/dbsat/
       3. Run again: make dbsat-seclab
EOF
    exit 4
}

# ------------------------------------------------------------------------------
# Function...: java_search_list
# Purpose....: Print the directories searched for Java, -j DIR if given
# ------------------------------------------------------------------------------
java_search_list() {
    if [[ -n "${JAVA_DIR}" ]]; then
        echo "${JAVA_DIR}"
    else
        echo "\$JAVA_HOME ${JRE_CANDIDATES}"
    fi
}

# ------------------------------------------------------------------------------
# Function...: die_no_java
# Purpose....: Explain how to provide Java 17+ after the collection, exit 5
# ------------------------------------------------------------------------------
die_no_java() {
    cat >&2 << EOF
ERROR: dbsat report needs Java ${MIN_JAVA}+ - none found in: $(java_search_list)
       The image JDK (\$ORACLE_HOME/jdk, Java 11) is rejected by DBSAT 4.x.
       The collection is done: $1
       Provide a JRE 21 from the host, then run again:
         make dbsat-seclab                       # seclab service
         make dbsat CONTAINER=<name>             # any container
         scripts/provide_jre.sh <container>      # JRE only, then rerun this script
EOF
    exit 5
}

# ------------------------------------------------------------------------------
# Function...: java_major
# Purpose....: Print the Java major version of $1/bin/java, empty if it fails
# Notes......: keep in sync with java_major in scripts/provide_jre.sh
# ------------------------------------------------------------------------------
java_major() {
    local out line ver
    out="$("$1/bin/java" -version 2>&1)" || true
    line="${out%%$'\n'*}"
    case "${line}" in
        *version*\"*\"*) ;;
        *) return 0 ;;
    esac
    ver="${line#*\"}"
    ver="${ver%%\"*}"
    ver="${ver#1.}"
    ver="${ver%%[.+-]*}"
    case "${ver}" in
        '' | *[!0-9]*) return 0 ;;
    esac
    echo "${ver}"
}

# ------------------------------------------------------------------------------
# Function...: resolve_java
# Purpose....: Export JAVA_HOME as the first candidate with Java 17+ and set
#              JAVA_OK; every rejected candidate is reported
# ------------------------------------------------------------------------------
resolve_java() {
    local candidates=() dir major
    if [[ -n "${JAVA_DIR}" ]]; then
        candidates=("${JAVA_DIR}")
    else
        # shellcheck disable=SC2206 # fixed list without whitespace in paths
        candidates=(${JAVA_HOME:-} ${JRE_CANDIDATES})
    fi
    for dir in "${candidates[@]}"; do
        if [[ ! -x "${dir}/bin/java" ]]; then
            echo "INFO: no java in ${dir} - skipped"
            continue
        fi
        major="$(java_major "${dir}")"
        if [[ -n "${major}" && ${major} -ge ${MIN_JAVA} ]]; then
            export JAVA_HOME="${dir}"
            JAVA_OK=true
            echo "INFO: Java ${major} in ${dir} - JAVA_HOME for dbsat report"
            return 0
        fi
        echo "INFO: Java ${major:-unknown} in ${dir} is older than ${MIN_JAVA} - skipped"
    done
    echo "WARN: no Java ${MIN_JAVA}+ found in $(java_search_list) - dbsat collect runs, dbsat report does not (exit 5)"
}

# ------------------------------------------------------------------------------
# Function...: check_prereqs
# Purpose....: Report the runtime prerequisites of DBSAT in this image
# ------------------------------------------------------------------------------
check_prereqs() {
    echo "INFO: python3: $(command -v python3 || echo none) - only DBSAT releases before 4.x report with it"
    resolve_java
    if command -v zip > /dev/null 2>&1; then
        echo "INFO: zip present - still using -n for a scriptable, unencrypted run"
    else
        echo "INFO: no zip binary in the image - collect and report use -n (unencrypted output)"
    fi
    if ! command -v unzip > /dev/null 2>&1; then
        echo "ERROR: unzip not found - cannot extract DBSAT" >&2
        return 1
    fi
}

# ------------------------------------------------------------------------------
# Function...: main
# Purpose....: Locate, extract, prepare account, collect, report
# ------------------------------------------------------------------------------
main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -s | --service) SERVICE="${2:?missing value for $1}"; shift 2 ;;
            -p | --pdb) PDB="${2:?missing value for $1}"; shift 2 ;;
            -u | --user) DBSAT_USER="${2:?missing value for $1}"; shift 2 ;;
            -e | --env) PWD_VAR="${2:?missing value for $1}"; shift 2 ;;
            -z | --zip-dir) ZIP_DIR="${2:?missing value for $1}"; shift 2 ;;
            -o | --out-dir) OUT_DIR="${2:?missing value for $1}"; shift 2 ;;
            -j | --java-home) JAVA_DIR="${2:?missing value for $1}"; shift 2 ;;
            -n | --dry-run) DRY_RUN=true; shift ;;
            -h | --help) usage 0 ;;
            *) echo "ERROR: unknown option $1" >&2; usage 1 ;;
        esac
    done
    if [[ -z "${SERVICE}" ]]; then
        echo "ERROR: -s SERVICE is required" >&2
        usage 1
    fi
    PDB="${PDB:-${SERVICE}}"

    local zip="" f
    for f in "${ZIP_DIR}"/dbsat*.zip; do
        if [[ -f "${f}" && "${f}" -nt "${zip:-/nonexistent}" ]]; then
            zip="${f}"
        fi
    done
    if [[ -z "${zip}" ]]; then
        missing_dbsat
    fi
    echo "INFO: DBSAT archive ${zip}"
    check_prereqs

    if [[ -z "${!PWD_VAR:-}" ]]; then
        echo "ERROR: ${PWD_VAR} is not set or empty (password of ${DBSAT_USER})" >&2
        return 1
    fi
    if [[ "${DRY_RUN}" == true ]]; then
        echo "INFO: dry run - prerequisites checked, nothing executed"
        return 0
    fi

    if [[ -e "${WORK_DIR}" ]]; then
        rm -rf "${WORK_DIR}"
        echo "INFO: removed previous extraction ${WORK_DIR}"
    fi
    # Plain Oracle image: no logs bind mount, run_sql_script.sh spools there
    export SQL_LOG_DIR="${SQL_LOG_DIR:-/opt/oracle/scripts/logs}"
    mkdir -p "${WORK_DIR}" "${OUT_DIR}" "${SQL_LOG_DIR}"
    unzip -q "${zip}" -d "${WORK_DIR}"
    # DBSAT 4.x extracts into a dbsat/ subdirectory, older releases flat
    local dbsat
    dbsat="$(find "${WORK_DIR}" -maxdepth 2 -name dbsat -type f | head -1)"
    if [[ -z "${dbsat}" ]]; then
        echo "ERROR: no dbsat launcher found in ${zip}" >&2
        return 1
    fi
    chmod +x "${dbsat}"
    echo "INFO: DBSAT extracted to ${WORK_DIR}, launcher ${dbsat}"

    "${COMMON_DIR}/run_sql_script.sh" -p "${PDB}" -e "${PWD_VAR}" create_dbsat_user.sql "${DBSAT_USER}"

    local name="dbsat_${PDB,,}" old
    for old in "${OUT_DIR}/${name}".json "${OUT_DIR}/${name}"_report.*; do
        if [[ -e "${old}" ]]; then
            rm -f "${old}"
            echo "INFO: removed previous output ${old}"
        fi
    done

    local rc=0
    echo "INFO: dbsat collect ${DBSAT_USER}@//localhost:1521/${SERVICE}"
    (cd "${OUT_DIR}" && printf '%s\n' "${!PWD_VAR}" \
        | "${dbsat}" collect -n "${DBSAT_USER}@//localhost:1521/${SERVICE}" "${OUT_DIR}/${name}") || rc=$?
    if [[ ${rc} -ne 0 || ! -s "${OUT_DIR}/${name}.json" ]]; then
        echo "ERROR: dbsat collect failed (rc=${rc}) or wrote no ${OUT_DIR}/${name}.json" >&2
        return 1
    fi
    if [[ "${JAVA_OK}" != true ]]; then
        die_no_java "${OUT_DIR}/${name}.json"
    fi

    echo "INFO: dbsat report ${OUT_DIR}/${name} (JAVA_HOME=${JAVA_HOME})"
    (cd "${OUT_DIR}" && "${dbsat}" report -n "${OUT_DIR}/${name}") || rc=$?
    if [[ ${rc} -ne 0 ]]; then
        echo "ERROR: dbsat report failed (rc=${rc})" >&2
        return 1
    fi
    echo "INFO: DBSAT output in ${OUT_DIR}:"
    ls -l "${OUT_DIR}/${name}"*
}

main "$@"
# - EOF ------------------------------------------------------------------------
