#!/bin/bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: seclab_simulate_logins.sh
# Author.....: Stefan Oehrli (oes), stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026.10.15
# Revision...: v1.0.0
# Purpose....: seclab - log in once over the listener with the accounts that
#              are "in use", so that DBA_USERS.LAST_LOGIN separates them from
#              the never-used accounts of scenario S06.
# Notes......: *** INTENTIONALLY INSECURE - lab use only ***
#              - Password from SECLAB_USER_PWD (environment, never argv).
#              - OLD_APP and TEST_USER are deliberately left out (S06).
#              - The LEGACY_APP login also proves that the legacy verifier of
#                S03 is accepted by the server.
# Usage......: seclab_simulate_logins.sh [-s SERVICE] [-n]
# Reference..: https://github.com/oehrlis/oracle-free-labs
# License....: Apache License Version 2.0, January 2004 as shown
#              at http://www.apache.org/licenses/
# ------------------------------------------------------------------------------
set -euo pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly ACTIVE_USERS=(APP_OWNER SVC_BATCH DEV_USER1 ANALYST1 LEGACY_APP)
SERVICE="SECPDB1"
DRY_RUN=false

# ------------------------------------------------------------------------------
# Function...: usage
# Purpose....: Print usage and exit
# ------------------------------------------------------------------------------
usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [-s SERVICE] [-n] [-h]

  -s, --service NAME  Service name of the seclab PDB (default: ${SERVICE})
  -n, --dry-run       List the logins, do not connect
  -h, --help          Show this help
EOF
    exit "${1:-0}"
}

# ------------------------------------------------------------------------------
# Function...: main
# Purpose....: Connect once per active account, fail on the first error
# ------------------------------------------------------------------------------
main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -s | --service) SERVICE="${2:?missing value for $1}"; shift 2 ;;
            -n | --dry-run) DRY_RUN=true; shift ;;
            -h | --help) usage 0 ;;
            *) echo "ERROR: unknown option $1" >&2; usage 1 ;;
        esac
    done
    if [[ -z "${SECLAB_USER_PWD:-}" ]]; then
        echo "ERROR: SECLAB_USER_PWD is not set or empty (see .env.example)" >&2
        return 1
    fi

    local user output rc failed=0
    for user in "${ACTIVE_USERS[@]}"; do
        if [[ "${DRY_RUN}" == true ]]; then
            echo "INFO: would log in as ${user}@//localhost:1521/${SERVICE}"
            continue
        fi
        rc=0
        output="$("${ORACLE_HOME}/bin/sqlplus" -s -L /nolog 2>&1 << SQL
WHENEVER SQLERROR EXIT SQL.SQLCODE
CONNECT ${user}/"${SECLAB_USER_PWD}"@//localhost:1521/${SERVICE}
SELECT 'LOGIN_OK' FROM dual;
EXIT
SQL
)" || rc=$?
        if [[ ${rc} -eq 0 && "${output}" == *LOGIN_OK* ]]; then
            echo "INFO: login as ${user} OK"
        else
            echo "ERROR: login as ${user} failed (rc=${rc}): ${output}" >&2
            failed=1
        fi
    done
    return "${failed}"
}

main "$@"
# - EOF ------------------------------------------------------------------------
