#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: 50_variant_d.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026-09-04
# Version....: 0.1.0
# Purpose....: Variant D: RESTORE ... FORCE AS DECRYPTED, then SET KEY (new
#              dev MEK), then ALTER TABLESPACE USERS ENCRYPTION OFFLINE ENCRYPT.
#              Tests whether the decrypt-rekey-encrypt cycle creates new TEK
#              material. Expected result: ciphertext is still IDENTICAL to prod.
#              Oracle rewraps the existing TEK under the new MEK; the TEK itself
#              survives in the datafile header across the OFFLINE DECRYPT/ENCRYPT
#              cycle. Only ONLINE REKEY (variant G) or a new tablespace replaces
#              the TEK.
# Notes......: Prerequisites: step 15 (backup) must have completed.
#              FORCE is mandatory for RESTORE AS DECRYPTED: without it, the
#              restore optimisation skips datafiles already on disk and the run
#              looks successful but the blocks are never decrypted.
#              After OFFLINE DECRYPT, V$ENCRYPTED_TABLESPACES must show 0 rows
#              for USERS before proceeding - otherwise the tablespace is not
#              truly decrypted and the SET KEY step cannot complete cleanly.
#              The database cannot open without the prod MEK after AS DECRYPTED
#              because the CDB Database Key still references it. SET KEY rotates
#              it to a dev-own key.
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

LABEL="variant_d"
CLONE_EXTRA_ARGS=()

# ------------------------------------------------------------------------------
# usage
# ------------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

  Variant D: RESTORE FORCE AS DECRYPTED + SET KEY + OFFLINE ENCRYPT.

  Resets odbencdev, restores the prod backup fully decrypted (FORCE required),
  rotates the master key to a dev-own key, then re-encrypts USERS offline.
  Collects evidence set 'variant_d' and compares ciphertext with 'baseline'.

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
    step_header "Step 50: Variant D - RESTORE AS DECRYPTED + SET KEY + OFFLINE ENCRYPT"

    require_command docker
    require_container "${PROD_SERVICE}"
    require_state "SOURCE_DBID"  "source DBID (run step 10 first)"
    require_state "BACKUP_READY" "backup flag (run step 15 first)"

    local dbid
    dbid=$(read_state "SOURCE_DBID")
    # The named autobackup of the source. FROM AUTOBACKUP would take the newest
    # one, and after any earlier clone that is the target's own control file -
    # the target carries the source DBID after a restore, so its autobackups
    # land in the same cf_c-<dbid>-* namespace. Recovery then asks for sequence 1
    # of that new incarnation and fails with RMAN-06054.
    local cf_piece
    cf_piece=$(read_state "BACKUP_CF_PIECE")
    if [[ -z "${cf_piece}" ]]; then
        lib_err "BACKUP_CF_PIECE is unset - run step 15 first"
        return 1
    fi
    lib_info "control file autobackup: ${cf_piece}"

    # Reset odbencdev
    step_header "Reset odbencdev"
    reset_service "${DEV_SERVICE}"
    start_service "${DEV_SERVICE}"
    wait_for_ready "${DEV_SERVICE}" 600

    # Phase 1: RESTORE AS DECRYPTED (with FORCE) using transported prod wallet
    # tde_clone.sh --variant a is used as the base; the AS DECRYPTED path
    # diverges after the restore by specifying the decrypted clause.
    step_header "RESTORE FORCE AS DECRYPTED (variant a base + decrypted clause)"
    lib_info "DBID: ${dbid}"

    # tde_clone.sh does not have a 'd' variant; variant a with transported wallet
    # restores the control file, then we run RESTORE AS DECRYPTED separately.
    # Here we run variant a but intercept after the control file restore to
    # use the AS DECRYPTED clause. Since tde_clone.sh runs the full restore,
    # we need the AS DECRYPTED to be part of the RMAN run - pass it to a custom
    # rman_dev call after variant a has set up the keystore.

    # Step a: set up wallet (use tde_clone.sh for wallet transport only, then stop)
    # We call a reduced sequence manually:
    # 1. Shutdown NOMOUNT
    # 2. Quarantine redo logs
    # 3. Restore controlfile from autobackup
    # 4. Mount
    # 5. Open keystore (prod wallet transported)
    # 6. Catalog backup
    # 7. RESTORE DATABASE FORCE AS DECRYPTED
    # 8. RECOVER DATABASE
    # 9. OPEN RESETLOGS

    # Transport prod wallet to dev
    lib_run in_dev "
mkdir -p ${WALLET_DIR_CONTAINER}/tde
if [ -f ${XCHANGE_CONTAINER}/wallet_prod/tde/ewallet.p12 ]; then
    cp ${XCHANGE_CONTAINER}/wallet_prod/tde/ewallet.p12 ${WALLET_DIR_CONTAINER}/tde/
fi
if [ -f ${XCHANGE_CONTAINER}/wallet_prod/wallet_pwd.txt ]; then
    cp ${XCHANGE_CONTAINER}/wallet_prod/wallet_pwd.txt ${WALLET_DIR_CONTAINER}/
