#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: 65_pdb_p4_remote.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026-09-04
# Version....: 0.1.0
# Purpose....: PDB P4 - Remote clone of PDBCLONE via DB link (c##clone user),
#              then export/import keys separately.
#              The c##clone password is never written to disk and never put on
#              the command line. It is read into memory, passed to the container
#              via stdin, and dropped again - "docker exec bash -c" would put it
#              in the host process list, where any local user can read it.
#              Steps:
#              1. Read the c##clone credential into memory (prod container)
#              2. Drop DB link prod_cdb_link in dev if exists
#              3. Create DB link prod_cdb_link in dev using c##clone credentials
#              4. Drop PDBCLONE_P4 in dev if exists
#              5. CREATE PLUGGABLE DATABASE PDBCLONE_P4 FROM PDBCLONE@prod_cdb_link
#              6. Export PDBCLONE keys from prod to xchange
#              7. Import keys into dev keystore
#              8. Delete temp credential file
#              9. Open PDBCLONE_P4 READ WRITE, verify canary
#             10. Collect evidence, compare vs pdb_baseline
# Notes......: Prerequisite: step 61 (PDB testbed).
#              DB link uses service FREE.oradba.ch (not FREE) and the internal
#              Docker network (port 1521, host odbencprod).
#              If the DB link creation fails with ORA-01017, check that
#              c##clone was created in step 61 and that ORACLE_PWD is set
#              identically in both containers.
# Reference..: https://github.com/oehrlis/oracle-free-labs
# License....: Apache License Version 2.0, January 2004 as shown
#              at http://www.apache.org/licenses/
# ------------------------------------------------------------------------------
# CHANGE LOG:
# 2026-09-04  oes  Initial release                                        0.1.0
# ------------------------------------------------------------------------------

set -euo pipefail
SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="0.1.0"
VERBOSE=${VERBOSE:-"FALSE"}
DRY_RUN=${DRY_RUN:-"FALSE"}
FORCE_YES=${FORCE_YES:-"FALSE"}
CANARY_MARKER="OEHRLI-CANARY-2026-09-03"
CLONE_SRC_PDB="PDBCLONE"
CLONE_TS_ENC="CLONE_ENC"
CLONE_USER="c##clone"
CLONE_P4_PDB="PDBCLONE_P4"
LABEL="pdb_p4_remote"
# Static lab constant for key export secret - not a production secret
# Transport secret, generated per run. A fixed value in the repository would
# be a committed secret even in a lab, and it adds nothing: the secret only
# has to match between the export and the import within this one run.
# head -c would exit after 24 bytes, tr would get SIGPIPE, and with
# pipefail set -e aborts the script before it prints a single line.
# openssl produces a finite stream and cut reads it to the end.
P4_KEY_SECRET="$(openssl rand -base64 48 | LC_ALL=C tr -dc "A-Za-z0-9" | cut -c1-24)"
DB_LINK="prod_cdb_link"
PROD_HOST="odbencprod"
PROD_PORT="1521"
PROD_SERVICE_NAME="FREE.oradba.ch"

# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
KEYS_FILE="${XCHANGE_CONTAINER}/pdbclone_p4_keys.exp"
# The clone password is never written to disk. /opt/oracle/xchange is a shared
# bind mount, so a credential file there would be readable by the target
# container and by anyone on the host - the opposite of what it looks like.
# It is read from the source container into a shell variable and handed to the
# target over stdin, so it appears neither in argv nor in a file.
CLONE_PWD=""

# ------------------------------------------------------------------------------
# usage
# ------------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

  PDB P4: remote clone of PDBCLONE via DB link (c##clone), then key import.
  Creates DB link prod_cdb_link in dev, clones PDBCLONE to PDBCLONE_P4,
  exports keys from prod, imports into dev keystore.
  Expected: canary readable after key import, ORIGIN=IMPORTED.

  Prerequisite: step 61 (PDB testbed) must have completed.
  DB link requires c##clone to exist in prod with CREATE SESSION and
  CREATE PLUGGABLE DATABASE granted CONTAINER=ALL.

Options:
  -h, --help      Show this help and exit
  -v, --verbose   Enable verbose output
  -d, --dry-run   Show what would be done; change nothing

Examples:
  ${SCRIPT_NAME} --dry-run
  ${SCRIPT_NAME} --verbose

EOF
}

# ------------------------------------------------------------------------------
# Parse arguments
# ------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)    usage; exit 0 ;;
        -v|--verbose) VERBOSE="TRUE"; shift ;;
        -d|--dry-run) DRY_RUN="TRUE"; shift ;;
        -y|--yes)     FORCE_YES="TRUE"; shift ;;
        *) lib_err "Unknown option: $1"; usage; exit 1 ;;
    esac
