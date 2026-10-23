#!/bin/bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: lib_java.sh
# Author.....: Stefan Oehrli (oes), stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026.10.23
# Revision...: v1.0.0
# Purpose....: Shared Java helpers for the assessment tools inside the
#              container (run_dbsat.sh, run_ciscat.sh): minimum versions,
#              Java major version, first usable JRE of a candidate list.
# Notes......: - Sourced from the directory of the calling script, not
#                executed. bash 4.4 (Oracle Linux 8 image).
#              - The host side keeps its own copy of the minimum versions
#                (scripts/lib_usecase.sh) and of java_major
#                (scripts/provide_jre.sh, runs java via docker exec) - keep
#                them in sync.
# Reference..: https://github.com/oehrlis/oracle-free-labs
# License....: Apache License Version 2.0, January 2004 as shown
#              at http://www.apache.org/licenses/
# ------------------------------------------------------------------------------
# shellcheck disable=SC2034 # constants and JAVA_FOUND_* are used by the sourcing scripts
set -euo pipefail

# keep in sync with DBSAT_MIN_JAVA / CISCAT_MIN_JAVA in scripts/lib_usecase.sh
readonly DBSAT_MIN_JAVA=17
readonly CISCAT_MIN_JAVA=21

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
# Function...: untrusted_file
# Purpose....: Print the first entry below $1 (incl. $1) that is not owned by
#              root or is world-writable (symlinks aside), empty if none
# ------------------------------------------------------------------------------
untrusted_file() {
    find "$1" \( ! -user root -o \( ! -type l -perm -0002 \) \) -print -quit 2> /dev/null || true
}

# ------------------------------------------------------------------------------
# Function...: resolve_java
# Purpose....: Find the first candidate with Java MIN+ and set JAVA_FOUND_DIR
#              and JAVA_FOUND_MAJOR; return 1 if none. Every rejected
#              candidate is reported (INFO, WARN for an untrusted JRE).
#              Usage: resolve_java [-r] MIN EXPLICIT_DIR DEFAULT_LIST
#              EXPLICIT_DIR (-j of the caller) replaces the list if set, else
#              $JAVA_HOME and the space separated DEFAULT_LIST are searched.
#              -r: refuse a JRE with an entry not owned by root or
#              world-writable (the caller runs java as root).
#              JAVA_CANDIDATES is set to the searched list (for messages).
# ------------------------------------------------------------------------------
resolve_java() {
    local root_only=false min explicit defaults candidates=() dir major bad
    if [[ "${1:-}" == -r ]]; then
        root_only=true
        shift
    fi
    min="$1" explicit="$2" defaults="$3"
    JAVA_FOUND_DIR=""
    JAVA_FOUND_MAJOR=""
    if [[ -n "${explicit}" ]]; then
        candidates=("${explicit}")
    else
        # shellcheck disable=SC2206 # fixed list without whitespace in paths
        candidates=(${JAVA_HOME:-} ${defaults})
    fi
    JAVA_CANDIDATES="${candidates[*]}"
    for dir in "${candidates[@]}"; do
        if [[ ! -x "${dir}/bin/java" ]]; then
            echo "INFO: no java in ${dir} - skipped"
            continue
        fi
        # root runs this java: a JRE that oracle (or anyone) can change is refused
        if [[ "${root_only}" == true ]]; then
            bad="$(untrusted_file "${dir}/")"
            if [[ -n "${bad}" ]]; then
                echo "WARN: JRE ${dir} refused - ${bad} has owner $(stat -c %U -- "${bad}"), mode" \
                    "$(stat -c %a -- "${bad}") (not root or world-writable); root must not run code another user can change"
                continue
            fi
        fi
        major="$(java_major "${dir}")"
        if [[ -n "${major}" && ${major} -ge ${min} ]]; then
            JAVA_FOUND_DIR="${dir}"
            JAVA_FOUND_MAJOR="${major}"
            return 0
        fi
        echo "INFO: Java ${major:-unknown} in ${dir} is older than ${min} - skipped"
    done
    return 1
}
# - EOF ------------------------------------------------------------------------
