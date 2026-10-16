#!/bin/bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: seclab_verify.sh
# Author.....: Stefan Oehrli (oes), stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026.10.15
# Revision...: v1.0.0
# Purpose....: seclab - read-only verification of the scenario catalog.
#              Prints PRESENT / ABSENT / NOT REPRODUCIBLE per scenario ID.
# Notes......: - Runs inside the seclab container as oracle (make verify-seclab).
#              - Reads sqlnet.ora, then runs seclab_verify.sql in the PDB.
#              - Every expected ID must appear exactly once; a missing line is
#                an error, not a pass.
#              - Exit codes: 0 all present (or documented not reproducible),
#                1 at least one ABSENT, 2 verification could not run.
# Usage......: seclab_verify.sh [-p PDB] [-h]
# Reference..: https://github.com/oehrlis/oracle-free-labs
# License....: Apache License Version 2.0, January 2004 as shown
#              at http://www.apache.org/licenses/
# ------------------------------------------------------------------------------
set -euo pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly COMMON_DIR="${COMMON_SCRIPTS_DIR:-/opt/oracle/common/scripts}"
readonly EXPECTED_IDS=(S01 S02 S03 S04 S05 S06 S07 S08 S09 S10 S11)
PDB="SECPDB1"

# ------------------------------------------------------------------------------
# Function...: usage
# Purpose....: Print usage and exit
# ------------------------------------------------------------------------------
usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [-p PDB] [-h]

Read-only check of the seclab scenarios. Exit 0 = all present,
1 = at least one ABSENT, 2 = check could not run.

  -p, --pdb PDB   PDB to check (default: ${PDB})
  -h, --help      Show this help
EOF
    exit "${1:-0}"
}

# ------------------------------------------------------------------------------
# Function...: sqlnet_value
# Purpose....: Print a sqlnet.ora value, empty if not set
# ------------------------------------------------------------------------------
sqlnet_value() {
    "${COMMON_DIR}/set_sqlnet_param.sh" --get "$1"
}

# ------------------------------------------------------------------------------
# Function...: main
# Purpose....: Run the checks and derive the exit code
# ------------------------------------------------------------------------------
main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p | --pdb) PDB="${2:?missing value for $1}"; shift 2 ;;
            -h | --help) usage 0 ;;
            *) echo "ERROR: unknown option $1" >&2; usage 2 ;;
        esac
    done

    local alvs enc chk
    if ! alvs="$(sqlnet_value SQLNET.ALLOWED_LOGON_VERSION_SERVER)" \
        || ! enc="$(sqlnet_value SQLNET.ENCRYPTION_SERVER)" \
        || ! chk="$(sqlnet_value SQLNET.CRYPTO_CHECKSUM_SERVER)"; then
        echo "ERROR: could not read sqlnet.ora" >&2
        return 2
    fi

    local output rc=0
    output="$("${ORACLE_HOME}/bin/sqlplus" -s -L "/ as sysdba" 2>&1 << SQL
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET LINESIZE 1000 TRIMOUT ON
ALTER SESSION SET CONTAINER=${PDB};
@${COMMON_DIR}/seclab_verify.sql "${alvs}" "${enc}" "${chk}"
EXIT
SQL
)" || rc=$?
    if [[ ${rc} -ne 0 ]] || grep -Eq '^(ORA|SP2)-[0-9]{4,5}' <<< "${output}"; then
        echo "${output}"
        echo "ERROR: verification query failed (rc=${rc})" >&2
        return 2
    fi

    echo "seclab verification - PDB ${PDB} - $(date '+%Y-%m-%d %H:%M:%S')"
    local id line count present=0 absent=0 notrepro=0 missing=0
    for id in "${EXPECTED_IDS[@]}"; do
        count=0
        line=""
        while IFS= read -r l; do
            case "${l}" in
                "${id} "*) count=$((count + 1)); line="${l}" ;;
            esac
        done <<< "${output}"
        if [[ ${count} -ne 1 ]]; then
            echo "${id} MISSING - expected exactly one result line, got ${count}"
            missing=$((missing + 1))
            continue
        fi
        echo "${line}"
        case "${line}" in
            "${id} PRESENT"*) present=$((present + 1)) ;;
            "${id} NOT REPRODUCIBLE"*) notrepro=$((notrepro + 1)) ;;
            *) absent=$((absent + 1)) ;;
        esac
    done

    echo "Summary: ${present} PRESENT, ${absent} ABSENT, ${notrepro} NOT REPRODUCIBLE, ${missing} MISSING"
    if [[ ${missing} -gt 0 ]]; then
        return 2
    fi
    if [[ ${absent} -gt 0 ]]; then
        return 1
    fi
    return 0
}

main "$@"
# - EOF ------------------------------------------------------------------------