done

# ------------------------------------------------------------------------------
# cleanup_cred - remove temp credential file on exit
# ------------------------------------------------------------------------------
cleanup_cred() {
    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        CLONE_PWD=""  # drop the secret from memory
    fi
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
main() {
    lib_info "Starting ${SCRIPT_NAME} ${VERSION}"
    step_header "Step 65: PDB P4 - remote clone via DB link"

    require_command docker
    require_container "${PROD_SERVICE}"
    require_healthy   "${PROD_SERVICE}"
    # Ahead of both dev requirements. The RMAN variants leave dev as a restore
    # of prod - same DBID - with a CDB temp file that no longer verifies, and a
    # failed attempt can leave the container removed altogether. Those are the
    # very states require_container and require_healthy abort on, so the repair
    # has to come first. P2/P7/P8 claim a foreign CDB, which a restore of the
    # source is not, so rebuilding is part of the method.
    ensure_independent_dev_cdb
    require_container "${DEV_SERVICE}"
    require_healthy   "${DEV_SERVICE}"
    require_state "PDBCLONE_READY" "PDB testbed (run step 61 first)"

    # Register cleanup for temp cred file
    trap cleanup_cred EXIT

    # Phase 1: Read the c##clone password into memory - never to disk
    # PDBs are created in both containers here; without OMF every
    # CREATE PLUGGABLE DATABASE fails with ORA-65016.
    ensure_omf "${PROD_SERVICE}"
    ensure_omf "${DEV_SERVICE}"

    step_header "Phase 1: Prepare credential for DB link (prod container only)"
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        lib_info "DRY-RUN: would read the clone password from the source container"
    else
        CLONE_PWD=$(docker exec "${PROD_SERVICE}" bash -c 'printf %s "${ORACLE_PWD}"')
        if [[ -z "${CLONE_PWD}" ]]; then
            lib_err "could not read ORACLE_PWD from ${PROD_SERVICE}"
            exit 1
        fi
        lib_info "clone password read into memory, not written to disk"
    fi

    # Phase 2: Drop DB link if it exists and re-create
    step_header "Phase 2: Create DB link ${DB_LINK} in dev"
    # shellcheck disable=SC1078,SC1079
    lib_run in_dev_stdin '
sqlplus -S / as sysdba <<SQL 2>&1 | grep -viE "identified by"; _rc=${PIPESTATUS[0]}; [ "${_rc}" -eq 0 ] || { echo "ERROR: sqlplus exited ${_rc}" >&2; exit "${_rc}"; }
WHENEVER SQLERROR CONTINUE
DROP DATABASE LINK '"${DB_LINK}"';
WHENEVER SQLERROR EXIT SQL.SQLCODE
EXIT
SQL
sqlplus -S / as sysdba <<SQL 2>&1 | grep -viE "identified by"; _rc=${PIPESTATUS[0]}; [ "${_rc}" -eq 0 ] || { echo "ERROR: sqlplus exited ${_rc}" >&2; exit "${_rc}"; }
WHENEVER SQLERROR EXIT SQL.SQLCODE
CREATE DATABASE LINK '"${DB_LINK}"'
  -- The user name must not be quoted. Step 61 creates it unquoted, so Oracle
  -- stores C##CLONE in upper case; "c##clone" would name a different,
  -- non-existent user and the link fails with ORA-01017.
  CONNECT TO '"${CLONE_USER}"' IDENTIFIED BY "'"${CLONE_PWD}"'"
  USING '"'"'(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST='"${PROD_HOST}"')(PORT='"${PROD_PORT}"'))(CONNECT_DATA=(SERVICE_NAME='"${PROD_SERVICE_NAME}"')))'"'"';
SELECT '"'"'DB link test'"'"' AS link_status FROM dual@'"${DB_LINK}"';
EXIT
SQL
'

    # Phase 3: Drop PDBCLONE_P4 in dev if exists (idempotency)
    step_header "Phase 3: Prepare dev - drop ${CLONE_P4_PDB} if exists"
    sqlplus_dev "
WHENEVER SQLERROR CONTINUE
ALTER PLUGGABLE DATABASE ${CLONE_P4_PDB} CLOSE IMMEDIATE;
DROP PLUGGABLE DATABASE ${CLONE_P4_PDB} INCLUDING DATAFILES;
WHENEVER SQLERROR EXIT SQL.SQLCODE
SELECT 'dev cleanup done' AS status FROM dual;
EXIT
"

    # Phase 4: Remote clone via DB link. The KEYSTORE clause is required as
    # soon as the source carries encrypted tablespaces - measured on the local
    # clone in step 62, which failed with ORA-46697 without it. An auto-login
    # keystore does not satisfy this operation.
    step_header "Phase 4: CREATE ${CLONE_P4_PDB} FROM ${CLONE_SRC_PDB}@${DB_LINK}"
    # shellcheck disable=SC1078,SC1079
    lib_run in_dev_stdin '
KSPWD=$(cat '"${WALLET_DIR_CONTAINER}"'/wallet_pwd.txt)
sqlplus -S / as sysdba <<SQL 2>&1 | grep -viE "identified by"; _rc=${PIPESTATUS[0]}; [ "${_rc}" -eq 0 ] || { echo "ERROR: sqlplus exited ${_rc}" >&2; exit "${_rc}"; }
WHENEVER SQLERROR EXIT SQL.SQLCODE
CREATE PLUGGABLE DATABASE '"${CLONE_P4_PDB}"'
  FROM '"${CLONE_SRC_PDB}"'@'"${DB_LINK}"'
  KEYSTORE IDENTIFIED BY "${KSPWD}";
SELECT name, open_mode FROM v\$pdbs WHERE name='"'"''"${CLONE_P4_PDB}"''"'"';
EXIT
SQL
'

    # Phase 5: Export PDBCLONE keys from prod
    step_header "Phase 5: Export keys from prod for ${CLONE_SRC_PDB}"
    # shellcheck disable=SC1078,SC1079
    lib_run in_prod_stdin '
KSPWD=$(cat '"${WALLET_DIR_CONTAINER}"'/wallet_pwd.txt)
sqlplus -S / as sysdba <<SQL 2>&1 | grep -viE "identified by|with secret"; _rc=${PIPESTATUS[0]}; [ "${_rc}" -eq 0 ] || { echo "ERROR: sqlplus exited ${_rc}" >&2; exit "${_rc}"; }
WHENEVER SQLERROR EXIT SQL.SQLCODE
ADMINISTER KEY MANAGEMENT EXPORT KEYS WITH SECRET "'"${P4_KEY_SECRET}"'"
  TO '"'"''"${KEYS_FILE}"''"'"'
  FORCE KEYSTORE IDENTIFIED BY "${KSPWD}"
  WITH IDENTIFIER IN
  (SELECT key_id FROM v\$encryption_keys
    WHERE con_id = (SELECT con_id FROM v\$pdbs WHERE name='"'"''"${CLONE_SRC_PDB}"''"'"'));
SELECT '"'"'keys exported'"'"' AS status FROM dual;
EXIT
SQL
'

    # Phase 6: Import keys into dev keystore
    step_header "Phase 6: Import keys into dev keystore"
    # shellcheck disable=SC1078,SC1079
    lib_run in_dev_stdin '
KSPWD=$(cat '"${WALLET_DIR_CONTAINER}"'/wallet_pwd.txt)
sqlplus -S / as sysdba <<SQL 2>&1 | grep -viE "identified by|with secret"; _rc=${PIPESTATUS[0]}; [ "${_rc}" -eq 0 ] || { echo "ERROR: sqlplus exited ${_rc}" >&2; exit "${_rc}"; }
WHENEVER SQLERROR EXIT SQL.SQLCODE
ADMINISTER KEY MANAGEMENT IMPORT KEYS WITH SECRET "'"${P4_KEY_SECRET}"'"
  FROM '"'"''"${KEYS_FILE}"''"'"'
  FORCE KEYSTORE IDENTIFIED BY "${KSPWD}"
  WITH BACKUP;
SELECT '"'"'keys imported'"'"' AS status FROM dual;
EXIT
SQL
'

    # Phase 7: Clean up temp credential file (also done by trap)
    step_header "Phase 7: Remove temp credential file"
    cleanup_cred
    lib_info "Credential file removed"

    # Phase 8: Open PDBCLONE_P4 and verify canary
    step_header "Phase 8: Open ${CLONE_P4_PDB} and verify canary"
    sqlplus_dev "
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER PLUGGABLE DATABASE ${CLONE_P4_PDB} OPEN READ WRITE;
WHENEVER SQLERROR CONTINUE
ALTER SESSION SET CONTAINER=${CLONE_P4_PDB};
@/opt/oracle/common/scripts/ssenc_canary.sql ${CANARY_OWNER} ${CANARY_MARKER} CANARY_CLONEENC
WHENEVER SQLERROR EXIT SQL.SQLCODE
EXIT
"

    # Phase 9: Query key chain
    step_header "Phase 9: Query key chain in ${CLONE_P4_PDB}"
    sqlplus_dev "
SET HEADING ON FEEDBACK ON PAGESIZE 100 LINESIZE 200
ALTER SESSION SET CONTAINER=${CLONE_P4_PDB};
SELECT key_id, key_use, keystore_type, origin, backed_up
FROM v\$encryption_keys
WHERE con_id = sys_context('userenv','con_id')
ORDER BY creation_time;
SELECT RAWTOHEX(masterkeyid) AS masterkeyid,
       RAWTOHEX(encryptedkey) AS encryptedkey,
       key_version, encryptionalg
FROM v\$encrypted_tablespaces
WHERE ts# = (SELECT ts# FROM v\$tablespace WHERE name='${CLONE_TS_ENC}' AND con_id=sys_context('userenv','con_id'));
EXIT
"

    # Collect evidence
    step_header "Collect evidence set '${LABEL}'"
    collect_evidence "${DEV_SERVICE}" "${CLONE_P4_PDB}" "${LABEL}" "${CLONE_TS_ENC}"

    # Compare against pdb_baseline
    step_header "Compare '${LABEL}' vs 'pdb_baseline'"
    compare_evidence "pdb_baseline" "${LABEL}"

    # Read key values and ORIGIN
    local mkid_p4 tek_p4 kv_p4 origin_p4
    mkid_p4=""; tek_p4=""; kv_p4=""; origin_p4=""
    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        mkid_p4=$(get_masterkeyid "${DEV_SERVICE}" "${CLONE_P4_PDB}" "${CLONE_TS_ENC}")
        tek_p4=$(get_encryptedkey  "${DEV_SERVICE}" "${CLONE_P4_PDB}" "${CLONE_TS_ENC}")
        kv_p4=$(printf '%s\n' "
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 80 TRIMSPOOL ON
ALTER SESSION SET CONTAINER=${CLONE_P4_PDB};
SELECT key_version FROM v\$encrypted_tablespaces WHERE ts# = (SELECT ts# FROM v\$tablespace WHERE name='${CLONE_TS_ENC}' AND con_id=sys_context('userenv','con_id'));
EXIT" | docker exec -i "${DEV_SERVICE}" sqlplus -S / as sysdba 2>/dev/null \
            | awk 'NF && $1 ~ /^[0-9]+$/ { print $1; exit }')
        origin_p4=$(printf '%s\n' "
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 80 TRIMSPOOL ON
ALTER SESSION SET CONTAINER=${CLONE_P4_PDB};
SELECT origin FROM v\$encryption_keys
WHERE con_id = sys_context('userenv','con_id') AND rownum=1;
EXIT" | docker exec -i "${DEV_SERVICE}" sqlplus -S / as sysdba 2>/dev/null \
            | awk 'NF && /^[A-Z]+$/ { print $1; exit }')
    else
        mkid_p4="DRY-RUN-MKID"; tek_p4="DRY-RUN-TEK"; kv_p4="0"; origin_p4="IMPORTED"
    fi

    local tek_src
    tek_src=$(read_state "PDBCLONE_TEK_ENC")
    local mkid_src
    mkid_src=$(read_state "PDBCLONE_MKID_ENC")

    write_state "PDB_P4_TEK"         "${tek_p4}"
    write_state "PDB_P4_MKID"        "${mkid_p4}"
    write_state "PDB_P4_KEY_VERSION" "${kv_p4}"
    write_state "PDB_P4_ORIGIN"      "${origin_p4}"
    write_state "PDB_TARGET_READY"   "TRUE"
    write_state "PDB_TARGET_NAME"    "${CLONE_P4_PDB}"
    write_state "PDB_TARGET_SERVICE" "${DEV_SERVICE}"

    local verdict msg
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        verdict="PASS"; msg="DRY-RUN"
    elif [[ "${tek_p4}" == "${tek_src}" ]]; then
        verdict="PASS"
        msg="P4: TEK preserved through remote clone + key import, ORIGIN=${origin_p4}"
    else
        verdict="FAIL"
        msg="P4: TEK DIFFERS from source - unexpected for remote clone + key import"
    fi

    print_key_summary "pdb_p4_remote (${CLONE_P4_PDB})" "${mkid_p4}" "${tek_p4}" \
        "ORIGIN=${origin_p4} KEY_VERSION=${kv_p4}"
    print_key_summary "pdb_baseline  (${CLONE_SRC_PDB})" "${mkid_src}" "${tek_src}"
    echo ""
    echo "TEK comparison:  $( [[ "${tek_p4}" == "${tek_src}" ]] && echo "IDENTICAL (expected)" || echo "DIFFERENT")"
    echo "ORIGIN in clone: ${origin_p4} (expect: IMPORTED)"
    echo "KEY_VERSION:     ${kv_p4}"

    print_verdict "${verdict}" "${msg}"
    lib_info "Done."
}

main "$@"
# --- EOF ----------------------------------------------------------------------
