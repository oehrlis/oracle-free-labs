#!/bin/bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: run_dbsat.sh
# Author.....: Stefan Oehrli (oes), stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026.10.15
# Revision...: v1.0.0
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
#              - Output: <out-dir>/dbsat_<pdb>.json and the reports
#                dbsat_<pdb>_report.{html,txt,xlsx,json}. Old files of the
#                same name are removed first and the removal is reported.
# Usage......: run_dbsat.sh -s SERVICE [-p PDB] [-u USER] [-e VAR] [-o DIR] [-n]
# Reference..: https://www.oracle.com/database/technologies/security/dbsat.html
# License....: Apache License Version 2.0, January 2004 as shown
#              at http://www.apache.org/licenses/
# ------------------------------------------------------------------------------
set -euo pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly COMMON_DIR="${COMMON_SCRIPTS_DIR:-/opt/oracle/common/scripts}"
readonly DBSAT_URL="https://www.oracle.com/database/technologies/security/dbsat.html"
ZIP_DIR="/opt/oracle/data/dbsat"
OUT_DIR="/opt/oracle/oradata/dbsat"
WORK_DIR="/tmp/dbsat"
SERVICE=""
PDB=""
DBSAT_USER="DBSAT_USER"
PWD_VAR="DBSAT_PWD"
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
  -n, --dry-run       Check prerequisites only, run nothing
  -h, --help          Show this help
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
# Function...: check_prereqs
# Purpose....: Report the runtime prerequisites of DBSAT in this image
# ------------------------------------------------------------------------------
check_prereqs() {
    local py
    if py="$(python3 --version 2>&1)"; then
        echo "INFO: reporter prerequisite python3: ${py}"
    else
        echo "ERROR: python3 not found - the DBSAT reporter needs Python 3" >&2
        return 1
    fi
    if [[ -x "${ORACLE_HOME}/jdk/bin/java" ]]; then
        echo "INFO: java (only for dbsat discover): ${ORACLE_HOME}/jdk/bin/java"
    else
        echo "WARN: no java under \$ORACLE_HOME/jdk - dbsat discover will not run (collect/report do not need it)"
    fi
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
    mkdir -p "${WORK_DIR}" "${OUT_DIR}"
    unzip -q "${zip}" -d "${WORK_DIR}"
    local dbsat="${WORK_DIR}/dbsat"
    if [[ ! -x "${dbsat}" ]]; then
        dbsat="$(find "${WORK_DIR}" -maxdepth 2 -name dbsat -type f | head -1)"
        chmod +x "${dbsat}"
    fi
    echo "INFO: DBSAT extracted to ${WORK_DIR}"

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

    echo "INFO: dbsat report ${OUT_DIR}/${name}"
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
