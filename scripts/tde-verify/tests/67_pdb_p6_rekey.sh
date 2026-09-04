#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: 67_pdb_p6_rekey.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026-09-04
# Version....: 0.1.0
# Purpose....: PDB P6 - ONLINE REKEY of CLONE_ENC in the target PDB after
#              P2 (archive) or P4 (remote clone). ONLINE REKEY creates a new
#              Tablespace Encryption Key and rewrites all data blocks.
#              Expected: KEY_VERSION increases, ciphertext DIFFERS from
#              pdb_baseline (new TEK = genuine re-encryption).
#              Note: ONLINE REKEY creates a new datafile. tde_evidence.sh
#              --compare matches by filename, so the comparison may report
#              no common files. This is a known limitation; the KEY_VERSION
#              delta and block fingerprint of the new file are the evidence.
# Notes......: Prerequisite: step 63 (P2) or step 65 (P4).
#              If step 66 (P5) ran first, this operates on the MEK-rotated state.
#              CLONE_ENC is set READ WRITE before REKEY (was READ ONLY in source).
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
LABEL="pdb_p6_rekey"

# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

# ------------------------------------------------------------------------------
# usage
# ------------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

  PDB P6: ONLINE REKEY of CLONE_ENC in the target PDB.
  ONLINE REKEY creates a new TEK and rewrites all data blocks in a new datafile.
  Expected: KEY_VERSION increases, ciphertext DIFFERS from pdb_baseline.

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
    step_header "Step 67: PDB P6 - ONLINE REKEY in target PDB"

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

    # Record key state BEFORE rekey
    step_header "Key state BEFORE ONLINE REKEY"
    local mkid_before tek_before kv_before
    mkid_before=""; tek_before=""; kv_before=""
    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        mkid_before=$(get_masterkeyid "${DEV_SERVICE}" "${target_pdb}" "${CLONE_TS_ENC}")
        tek_before=$(get_encryptedkey  "${DEV_SERVICE}" "${target_pdb}" "${CLONE_TS_ENC}")
        kv_before=$(printf '%s\n' "
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 80 TRIMSPOOL ON
ALTER SESSION SET CONTAINER=${target_pdb};
SELECT key_version FROM v\$encrypted_tablespaces WHERE ts# = (SELECT ts# FROM v\$tablespace WHERE name='${CLONE_TS_ENC}' AND con_id=sys_context('userenv','con_id'));
EXIT" | docker exec -i "${DEV_SERVICE}" sqlplus -S / as sysdba 2>/dev/null \
            | awk 'NF && $1 ~ /^[0-9]+$/ { print $1; exit }')
    else
        mkid_before="DRY-RUN-MKID-BEFORE"
        tek_before="DRY-RUN-TEK-BEFORE"
        kv_before="1"
    fi
    lib_info "KEY_VERSION before: ${kv_before}"

    # Set CLONE_ENC READ WRITE (ONLINE REKEY requires writable tablespace)
    step_header "Set ${CLONE_TS_ENC} READ WRITE in ${target_pdb}"
    sqlplus_dev "
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SESSION SET CONTAINER=${target_pdb};
ALTER TABLESPACE ${CLONE_TS_ENC} READ WRITE;
SELECT tablespace_name, status FROM dba_tablespaces
  WHERE tablespace_name='${CLONE_TS_ENC}';
EXIT
"

    # ONLINE REKEY
    step_header "ALTER TABLESPACE ${CLONE_TS_ENC} ENCRYPTION ONLINE REKEY"
    sqlplus_dev "
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SESSION SET CONTAINER=${target_pdb};
ALTER TABLESPACE ${CLONE_TS_ENC} ENCRYPTION ONLINE REKEY;
SELECT 'ONLINE REKEY done' AS status FROM dual;
EXIT
"

    # Record key state AFTER rekey
    step_header "Key state AFTER ONLINE REKEY"
    local mkid_after tek_after kv_after
    mkid_after=""; tek_after=""; kv_after=""
    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        mkid_after=$(get_masterkeyid "${DEV_SERVICE}" "${target_pdb}" "${CLONE_TS_ENC}")
        tek_after=$(get_encryptedkey  "${DEV_SERVICE}" "${target_pdb}" "${CLONE_TS_ENC}")
        kv_after=$(printf '%s\n' "
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 80 TRIMSPOOL ON
ALTER SESSION SET CONTAINER=${target_pdb};
SELECT key_version FROM v\$encrypted_tablespaces WHERE ts# = (SELECT ts# FROM v\$tablespace WHERE name='${CLONE_TS_ENC}' AND con_id=sys_context('userenv','con_id'));
EXIT" | docker exec -i "${DEV_SERVICE}" sqlplus -S / as sysdba 2>/dev/null \
            | awk 'NF && $1 ~ /^[0-9]+$/ { print $1; exit }')
    else
        mkid_after="DRY-RUN-MKID-AFTER"
        tek_after="DRY-RUN-TEK-AFTER"
        kv_after="2"
    fi
    lib_info "KEY_VERSION after: ${kv_after}"

    sqlplus_dev "
SET HEADING ON FEEDBACK ON PAGESIZE 100 LINESIZE 200
ALTER SESSION SET CONTAINER=${target_pdb};
SELECT RAWTOHEX(masterkeyid) AS masterkeyid_after,
       RAWTOHEX(encryptedkey) AS encryptedkey_after,
       key_version, encryptionalg
FROM v\$encrypted_tablespaces WHERE ts# = (SELECT ts# FROM v\$tablespace WHERE name='${CLONE_TS_ENC}' AND con_id=sys_context('userenv','con_id'));
EXIT
"

    # Collect evidence AFTER rekey
    step_header "Collect evidence set '${LABEL}'"
    collect_evidence "${DEV_SERVICE}" "${target_pdb}" "${LABEL}" "${CLONE_TS_ENC}"

    # Compare against pdb_baseline - expect DIFFERENT (new datafile, new TEK)
    step_header "Compare '${LABEL}' vs 'pdb_baseline' (expect RE-ENCRYPT: blocks differ)"
    lib_info "Note: ONLINE REKEY creates a new datafile; --compare may report no common files."
    lib_info "KEY_VERSION delta and block fingerprint of the new file are the primary evidence."
    compare_evidence "pdb_baseline" "${LABEL}" || lib_warn "compare returned non-zero (may be expected: new datafile)"

    write_state "PDB_P6_TEK_BEFORE"  "${tek_before}"
    write_state "PDB_P6_TEK_AFTER"   "${tek_after}"
    write_state "PDB_P6_MKID_AFTER"  "${mkid_after}"

    local kv_before_int kv_after_int
    # Falling back to 0 keeps the comparison from crashing, but a missing value
    # means the measurement failed - say so instead of folding it into the result.
    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        [[ -n "${kv_before}" ]] || lib_warn "KEY_VERSION before REKEY not measured, treating as 0"
        [[ -n "${kv_after}"  ]] || lib_warn "KEY_VERSION after REKEY not measured, treating as 0"
    fi
    kv_before_int="${kv_before:-0}"
    kv_after_int="${kv_after:-0}"

    local verdict msg
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        verdict="PASS"; msg="DRY-RUN"
    elif [[ "${tek_after}" != "${tek_before}" ]]; then
        verdict="PASS"
        msg="P6: ONLINE REKEY created new TEK (KEY_VERSION ${kv_before_int} -> ${kv_after_int})"
    elif (( kv_after_int > kv_before_int )); then
        verdict="PASS"
        msg="P6: KEY_VERSION increased (${kv_before_int} -> ${kv_after_int}); TEK value may appear same due to ENCRYPTEDKEY format"
    else
        verdict="FAIL"
        msg="P6: KEY_VERSION did not increase - ONLINE REKEY may not have executed"
    fi

    print_key_summary "before ONLINE REKEY" "${mkid_before}" "${tek_before}" "KEY_VERSION=${kv_before}"
    print_key_summary "after  ONLINE REKEY" "${mkid_after}"  "${tek_after}"  "KEY_VERSION=${kv_after}"
    echo ""
    echo "TEK changed:       $( [[ "${tek_after}" != "${tek_before}" ]] && echo "YES (new TEK)" || echo "NO")"
    echo "KEY_VERSION delta: ${kv_before_int} -> ${kv_after_int}"

    print_verdict "${verdict}" "${msg}"
    lib_info "Done."
}

main "$@"
# --- EOF ----------------------------------------------------------------------
