#!/bin/bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: run_sql_script.sh
# Author.....: Stefan Oehrli (oes), stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026.10.15
# Revision...: v1.0.0
# Purpose....: Run a SQL*Plus script as SYSDBA, optionally inside a PDB, with
#              the standard logging and container guards. Values that must not
#              live in code (passwords) are passed by environment variable name.
# Notes......: - Generates the same wrapper a setup/*.sql file would contain:
#                WHENEVER SQLERROR EXIT, define_logging_begin/end, require_pdb
#                or require_cdb_root.
#              - Arguments are passed to SQL*Plus on stdin, never on the
#                command line of sqlplus, so they do not show up in ps.
#              - Output is captured first and then checked, so neither a pipe
#                nor a missing script (SP2-0310) can hide a failure.
#              - Can be called from a sourced setup wrapper: it is a separate
#                process, its exit does not end the caller.
# Usage......: run_sql_script.sh [-p PDB] [-l LOG_PREFIX] [-e VAR]... SCRIPT [ARG]...
# Reference..: https://github.com/oehrlis/oracle-free-labs
# License....: Apache License Version 2.0, January 2004 as shown
#              at http://www.apache.org/licenses/
# ------------------------------------------------------------------------------
set -euo pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly COMMON_DIR="${COMMON_SCRIPTS_DIR:-/opt/oracle/common/scripts}"
readonly LOG_DIR="${SQL_LOG_DIR:-/opt/oracle/scripts/logs}"

PDB=""
LOG_PREFIX=""
DRY_RUN=false
ENV_VARS=()

# ------------------------------------------------------------------------------
# Function...: usage
# Purpose....: Print usage and exit
# ------------------------------------------------------------------------------
usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [options] SCRIPT [ARG]...

Run SCRIPT as SYSDBA with logging and container guards.

Options:
  -p, --pdb PDB         Switch to PDB before running SCRIPT (default: CDB\$ROOT)
  -l, --log-prefix STR  Log file prefix (default: basename of SCRIPT)
  -e, --env VAR         Append the value of environment variable VAR as an
                        argument after the positional ARGs (repeatable).
                        Fails if VAR is unset or empty.
  -n, --dry-run         Print the generated SQL*Plus input, values masked
  -h, --help            Show this help

Example:
  ${SCRIPT_NAME} -p SECPDB1 -e SECLAB_USER_PWD seclab_accounts.sql
EOF
    exit "${1:-0}"
}

# ------------------------------------------------------------------------------
# Function...: parse_args
# Purpose....: Parse command line arguments into globals
# ------------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p | --pdb) PDB="${2:?missing value for $1}"; shift 2 ;;
            -l | --log-prefix) LOG_PREFIX="${2:?missing value for $1}"; shift 2 ;;
            -e | --env) ENV_VARS+=("${2:?missing value for $1}"); shift 2 ;;
            -n | --dry-run) DRY_RUN=true; shift ;;
            -h | --help) usage 0 ;;
            --) shift; break ;;
            -*) echo "ERROR: unknown option $1" >&2; usage 1 ;;
            *) break ;;
        esac
    done
    if [[ $# -lt 1 ]]; then
        echo "ERROR: SCRIPT is required" >&2
        usage 1
    fi
    SQL_SCRIPT="$1"
    shift
    SQL_ARGS=("$@")
}

# ------------------------------------------------------------------------------
# Function...: build_input
# Purpose....: Write the SQL*Plus input to stdout. $1 = true masks env values.
# ------------------------------------------------------------------------------
build_input() {
    local mask="$1"
    local call="@${SQL_SCRIPT}"
    local arg var value
    for arg in "${SQL_ARGS[@]+"${SQL_ARGS[@]}"}"; do
        call+=" \"${arg}\""
    done
    for var in "${ENV_VARS[@]+"${ENV_VARS[@]}"}"; do
        value="${!var:-}"
        if [[ "${mask}" == true ]]; then
            value="***"
        fi
        call+=" \"${value}\""
    done

    echo "WHENEVER SQLERROR EXIT SQL.SQLCODE"
    echo "SET LINESIZE 256 PAGESIZE 1000"
    echo "SET SERVEROUTPUT ON FEEDBACK ON ECHO OFF TERMOUT ON VERIFY OFF"
    if [[ -n "${PDB}" ]]; then
        echo "ALTER SESSION SET CONTAINER=${PDB};"
    fi
    echo "DEFINE LOG_PREFIX = '${LOG_PREFIX}'"
    echo "DEFINE LOG_DIR = '${LOG_DIR}'"
    echo "@${COMMON_DIR}/define_logging_begin.sql"
    if [[ -n "${PDB}" ]]; then
        echo "@${COMMON_DIR}/require_pdb.sql"
    else
        echo "@${COMMON_DIR}/require_cdb_root.sql"
    fi
    echo "SET VERIFY OFF"
    echo "${call}"
    echo "@${COMMON_DIR}/define_logging_end.sql"
    echo "EXIT"
}

# ------------------------------------------------------------------------------
# Function...: main
# Purpose....: Validate input, run SQL*Plus, check the captured output
# ------------------------------------------------------------------------------
main() {
    parse_args "$@"

    # Resolve bare script names against the common scripts directory
    if [[ "${SQL_SCRIPT}" != /* ]]; then
        SQL_SCRIPT="${COMMON_DIR}/${SQL_SCRIPT}"
    fi
    if [[ -z "${LOG_PREFIX}" ]]; then
        LOG_PREFIX="$(basename "${SQL_SCRIPT}" .sql)"
        if [[ -n "${PDB}" ]]; then
            LOG_PREFIX="${LOG_PREFIX}_${PDB,,}"
        fi
    fi

    local var
    for var in "${ENV_VARS[@]+"${ENV_VARS[@]}"}"; do
        if [[ -z "${!var:-}" ]]; then
            echo "ERROR: environment variable ${var} is not set or empty (see .env.example)" >&2
            return 1
        fi
        if [[ "${!var:-}" == *[\"\']* ]]; then
            echo "ERROR: value of ${var} must not contain a quote character (' or \")" >&2
            return 1
        fi
    done

    if [[ "${DRY_RUN}" == true ]]; then
        echo "INFO: dry run - SQL*Plus input for ${SQL_SCRIPT}, nothing executed"
        build_input true
        return 0
    fi

    if [[ ! -r "${SQL_SCRIPT}" ]]; then
        echo "ERROR: SQL script not found: ${SQL_SCRIPT}" >&2
        return 1
    fi

    echo "INFO: ${SCRIPT_NAME} - ${SQL_SCRIPT} in ${PDB:-CDB\$ROOT}"
    local output rc=0
    output="$(build_input false | "${ORACLE_HOME}/bin/sqlplus" -s -L "/ as sysdba" 2>&1)" || rc=$?
    echo "${output}"

    if [[ ${rc} -ne 0 ]]; then
        echo "ERROR: ${SQL_SCRIPT} failed with SQL*Plus exit code ${rc}" >&2
        return "${rc}"
    fi
    if grep -Eq '^(ORA|SP2)-[0-9]{4,5}' <<< "${output}"; then
        echo "ERROR: ${SQL_SCRIPT} reported ORA-/SP2- errors (see output above)" >&2
        return 1
    fi
    echo "INFO: ${SQL_SCRIPT} completed"
}

main "$@"
# - EOF ------------------------------------------------------------------------
