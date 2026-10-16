#!/bin/bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: set_sqlnet_param.sh
# Author.....: Stefan Oehrli (oes), stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026.10.15
# Revision...: v1.0.0
# Purpose....: Set one or more parameters in the server sqlnet.ora idempotently.
# Notes......: - Default file: the sqlnet.ora the Oracle Free image keeps under
#                $ORACLE_BASE/oradata/dbconfig/$ORACLE_SID. TNS_ADMIN
#                (/opt/oracle/network/admin) and $ORACLE_HOME/network/admin
#                both resolve to this file in the named services.
#              - Each parameter is reported as added, changed (old -> new) or
#                unchanged. Matching is case-insensitive on the name.
#              - New server processes read sqlnet.ora on connect; no restart.
# Usage......: set_sqlnet_param.sh [-f FILE] [-n] NAME=VALUE...
#              set_sqlnet_param.sh [-f FILE] --get NAME   (print value, read-only)
# Reference..: https://github.com/oehrlis/oracle-free-labs
# License....: Apache License Version 2.0, January 2004 as shown
#              at http://www.apache.org/licenses/
# ------------------------------------------------------------------------------
set -euo pipefail

readonly SCRIPT_NAME="${0##*/}"
SQLNET_FILE="${ORACLE_BASE:-/opt/oracle}/oradata/dbconfig/${ORACLE_SID:-FREE}/sqlnet.ora"
DRY_RUN=false
GET_NAME=""

# ------------------------------------------------------------------------------
# Function...: usage
# Purpose....: Print usage and exit
# ------------------------------------------------------------------------------
usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [options] NAME=VALUE...

Options:
  -f, --file FILE   sqlnet.ora to edit (default: ${SQLNET_FILE})
  -n, --dry-run     Show what would change, write nothing
  -g, --get NAME    Print the current value of NAME (empty if not set), read-only
  -h, --help        Show this help

Example:
  ${SCRIPT_NAME} SQLNET.ALLOWED_LOGON_VERSION_SERVER=11
EOF
    exit "${1:-0}"
}

# ------------------------------------------------------------------------------
# Function...: current_value
# Purpose....: Print the current value of parameter $1 (empty if not set)
# ------------------------------------------------------------------------------
current_value() {
    awk -v key="$1" '
        BEGIN { key = toupper(key) }
        /^[[:space:]]*#/ { next }
        {
            split($0, kv, "=")
            name = toupper(kv[1]); gsub(/[[:space:]]/, "", name)
            if (name == key) {
                value = substr($0, index($0, "=") + 1)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
                found = value
            }
        }
        END { print found }' "${SQLNET_FILE}"
}

# ------------------------------------------------------------------------------
# Function...: write_value
# Purpose....: Replace parameter $1 with value $2, or append it
# ------------------------------------------------------------------------------
write_value() {
    local tmp
    tmp="$(mktemp)"
    awk -v key="$1" -v val="$2" '
        BEGIN { key = toupper(key); done = 0 }
        /^[[:space:]]*#/ { print; next }
        {
            split($0, kv, "=")
            name = toupper(kv[1]); gsub(/[[:space:]]/, "", name)
            if (name == key) {
                if (!done) { print key " = " val; done = 1 }
                next
            }
            print
        }
        END { if (!done) print key " = " val }' "${SQLNET_FILE}" > "${tmp}"
    # Keep inode and permissions of the original file
    cat "${tmp}" > "${SQLNET_FILE}"
    rm -f "${tmp}"
}

# ------------------------------------------------------------------------------
# Function...: main
# Purpose....: Apply all NAME=VALUE pairs
# ------------------------------------------------------------------------------
main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f | --file) SQLNET_FILE="${2:?missing value for $1}"; shift 2 ;;
            -n | --dry-run) DRY_RUN=true; shift ;;
            -g | --get) GET_NAME="${2:?missing value for $1}"; shift 2 ;;
            -h | --help) usage 0 ;;
            -*) echo "ERROR: unknown option $1" >&2; usage 1 ;;
            *) break ;;
        esac
    done
    if [[ -n "${GET_NAME}" ]]; then
        if [[ ! -r "${SQLNET_FILE}" ]]; then
            echo "ERROR: ${SQLNET_FILE} not readable" >&2
            return 1
        fi
        current_value "${GET_NAME}"
        return 0
    fi
    if [[ $# -lt 1 ]]; then
        echo "ERROR: at least one NAME=VALUE is required" >&2
        usage 1
    fi

    if [[ ! -e "${SQLNET_FILE}" ]]; then
        if [[ "${DRY_RUN}" == true ]]; then
            echo "INFO: ${SQLNET_FILE} does not exist - would be created"
        else
            mkdir -p "$(dirname "${SQLNET_FILE}")"
            touch "${SQLNET_FILE}"
            echo "INFO: ${SQLNET_FILE} did not exist - created empty file"
        fi
    fi
    echo "INFO: ${SCRIPT_NAME} - editing ${SQLNET_FILE}"

    local pair name value old
    for pair in "$@"; do
        if [[ "${pair}" != *=* ]]; then
            echo "ERROR: expected NAME=VALUE, got '${pair}'" >&2
            return 1
        fi
        name="${pair%%=*}"
        value="${pair#*=}"
        old=""
        if [[ -e "${SQLNET_FILE}" ]]; then
            old="$(current_value "${name}")"
        fi
        if [[ "${old}" == "${value}" ]]; then
            echo "INFO: ${name} = ${value} (unchanged)"
            continue
        fi
        if [[ "${DRY_RUN}" == true ]]; then
            echo "INFO: would set ${name}: '${old:-<not set>}' -> '${value}'"
            continue
        fi
        write_value "${name}" "${value}"
        echo "INFO: ${name}: '${old:-<not set>}' -> '${value}'"
    done
}

main "$@"
# - EOF ------------------------------------------------------------------------
