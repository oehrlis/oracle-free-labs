#!/bin/bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: seclab_set_admin_pwd.sh
# Author.....: Stefan Oehrli (oes), stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026.10.20
# Revision...: v1.0.0
# Purpose....: Set SYS, SYSTEM and PDBADMIN (every open PDB that has it) to
#              the ORACLE_PWD of the container environment.
# Notes......: - The Oracle image applies ORACLE_PWD only when it creates the
#                database. After a rotation (SECLAB_ORACLE_PWD in .env and a
#                recreated container) this brings the database in line.
#              - Password from the environment, fed to sqlplus on stdin - never
#                on the command line. A '"' in the password is refused.
#              - ALTER USER SYS also updates the password file.
#              - Runs as oracle inside the container (OS authentication).
# Usage......: seclab_set_admin_pwd.sh [-e VAR] [-n]
# Reference..: doc/seclab-runbook.md (Rotate Passwords)
# License....: Apache License Version 2.0, January 2004 as shown
#              at http://www.apache.org/licenses/
# ------------------------------------------------------------------------------
set -euo pipefail

readonly SCRIPT_NAME="${0##*/}"
PWD_VAR="ORACLE_PWD"
DRY_RUN=false

# ------------------------------------------------------------------------------
# Function...: usage
# Purpose....: Print usage and exit
# ------------------------------------------------------------------------------
usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [-e VAR] [-n] [-h]

  -e, --env VAR       Environment variable with the new password (default: ${PWD_VAR})
  -n, --dry-run       List the accounts, change nothing
  -h, --help          Show this help
EOF
    exit "${1:-0}"
}

# ------------------------------------------------------------------------------
# Function...: run_sql
# Purpose....: Run SQL from stdin as SYSDBA, fail on the first error
# ------------------------------------------------------------------------------
run_sql() {
    "${ORACLE_HOME}/bin/sqlplus" -s -L / as sysdba
}

# ------------------------------------------------------------------------------
# Function...: main
# Purpose....: Set the common accounts in the root, PDBADMIN per open PDB
# ------------------------------------------------------------------------------
main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -e | --env) PWD_VAR="${2:?missing value for $1}"; shift 2 ;;
            -n | --dry-run) DRY_RUN=true; shift ;;
            -h | --help) usage 0 ;;
            *) echo "ERROR: unknown option $1" >&2; usage 1 ;;
        esac
    done
    local pwd="${!PWD_VAR:-}"
    if [[ -z "${pwd}" ]]; then
        echo "ERROR: ${PWD_VAR} is not set or empty" >&2
        return 1
    fi
    if [[ "${pwd}" == *\"* ]]; then
        echo "ERROR: ${PWD_VAR} contains '\"' - not usable in IDENTIFIED BY \"...\"" >&2
        return 1
    fi

    local pdbs pdb
    pdbs="$(run_sql << 'SQL'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0
WHENEVER SQLERROR EXIT SQL.SQLCODE
SELECT p.name FROM v$pdbs p
 WHERE p.open_mode = 'READ WRITE' AND p.name <> 'PDB$SEED'
 ORDER BY p.name;
EXIT
SQL
)"
    if [[ "${DRY_RUN}" == true ]]; then
        echo "INFO: would set SYS, SYSTEM (root) and PDBADMIN in: $(echo ${pdbs:-none}) from ${PWD_VAR}"
        return 0
    fi

    run_sql << SQL > /dev/null
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER USER sys IDENTIFIED BY "${pwd}";
ALTER USER system IDENTIFIED BY "${pwd}";
EXIT
SQL
    echo "INFO: SYS and SYSTEM set from ${PWD_VAR}"

    local out rc
    for pdb in ${pdbs}; do
        rc=0
        out="$(run_sql << SQL
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET HEADING OFF FEEDBACK OFF
ALTER SESSION SET CONTAINER = ${pdb};
-- after the container switch: DBMS_OUTPUT is enabled per container
SET SERVEROUTPUT ON
DECLARE
    l_cnt PLS_INTEGER;
BEGIN
    SELECT COUNT(*) INTO l_cnt FROM dba_users WHERE username = 'PDBADMIN';
    IF l_cnt = 1 THEN
        EXECUTE IMMEDIATE 'ALTER USER pdbadmin IDENTIFIED BY "${pwd}"';
        dbms_output.put_line('PDBADMIN_SET');
    ELSE
        dbms_output.put_line('PDBADMIN_NONE');
    END IF;
END;
/
EXIT
SQL
)" || rc=$?
        case "${rc}:${out}" in
            0:*PDBADMIN_SET*) echo "INFO: PDBADMIN in ${pdb} set from ${PWD_VAR}" ;;
            0:*PDBADMIN_NONE*) echo "INFO: no PDBADMIN in ${pdb} - nothing to set" ;;
            *)
                echo "ERROR: setting PDBADMIN in ${pdb} failed (rc=${rc}): ${out//${pwd}/***}" >&2
                return 1
                ;;
        esac
    done
}

main "$@"
# - EOF ------------------------------------------------------------------------