fi
"

    # Shutdown and go NOMOUNT
    sqlplus_dev "
WHENEVER SQLERROR CONTINUE
SHUTDOWN IMMEDIATE;
STARTUP NOMOUNT;
EXIT
"

    # Quarantine stale redo logs
    lib_run in_dev "
mkdir -p ${XCHANGE_CONTAINER}/stale_redo_${DEV_SERVICE}
for f in /opt/oracle/oradata/FREE/redo*.log; do
    [ -e \"\$f\" ] && mv \"\$f\" ${XCHANGE_CONTAINER}/stale_redo_${DEV_SERVICE}/ && echo \"moved \$f\"
done; true
"

    # Restore controlfile and mount
    rman_dev "
SET DBID ${dbid};
RUN {
  ALLOCATE CHANNEL c1 DEVICE TYPE DISK;
  SET CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '${XCHANGE_CONTAINER}/backup/cf_%F';
  RESTORE CONTROLFILE FROM '${XCHANGE_CONTAINER}/backup/${cf_piece}';
  ALTER DATABASE MOUNT;
  RELEASE CHANNEL c1;
}
# CONFIGURE is a standalone command and is not allowed inside RUN.
# The restored control file carries the SOURCE autobackup path, so every
# autobackup this target triggers would land next to the source pieces under the
# same DBID. Redirect right after the mount, before recovery writes one.
CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '/opt/oracle/oradata/cf_target_%F';
SHOW CONTROLFILE AUTOBACKUP FORMAT;
EXIT
"

    # Open the prod keystore
    lib_run in_dev '
KSPWD=$(cat '"${WALLET_DIR_CONTAINER}"'/wallet_pwd.txt)
sqlplus -S / as sysdba <<SQL 2>&1 | grep -viE "identified by"
WHENEVER SQLERROR CONTINUE
ADMINISTER KEY MANAGEMENT SET KEYSTORE OPEN FORCE KEYSTORE IDENTIFIED BY "${KSPWD}" CONTAINER=ALL;
SELECT con_id, status, wallet_type FROM v\$encryption_wallet ORDER BY con_id;
EXIT
SQL
'

    # Catalog and restore AS DECRYPTED FORCE
    local until_seq until_plus1
    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        until_seq=$(printf '%s\n' "
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 80 TRIMSPOOL ON
SELECT NVL(MAX(sequence#), 0) FROM v\$archived_log WHERE thread# = 1;
EXIT" | docker exec -i "${DEV_SERVICE}" sqlplus -S / as sysdba 2>/dev/null \
            | awk 'NF && $1 ~ /^[0-9]+$/ { print $1; exit }')
        if [[ -z "${until_seq}" ]]; then
            # An empty value here silently becomes 1, and SET UNTIL SEQUENCE 1
            # makes RMAN look for backups older than the first log - it then
            # reports RMAN-06023 "no backup found" for every datafile, which
            # looks like a missing backup rather than a parsing bug.
            lib_err "could not determine the last archived sequence in ${DEV_SERVICE}"
            lib_err "SET UNTIL SEQUENCE would fall back to 1 and no backup would be found"
            return 1
        fi
        until_plus1=$(( until_seq + 1 ))
    else
        until_plus1=0
    fi

    rman_dev "
RUN {
  ALLOCATE CHANNEL c1 DEVICE TYPE DISK;
  # No CATALOG here on purpose. Both containers mount the exchange directory at
  # the same path, so the restored control file already knows every source
  # piece. Cataloging the directory would also register any control file
  # autobackup a previous clone left there, and with it that clone incarnation.
  # Recovery then fails with ORA-19912, cannot recover to target incarnation.
  SET UNTIL SEQUENCE ${until_plus1} THREAD 1;
  RESTORE DATABASE FORCE AS DECRYPTED;
  RECOVER DATABASE;
  RELEASE CHANNEL c1;
}
EXIT
"

    sqlplus_dev "
WHENEVER SQLERROR CONTINUE
ALTER DATABASE OPEN RESETLOGS;
SELECT dbid, name, open_mode, log_mode FROM v\$database;
EXIT
"

    # Phase 2: Verify USERS is decrypted
    step_header "Verify USERS is fully decrypted"
    sqlplus_dev "
SET LINESIZE 120 PAGESIZE 100
ALTER SESSION SET CONTAINER=${PROD_PDB};
SELECT tablespace_name, encrypted FROM dba_tablespaces WHERE tablespace_name='USERS';
SELECT COUNT(*) AS enc_ts_count FROM v\$encrypted_tablespaces WHERE ts# = (SELECT ts# FROM v\$tablespace WHERE name='USERS' AND con_id=sys_context('userenv','con_id'));
EXIT
"

    # The restore ended in OPEN RESETLOGS, which restarts the instance and
    # closes a password-opened keystore. Without this the SET KEY below and the
    # offline encryption fail with ORA-28365.
    step_header "Reopen the keystore after RESETLOGS"
    ensure_autologin_for "${DEV_SERVICE}"

    # Phase 3: SET KEY to a dev-own MEK
    # Per container, not CONTAINER=ALL: PDB$SEED has no master key, so
    # CONTAINER=ALL fails with ORA-46663 "master encryption keys not created for
    # all PDBs for REKEY" and leaves the rotation half done.
    step_header "SET KEY to dev-own MEK (CDB\$ROOT and ${PROD_PDB} separately)"
    lib_run in_dev '
KSPWD=$(cat '"${WALLET_DIR_CONTAINER}"'/wallet_pwd.txt)
sqlplus -S / as sysdba <<SQL 2>&1 | grep -viE "identified by"
WHENEVER SQLERROR CONTINUE
SET LINESIZE 200 PAGESIZE 100 FEEDBACK OFF
ADMINISTER KEY MANAGEMENT SET KEY FORCE KEYSTORE IDENTIFIED BY "${KSPWD}" WITH BACKUP;
ALTER SESSION SET CONTAINER='"${PROD_PDB}"';
ADMINISTER KEY MANAGEMENT SET KEY FORCE KEYSTORE IDENTIFIED BY "${KSPWD}" WITH BACKUP;
ALTER SESSION SET CONTAINER=CDB\$ROOT;
COLUMN key_id FORMAT A54
SELECT key_id, origin, con_id FROM v\$encryption_keys ORDER BY con_id;
EXIT
SQL
'

    # Phase 4: Re-encrypt USERS offline
    step_header "ALTER TABLESPACE USERS ENCRYPTION OFFLINE ENCRYPT"
    sqlplus_dev "
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SESSION SET CONTAINER=${PROD_PDB};
-- READ WRITE first, it came back READ ONLY from the restore, and then OFFLINE:
-- offline encryption needs the tablespace offline, otherwise it fails with
-- ORA-28440, cannot offline encrypt or decrypt data file, file is in use.
ALTER TABLESPACE USERS READ WRITE;
ALTER TABLESPACE USERS OFFLINE NORMAL;
ALTER TABLESPACE USERS ENCRYPTION OFFLINE ENCRYPT;
ALTER TABLESPACE USERS ONLINE;
ALTER SYSTEM CHECKPOINT;
SELECT tablespace_name, status, encrypted FROM dba_tablespaces WHERE tablespace_name='USERS';
EXIT
"

    # Collect evidence
    step_header "Collect evidence set '${LABEL}'"
    collect_evidence "${DEV_SERVICE}" "${PROD_PDB}" "${LABEL}" "USERS"

    # Compare with baseline
    step_header "Compare '${LABEL}' vs 'baseline'"
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

    # The verdict rests on the canary data blocks, not on the stored key.
    # Variant D rotates the master key on purpose, so the wrapped TEK in
    # v$encrypted_tablespaces has to change - it is the same tablespace key
    # in a new wrapper. That column therefore cannot tell a re-wrap apart
    # from new key material; only the ciphertext of the data can.
    local canary_cmp canary_rc
    canary_cmp=""
    canary_rc=0
    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        canary_cmp=$(compare_canary_blocks "baseline" "${LABEL}" \
                       "${DEV_SERVICE}" "${PROD_PDB}" "CANARY_TDE") || canary_rc=$?
        echo "canary blocks:   ${canary_cmp}"
    fi

    local verdict msg
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        verdict="PASS"
        msg="DRY-RUN"
    elif [[ ${canary_rc} -eq 2 ]]; then
        verdict="FAIL"
        msg="could not compare the canary blocks - no verdict possible"
    elif [[ ${canary_rc} -eq 0 ]]; then
        verdict="PASS"
        msg="canary ciphertext IDENTICAL (${canary_cmp}) - the OFFLINE DECRYPT/ENCRYPT cycle reproduces the source ciphertext, so the tablespace key material is unchanged; the differing wrapped TEK is the re-wrap under the new dev MEK"
    else
        verdict="FAIL"
        msg="canary ciphertext CHANGED (${canary_cmp}) - unexpected for variant D, the offline cycle should reproduce the source blocks"
    fi

    write_state "VARIANT_D_MKID" "${mkid_clone}"
    write_state "VARIANT_D_TEK"  "${tek_clone}"

    print_key_summary "variant_d (clone)" "${mkid_clone}" "${tek_clone}"
    print_key_summary "baseline  (source)" "${mkid_source}" "${tek_source}"

    echo ""
    echo "Wrapped TEK:     $( [[ "${tek_clone}" == "${tek_source}" ]] && echo "IDENTICAL" || echo "DIFFERENT (expected - re-wrapped under the new dev MEK)")"
    echo "MASTERKEYID:     $( [[ "${mkid_clone}" == "${mkid_source}" ]] && echo "IDENTICAL" || echo "DIFFERENT (expected - a new dev MEK was set)")"
    echo "Note:            the wrapped TEK is not evidence either way - it"
    echo "                 changes on a pure re-wrap as well. The verdict is"
    echo "                 taken from the canary ciphertext above."

    print_verdict "${verdict}" "${msg}"
    lib_info "Done."
}

main "$@"
# --- EOF ----------------------------------------------------------------------
