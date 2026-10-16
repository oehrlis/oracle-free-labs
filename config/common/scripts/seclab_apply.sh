#!/bin/bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: seclab_apply.sh
# Author.....: Stefan Oehrli (oes), stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026.10.15
# Revision...: v1.0.0
# Purpose....: seclab - apply the whole intentionally insecure security
#              baseline (scenarios S01-S11) to an existing PDB and verify it.
# Notes......: *** INTENTIONALLY INSECURE - lab use only ***
#              - Single entry point for both paths:
#                * seclab service setup (config/seclab/setup/20_*.sh)
#                * any running Oracle Database Free container, also the plain
#                  image from Oracle (scripts/apply_usecase.sh seclab ...)
#              - Creates no PDB and drops none. Works on FREEPDB1 by default.
#              - S10 needs an instance restart (static parameter). Use
#                --no-restart to skip it; S10 then stays ABSENT and is named.
#              - Rerunnable: accounts are dropped and recreated, existing
#                demo schemas and audit policies are kept and reported.
#              - Needs SECLAB_USER_PWD and SECLAB_SCOTT_PWD in the environment.
#              - Exit code is the exit code of seclab_verify.sh (0/1/2), or 3
#                if a step failed.
# Usage......: seclab_apply.sh [-p PDB] [-s SERVICE] [--no-restart] [-n] [-h]
# Reference..: doc/seclab.md
# License....: Apache License Version 2.0, January 2004 as shown
#              at http://www.apache.org/licenses/
# ------------------------------------------------------------------------------
set -Eeuo pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly COMMON_DIR="${COMMON_SCRIPTS_DIR:-/opt/oracle/common/scripts}"
readonly RUN="${COMMON_DIR}/run_sql_script.sh"
# Lowest logon version that still changes anything on 23.26: 8 and 10 produce
# the same verifier set (11G 12C) as 11 - see doc/seclab.md, S03.
readonly SECLAB_ALVS="11"

PDB="${ORACLE_PDB:-FREEPDB1}"
SERVICE=""
RESTART=true
DRY_RUN=false
STEP=0
readonly STEPS=10

# ------------------------------------------------------------------------------
# Function...: usage
# Purpose....: Print usage and exit
# ------------------------------------------------------------------------------
usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [options]

Apply the seclab scenarios S01-S11 to an existing PDB, then verify them.
INTENTIONALLY INSECURE - lab use only.

Options:
  -p, --pdb PDB         Target PDB (default: \$ORACLE_PDB or FREEPDB1, now ${PDB})
  -s, --service NAME    Listener service of the PDB (default: PDB name)
      --no-restart      Do not restart the instance; S10 is skipped and reported
  -n, --dry-run         Show the steps, change nothing
  -h, --help            Show this help

Environment: SECLAB_USER_PWD, SECLAB_SCOTT_PWD (required)
EOF
    exit "${1:-0}"
}

# ------------------------------------------------------------------------------
# Function...: step
# Purpose....: Print a step header
# ------------------------------------------------------------------------------
step() {
    STEP=$((STEP + 1))
    echo ""
    echo "=== seclab step ${STEP}/${STEPS}: $* ==="
}

# ------------------------------------------------------------------------------
# Function...: run
# Purpose....: Run a command, or print it in dry-run mode
# ------------------------------------------------------------------------------
run() {
    if [[ "${DRY_RUN}" == true ]]; then
        echo "DRY-RUN: $*"
        return 0
    fi
    "$@"
}

# ------------------------------------------------------------------------------
# Function...: sql_value
# Purpose....: Print the single value of query $1, run in the target PDB
# ------------------------------------------------------------------------------
sql_value() {
    local output rc=0
    output="$("${ORACLE_HOME}/bin/sqlplus" -s -L "/ as sysdba" 2>&1 << SQL
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 VERIFY OFF
ALTER SESSION SET CONTAINER=${PDB};
$1
EXIT
SQL
)" || rc=$?
    if [[ ${rc} -ne 0 ]]; then
        echo "ERROR: query failed in ${PDB}: ${output}" >&2
        return 1
    fi
    output="${output//[[:space:]]/}"
    echo "${output}"
}

# ------------------------------------------------------------------------------
# Function...: open_pdb
# Purpose....: Make sure the target PDB is open read write and keeps its state
# ------------------------------------------------------------------------------
open_pdb() {
    local output rc=0
    output="$("${ORACLE_HOME}/bin/sqlplus" -s -L "/ as sysdba" 2>&1 << SQL
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET SERVEROUTPUT ON FEEDBACK OFF
DECLARE
  l_mode v\$pdbs.open_mode%TYPE;
BEGIN
  SELECT open_mode INTO l_mode FROM v\$pdbs WHERE name = UPPER('${PDB}');
  IF l_mode <> 'READ WRITE' THEN
    EXECUTE IMMEDIATE 'ALTER PLUGGABLE DATABASE ${PDB} OPEN READ WRITE';
    dbms_output.put_line('- ${PDB} was ' || l_mode || ', opened read write');
  ELSE
    dbms_output.put_line('- ${PDB} is open read write');
  END IF;
  EXECUTE IMMEDIATE 'ALTER PLUGGABLE DATABASE ${PDB} SAVE STATE';
  dbms_output.put_line('- ${PDB} state saved');
END;
/
EXIT
SQL
)" || rc=$?
    echo "${output}"
    if [[ ${rc} -ne 0 ]]; then
        echo "ERROR: could not open PDB ${PDB} (does it exist?)" >&2
        return 1
    fi
}

