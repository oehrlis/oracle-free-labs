#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: 66_pdb_p5_mekrot.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026-09-04
# Version....: 0.1.0
# Purpose....: PDB P5 - MEK rotation in the target PDB after P2 (archive) or
#              P4 (remote clone). Verifies that rotating the MEK in dev only
#              re-wraps the tablespace key (ENCRYPTEDKEY changes, TEK blocks
#              unchanged) - the same behaviour observed for CDB-level RMAN
#              variants.
#              Expected: MASTERKEYID changes, ciphertext blocks unchanged
#              (same verdict as RMAN Variant A/C: RE-WRAP INDICATED).
# Notes......: Prerequisite: step 63 (P2) or step 65 (P4) must have completed.
#              Target PDB name is read from state (PDB_TARGET_NAME).
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
CLONE_TS_ENC="CLONE_ENC"
LABEL="pdb_p5_mekrot"

# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

# ------------------------------------------------------------------------------
# usage
# ------------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

  PDB P5: MEK rotation in the target PDB (from state: PDB_TARGET_NAME).
  Verifies that MEK rotation only re-wraps the tablespace key (same ciphertext,
  different MASTERKEYID and ENCRYPTEDKEY).
  Expected: RE-WRAP INDICATED (same behaviour as CDB-level RMAN variants).

  Prerequisite: step 63 (P2) or step 65 (P4) must have completed.

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
# Main
# ------------------------------------------------------------------------------
main() {
    lib_info "Starting ${SCRIPT_NAME} ${VERSION}"
    step_header "Step 66: PDB P5 - MEK rotation in target PDB"

    require_command docker
    require_container "${DEV_SERVICE}"
    require_healthy   "${DEV_SERVICE}"
    require_state "PDB_TARGET_READY" "target PDB in dev (run step 63 P2 or step 65 P4 first)"

    local target_pdb
    target_pdb=$(read_state "PDB_TARGET_NAME")
    if [[ -z "${target_pdb}" ]]; then
        target_pdb="PDBCLONE_P2"
        lib_warn "PDB_TARGET_NAME not in state, defaulting to ${target_pdb}"
    fi
    lib_info "Target PDB: ${target_pdb} in ${DEV_SERVICE}"

    # Record key state BEFORE rotation
    step_header "Key state BEFORE MEK rotation"
    local mkid_before tek_before
    mkid_before=""; tek_before=""
    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        mkid_before=$(get_masterkeyid "${DEV_SERVICE}" "${target_pdb}" "${CLONE_TS_ENC}")
        tek_before=$(get_encryptedkey  "${DEV_SERVICE}" "${target_pdb}" "${CLONE_TS_ENC}")
    else
        mkid_before="DRY-RUN-MKID-BEFORE"
        tek_before="DRY-RUN-TEK-BEFORE"
    fi
    sqlplus_dev "
SET HEADING ON FEEDBACK ON PAGESIZE 100 LINESIZE 200
ALTER SESSION SET CONTAINER=${target_pdb};
SELECT key_id, key_use, origin, keystore_type FROM v\$encryption_keys
WHERE con_id = sys_context('userenv','con_id')
ORDER BY creation_time;
SELECT RAWTOHEX(masterkeyid) AS masterkeyid_before,
       RAWTOHEX(encryptedkey) AS encryptedkey_before,
       key_version
FROM v\$encrypted_tablespaces WHERE name='${CLONE_TS_ENC}';
EXIT
"

    # MEK rotation in the target PDB
    step_header "MEK rotation in ${target_pdb}"
    # shellcheck disable=SC1078,SC1079
    lib_run in_dev '
KSPWD=$(cat '"${WALLET_DIR_CONTAINER}"'/wallet_pwd.txt)
sqlplus -S / as sysdba <<SQL 2>&1 | grep -viE "identified by|password"
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SESSION SET CONTAINER='"${target_pdb}"';
ADMINISTER KEY MANAGEMENT SET KEY IDENTIFIED BY "${KSPWD}"
  WITH BACKUP CONTAINER=CURRENT;
SELECT '"'"'MEK rotation done'"'"' AS status FROM dual;
EXIT
SQL
'

    # Record key state AFTER rotation
    step_header "Key state AFTER MEK rotation"
    local mkid_after tek_after
    mkid_after=""; tek_after=""
    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        mkid_after=$(get_masterkeyid "${DEV_SERVICE}" "${target_pdb}" "${CLONE_TS_ENC}")
        tek_after=$(get_encryptedkey  "${DEV_SERVICE}" "${target_pdb}" "${CLONE_TS_ENC}")
    else
        mkid_after="DRY-RUN-MKID-AFTER"
        tek_after="DRY-RUN-TEK-AFTER"
    fi
    sqlplus_dev "
SET HEADING ON FEEDBACK ON PAGESIZE 100 LINESIZE 200
ALTER SESSION SET CONTAINER=${target_pdb};
SELECT key_id, key_use, origin, keystore_type FROM v\$encryption_keys
WHERE con_id = sys_context('userenv','con_id')
ORDER BY creation_time;
SELECT RAWTOHEX(masterkeyid) AS masterkeyid_after,
       RAWTOHEX(encryptedkey) AS encryptedkey_after,
       key_version
FROM v\$encrypted_tablespaces WHERE name='${CLONE_TS_ENC}';
EXIT
"

    # Collect evidence AFTER rotation
    step_header "Collect evidence set '${LABEL}'"
    collect_evidence "${DEV_SERVICE}" "${target_pdb}" "${LABEL}" "${CLONE_TS_ENC}"

    # Compare against pdb_baseline - expect RE-WRAP (only header blocks differ)
    step_header "Compare '${LABEL}' vs 'pdb_baseline' (expect RE-WRAP: data blocks identical)"
    compare_evidence "pdb_baseline" "${LABEL}"

    write_state "PDB_P5_MKID_BEFORE" "${mkid_before}"
    write_state "PDB_P5_TEK_BEFORE"  "${tek_before}"
    write_state "PDB_P5_MKID_AFTER"  "${mkid_after}"
    write_state "PDB_P5_TEK_AFTER"   "${tek_after}"

    local verdict msg
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        verdict="PASS"; msg="DRY-RUN"
    elif [[ "${mkid_after}" != "${mkid_before}" ]]; then
        verdict="PASS"
        msg="P5: MEK rotation succeeded (MASTERKEYID changed); ciphertext comparison shows RE-WRAP"
    else
        verdict="FAIL"
        msg="P5: MASTERKEYID unchanged after SET KEY - rotation may have failed"
    fi

    print_key_summary "before rotation" "${mkid_before}" "${tek_before}"
    print_key_summary "after  rotation" "${mkid_after}"  "${tek_after}"
    echo ""
    echo "MASTERKEYID changed: $( [[ "${mkid_after}" != "${mkid_before}" ]] && echo "YES (expected)" || echo "NO")"
    echo "ENCRYPTEDKEY changed: $( [[ "${tek_after}" != "${tek_before}" ]] && echo "YES (rewrap)" || echo "NO")"

    print_verdict "${verdict}" "${msg}"
    lib_info "Done."
}

main "$@"
# --- EOF ----------------------------------------------------------------------
