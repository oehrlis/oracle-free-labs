#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: 60_variant_f.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026-09-04
# Version....: 0.1.0
# Purpose....: Variant F: the only measured path that breaks the key chain and
#              creates genuinely new TEK material.
#              Steps:
#              1. Variant A base: RESTORE with transported prod keystore
#              2. OFFLINE DECRYPT USERS (verify V$ENCRYPTED_TABLESPACES = 0 rows)
#              3. Remove the prod keystore, create a fresh dev keystore
#              4. In the PDB: SET "_db_discard_lost_masterkey"=TRUE SCOPE=MEMORY
#              5. In the PDB: ADMINISTER KEY MANAGEMENT SET KEY FORCE KEYSTORE
#              6. OFFLINE ENCRYPT USERS (new TEK generated)
#              Expected result: ciphertext DIFFERS from prod - new TEK material.
# Notes......: Prerequisites: step 15 (backup) must have completed.
#              _db_discard_lost_masterkey MUST be set in the PDB (ISPDB_MODIFIABLE
#              TRUE). At CDB level SCOPE=MEMORY fails with ORA-28355; SCOPE=SPFILE
#              + restart silently does not apply it. Only in-PDB SCOPE=MEMORY works.
#              After step 3 the prod MEKs are gone; the database cannot open
#              USERS without step 4+5. Do not attempt to open the PDB between
#              step 3 and step 5.
#              The warning in the Alert Log after step 5 is expected and is part
#              of the evidence: "replacing lost SYSAUX key with new database key
#              due to prior wallet deletion". SYSAUX blocks may appear corrupted
#              if this path is used on production data.
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

# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

LABEL="variant_f"
CLONE_EXTRA_ARGS=()

# ------------------------------------------------------------------------------
# usage
# ------------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

  Variant F: RESTORE (A) + OFFLINE DECRYPT + fresh keystore +
             _db_discard_lost_masterkey + SET KEY + OFFLINE ENCRYPT.

  The only measured path that creates genuinely new TEK material. Ciphertext
  after step 6 will DIFFER from the prod baseline.

  Prerequisite: step 15 (backup) must have completed.

Options:
  -h, --help      Show this help and exit
  -v, --verbose   Enable verbose output
  -d, --dry-run   Show what would be done; change nothing
  -y, --yes       Skip the dev reset confirmation prompt

Examples:
  ${SCRIPT_NAME} --dry-run
  ${SCRIPT_NAME} --yes

EOF
}

# ------------------------------------------------------------------------------
# Parse arguments
# ------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)    usage; exit 0 ;;
        -v|--verbose) VERBOSE="TRUE"; CLONE_EXTRA_ARGS+=("--verbose"); shift ;;
        -d|--dry-run) DRY_RUN="TRUE";  CLONE_EXTRA_ARGS+=("--dry-run");  shift ;;
        -y|--yes)     FORCE_YES="TRUE"; CLONE_EXTRA_ARGS+=("--yes");      shift ;;
        *) lib_err "Unknown option: $1"; usage; exit 1 ;;
    esac