# ------------------------------------------------------------------------------
# Function...: parse_args
# Purpose....: Parse command line arguments into globals
# ------------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p | --pdb) PDB="${2:?missing value for $1}"; shift 2 ;;
            -s | --service) SERVICE="${2:?missing value for $1}"; shift 2 ;;
            --no-restart) RESTART=false; shift ;;
            -n | --dry-run) DRY_RUN=true; shift ;;
            -h | --help) usage 0 ;;
            *) echo "ERROR: unknown option $1" >&2; usage 3 ;;
        esac
    done
    PDB="${PDB^^}"
    SERVICE="${SERVICE:-${PDB}}"
}

# ------------------------------------------------------------------------------
# Function...: apply_scenarios
# Purpose....: All steps up to the logins; returns non-zero on the first failure
# ------------------------------------------------------------------------------
apply_scenarios() {
    local count

    step "S03/S09 sqlnet.ora (logon version ${SECLAB_ALVS}, network encryption optional)"
    run "${COMMON_DIR}/set_sqlnet_param.sh" \
        "SQLNET.ALLOWED_LOGON_VERSION_SERVER=${SECLAB_ALVS}" \
        SQLNET.ENCRYPTION_SERVER=ACCEPTED \
        SQLNET.CRYPTO_CHECKSUM_SERVER=ACCEPTED

    step "S10 static parameter SQL92_SECURITY=FALSE (instance restart)"
    if [[ "${RESTART}" == true ]]; then
        run "${RUN}" set_static_param.sql sql92_security FALSE
    else
        echo "WARN: S10 skipped (--no-restart). It stays ABSENT until you run:"
        echo "WARN:   ${RUN} set_static_param.sql sql92_security FALSE"
    fi

    step "PDB ${PDB} open read write"
    run open_pdb

    step "USERS tablespace and OraDBA audit policies in ${PDB}"
    if [[ "${DRY_RUN}" == true ]]; then
        echo "DRY-RUN: create_ts_users.sql USERS (keeps an existing USERS tablespace)"
        echo "DRY-RUN: create_audit_policies.sql unless ORADBA_LOC_* policies exist"
    else
        "${RUN}" -p "${PDB}" create_ts_users.sql USERS 20480K
        count="$(sql_value "SELECT COUNT(DISTINCT policy_name) FROM audit_unified_policies WHERE policy_name LIKE 'ORADBA_LOC%';")"
        if [[ "${count}" == "0" ]]; then
            "${RUN}" -p "${PDB}" create_audit_policies.sql
        else
            echo "INFO: ${count} ORADBA_LOC_* audit policies already exist in ${PDB} - not recreated"
        fi
    fi

    step "Demo schemas SCOTT and TVD_HR"
    if [[ "${DRY_RUN}" == true ]]; then
        echo "DRY-RUN: create_scott.sql unless SCOTT exists, create_tvd_hr.sql (drops and recreates TVD_HR)"
    else
        count="$(sql_value "SELECT COUNT(*) FROM dba_users WHERE username = 'SCOTT';")"
        if [[ "${count}" == "0" ]]; then
            "${RUN}" -p "${PDB}" create_scott.sql
        else
            echo "INFO: SCOTT already exists in ${PDB} - schema kept, password handled by S11"
        fi
        "${RUN}" -p "${PDB}" create_tvd_hr.sql
    fi

    step "Accounts, weak profile and application schema (S03, S04, S06 base)"
    run "${RUN}" -p "${PDB}" -e SECLAB_USER_PWD seclab_accounts.sql

    step "Scenarios S01, S02, S05, S06, S07"
    run "${RUN}" -p "${PDB}" seclab_s01_public_grants.sql INSECURE
    run "${RUN}" -p "${PDB}" seclab_s02_utl_file_dependency.sql
    run "${RUN}" -p "${PDB}" seclab_s05_overprivileged.sql
    run "${RUN}" -p "${PDB}" seclab_s06_unused_accounts.sql INSECURE
    run "${RUN}" -p "${PDB}" seclab_s07_audit_gaps.sql

    step "S11 SCOTT with default password"
    run "${RUN}" -p "${PDB}" -e SECLAB_SCOTT_PWD seclab_s11_default_password.sql INSECURE

    step "Logins of the accounts in use (service ${SERVICE})"
    run "${COMMON_DIR}/seclab_simulate_logins.sh" -s "${SERVICE}"
}

# ------------------------------------------------------------------------------
# Function...: main
# Purpose....: Validate, apply, verify
# ------------------------------------------------------------------------------
main() {
    parse_args "$@"

    local var missing=0
    for var in SECLAB_USER_PWD SECLAB_SCOTT_PWD; do
        if [[ -z "${!var:-}" ]]; then
            echo "ERROR: ${var} is not set or empty (see .env.example)" >&2
            missing=1
        fi
    done
    if [[ ${missing} -ne 0 ]]; then
        return 3
    fi

    export SQL_LOG_DIR="${SQL_LOG_DIR:-/opt/oracle/scripts/logs}"
    if [[ "${DRY_RUN}" == false ]]; then
        mkdir -p "${SQL_LOG_DIR}"
    fi

    echo "seclab apply - PDB ${PDB}, service ${SERVICE}, restart ${RESTART}, logs ${SQL_LOG_DIR}"
    echo "*** INTENTIONALLY INSECURE - lab use only ***"
    local started=${SECONDS}
    # Called plainly, not in "if !" or "||": both would switch off errexit
    # inside the function. The ERR trap turns the first failure into exit 3.
    trap 'echo "ERROR: seclab apply stopped in step ${STEP}/${STEPS} - see output above" >&2; exit 3' ERR
    apply_scenarios
    trap - ERR

    step "Verification"
    local rc=0
    run "${COMMON_DIR}/seclab_verify.sh" -p "${PDB}" || rc=$?
    echo "seclab apply finished in $((SECONDS - started))s, verification exit code ${rc}"
    return "${rc}"
}

main "$@"
# - EOF ------------------------------------------------------------------------