done

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
main() {
    lib_info "Starting ${SCRIPT_NAME} ${VERSION}"
    step_header "Step 60: Variant F - chain-breaking path (new TEK)"

    require_command docker
    require_container "${PROD_SERVICE}"
    require_state "SOURCE_DBID"  "source DBID (run step 10 first)"
    require_state "BACKUP_READY" "backup flag (run step 15 first)"

    local dbid
    dbid=$(read_state "SOURCE_DBID")
    # Named source autobackup; without it the clone picks the newest one, which
    # after any earlier clone is the target's own control file.
    local cf_piece
    cf_piece=$(read_state "BACKUP_CF_PIECE")
    if [[ -z "${cf_piece}" ]]; then
        lib_err "BACKUP_CF_PIECE is unset - run step 15 first"
        return 1
    fi

    # Reset odbencdev
    step_header "Reset odbencdev"
    reset_service "${DEV_SERVICE}"
    start_service "${DEV_SERVICE}"
    wait_for_ready "${DEV_SERVICE}" 600

    # Phase 1: variant A base (RESTORE with transported prod keystore)
    step_header "Phase 1: Variant A base (RESTORE with prod keystore)"
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        lib_info "DRY-RUN: would run: ${CLONE_SCRIPT} --variant a --dbid ${dbid} --cf-piece ${cf_piece} --delete"
    else
        "${CLONE_SCRIPT}" \
            --variant a \
            --dbid     "${dbid}" \
            --cf-piece "${cf_piece}" \
            --delete \
            "${CLONE_EXTRA_ARGS[@]}"
    fi

    # Phase 2: OFFLINE DECRYPT USERS
    step_header "Phase 2: OFFLINE DECRYPT USERS"
    sqlplus_dev "
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SESSION SET CONTAINER=${PROD_PDB};
-- READ WRITE and then OFFLINE: offline conversion needs the tablespace offline,
-- otherwise it fails with ORA-28440 "file is in use".
ALTER TABLESPACE USERS READ WRITE;
ALTER TABLESPACE USERS OFFLINE NORMAL;
ALTER TABLESPACE USERS ENCRYPTION OFFLINE DECRYPT;
ALTER TABLESPACE USERS ONLINE;
ALTER SYSTEM CHECKPOINT;
-- Verify: must be 0 rows
SELECT COUNT(*) AS enc_ts_remaining FROM v\$encrypted_tablespaces;
EXIT
"

    # Gate: verify no encrypted tablespaces remain in the PDB
    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        local enc_count
        enc_count=$(printf '%s\n' "
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 80 TRIMSPOOL ON
ALTER SESSION SET CONTAINER=${PROD_PDB};
SELECT COUNT(*) FROM v\$encrypted_tablespaces;
EXIT" | docker exec -i "${DEV_SERVICE}" sqlplus -S / as sysdba 2>/dev/null \
            | awk 'NF && $1 ~ /^[0-9]+$/ { print $1; exit }')
        if [[ "${enc_count:-1}" -ne 0 ]]; then
            lib_err "Gate: V\$ENCRYPTED_TABLESPACES still has ${enc_count} row(s) after OFFLINE DECRYPT"
            lib_err "All tablespaces must be decrypted before discarding the master key handles"
            exit 1
        fi
        lib_info "Gate OK: V\$ENCRYPTED_TABLESPACES = 0 rows, all tablespaces decrypted"
    fi

    # Phase 3: Remove prod keystore, create a fresh dev keystore
    step_header "Phase 3: Remove prod keystore, create fresh dev keystore"
    lib_run in_dev "
ks_dir=${WALLET_DIR_CONTAINER}/tde
# Preserve the dev-pristine backup if it exists; move prod wallet aside
if [ -d \${ks_dir} ]; then
    mv \${ks_dir} ${XCHANGE_CONTAINER}/wallet_prod_used_f
    echo 'prod keystore moved to ${XCHANGE_CONTAINER}/wallet_prod_used_f'
fi
mkdir -p \${ks_dir}
echo 'fresh keystore directory created: '\${ks_dir}
"

    # shellcheck disable=SC1078
    lib_run in_dev '
KSPWD=$(cat '"${WALLET_DIR_CONTAINER}"'/wallet_pwd.txt)
sqlplus -S / as sysdba <<SQL 2>&1 | grep -viE "identified by"
WHENEVER SQLERROR EXIT SQL.SQLCODE
ADMINISTER KEY MANAGEMENT CREATE KEYSTORE '"'"'${WALLET_DIR_CONTAINER}/tde'"'"' IDENTIFIED BY "${KSPWD}";
ADMINISTER KEY MANAGEMENT SET KEYSTORE OPEN IDENTIFIED BY "${KSPWD}" CONTAINER=ALL;
-- Set CDB master key first (PDB key will follow after discard step)
ADMINISTER KEY MANAGEMENT SET KEY IDENTIFIED BY "${KSPWD}" WITH BACKUP CONTAINER=ALL;
SELECT con_id, key_id, keystore_type, origin FROM v\$encryption_keys ORDER BY con_id;
EXIT
SQL
'

    # Phase 4+5: In PDB - discard lost master key handles, then SET KEY
    step_header "Phase 4+5: In PDB - _db_discard_lost_masterkey + SET KEY"
    # shellcheck disable=SC1078
    lib_run in_dev '
KSPWD=$(cat '"${WALLET_DIR_CONTAINER}"'/wallet_pwd.txt)
sqlplus -S / as sysdba <<SQL 2>&1 | grep -viE "identified by"
WHENEVER SQLERROR CONTINUE
ALTER SESSION SET CONTAINER='"${PROD_PDB}"';
-- _db_discard_lost_masterkey MUST be set in the PDB with SCOPE=MEMORY
-- At CDB level: ORA-28355. SCOPE=SPFILE + restart does not apply it.
ALTER SYSTEM SET "_db_discard_lost_masterkey"=TRUE SCOPE=MEMORY;
-- Now SET KEY succeeds despite the prod MEK being gone
ADMINISTER KEY MANAGEMENT SET KEY FORCE KEYSTORE IDENTIFIED BY "${KSPWD}" WITH BACKUP;
SELECT con_id, key_id, keystore_type, origin FROM v\$encryption_keys ORDER BY con_id;
SELECT COUNT(*) AS prod_keys_remaining
  FROM v\$encryption_keys WHERE origin != '"'"'LOCAL'"'"';
EXIT
SQL
'

    # Phase 6: OFFLINE ENCRYPT USERS (new TEK generated)
    step_header "Phase 6: OFFLINE ENCRYPT USERS"
    sqlplus_dev "
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SESSION SET CONTAINER=${PROD_PDB};
ALTER TABLESPACE USERS OFFLINE NORMAL;
ALTER TABLESPACE USERS ENCRYPTION OFFLINE ENCRYPT;
ALTER TABLESPACE USERS ONLINE;
ALTER SYSTEM CHECKPOINT;
SELECT tablespace_name, status, encrypted FROM dba_tablespaces WHERE tablespace_name='USERS';
SELECT RAWTOHEX(masterkeyid), RAWTOHEX(encryptedkey), key_version
  FROM v\$encrypted_tablespaces WHERE ts# = (SELECT ts# FROM v\$tablespace WHERE name='USERS' AND con_id=sys_context('userenv','con_id'));
EXIT
"

    # Collect evidence
    step_header "Collect evidence set '${LABEL}'"
    collect_evidence "${DEV_SERVICE}" "${PROD_PDB}" "${LABEL}" "USERS"

    # Compare with baseline - ciphertext MUST differ here
    step_header "Compare '${LABEL}' vs 'baseline' (expect DIFFERENT)"
    compare_evidence "baseline" "${LABEL}"

    # Read key values
    local mkid_clone tek_clone
    mkid_clone=""
    tek_clone=""
    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        mkid_clone=$(get_masterkeyid "${DEV_SERVICE}" "${PROD_PDB}" "USERS")
        tek_clone=$(get_encryptedkey  "${DEV_SERVICE}" "${PROD_PDB}" "USERS")
    fi

    local mkid_source tek_source
    mkid_source=$(read_state "SOURCE_MASTERKEYID")
    tek_source=$(read_state  "SOURCE_TEK")

    local verdict msg
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        verdict="PASS"
        msg="DRY-RUN"
    elif [[ "${tek_clone}" != "${tek_source}" ]]; then
        verdict="PASS"
        msg="TEK DIFFERS from baseline - new TEK created, key chain broken"
    else
        verdict="FAIL"
        msg="TEK is still identical to baseline - chain not broken (investigate)"
    fi

    write_state "VARIANT_F_MKID" "${mkid_clone}"
    write_state "VARIANT_F_TEK"  "${tek_clone}"

    print_key_summary "variant_f (clone)" "${mkid_clone}" "${tek_clone}"
    print_key_summary "baseline  (source)" "${mkid_source}" "${tek_source}"

    echo ""
    echo "TEK comparison: $( [[ "${tek_clone}" == "${tek_source}" ]] && echo "IDENTICAL" || echo "DIFFERENT (expected)")"

    print_verdict "${verdict}" "${msg}"
    lib_info "Done."
}

main "$@"
# --- EOF ----------------------------------------------------------------------
