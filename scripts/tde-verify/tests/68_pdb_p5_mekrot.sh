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
    local mkid_before tek_before mek_before
    mkid_before=""; tek_before=""; mek_before="DRY-RUN-MEK-BEFORE"
    [[ "${DRY_RUN}" == "TRUE" ]] || mek_before=$(get_pdb_active_mek "${DEV_SERVICE}" "${target_pdb}")
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
FROM v\$encrypted_tablespaces WHERE ts# = (SELECT ts# FROM v\$tablespace WHERE name='${CLONE_TS_ENC}' AND con_id=sys_context('userenv','con_id'));
EXIT
"

    # Evidence of the target BEFORE the rotation. Comparing against prod's
    # baseline would be wrong here: the target is PDBCLONE_P2 or PDBCLONE_P4
    # depending on what ran, and the clone in P4 already differs from prod by
    # design. The question this step answers - did the rotation touch the data
    # - can only be asked against the target own prior state.
    step_header "Collect evidence set '${LABEL}_before' (target before rotation)"
    collect_evidence "${DEV_SERVICE}" "${target_pdb}" "${LABEL}_before" "${CLONE_TS_ENC}"

    # MEK rotation in the target PDB
    step_header "MEK rotation in ${target_pdb}"
    # shellcheck disable=SC1078,SC1079
    lib_run in_dev '
KSPWD=$(cat '"${WALLET_DIR_CONTAINER}"'/wallet_pwd.txt)
sqlplus -S / as sysdba <<SQL 2>&1 | grep -viE "identified by"; _rc=${PIPESTATUS[0]}; [ "${_rc}" -eq 0 ] || { echo "ERROR: sqlplus exited ${_rc}" >&2; exit "${_rc}"; }
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SESSION SET CONTAINER='"${target_pdb}"';
-- FORCE KEYSTORE is required: the dev keystore is open as LOCAL_AUTOLOGIN,
-- and a password operation against it fails with ORA-28417 otherwise. Step 61
-- needs it for the same reason.
ADMINISTER KEY MANAGEMENT SET KEY FORCE KEYSTORE IDENTIFIED BY "${KSPWD}"
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
FROM v\$encrypted_tablespaces WHERE ts# = (SELECT ts# FROM v\$tablespace WHERE name='${CLONE_TS_ENC}' AND con_id=sys_context('userenv','con_id'));
EXIT
"

    local mek_after_ro="DRY-RUN-MEK-A"
    [[ "${DRY_RUN}" == "TRUE" ]] || mek_after_ro=$(get_pdb_active_mek "${DEV_SERVICE}" "${target_pdb}")

    # Collect evidence AFTER the rotation on the READ ONLY tablespace
    step_header "Collect evidence set '${LABEL}' (after rotation, tablespace READ ONLY)"
    collect_evidence "${DEV_SERVICE}" "${target_pdb}" "${LABEL}" "${CLONE_TS_ENC}"

    step_header "Compare '${LABEL}' vs '${LABEL}_before'"
    compare_evidence "${LABEL}_before" "${LABEL}"

    # ---------------------------------------------------------------------
    # Phase B: the same rotation on a READ WRITE tablespace.
    # Phase A leaves the tablespace pointing at the OLD master key because it
    # is READ ONLY and cannot be re-wrapped. That is the operationally
    # important half of the answer, but on its own it would look like a failed
    # rotation. Measuring both makes the difference explicit.
    # ---------------------------------------------------------------------
    step_header "Phase B: set ${CLONE_TS_ENC} READ WRITE and rotate again"
    sqlplus_dev "
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SESSION SET CONTAINER=${target_pdb};
ALTER TABLESPACE ${CLONE_TS_ENC} READ WRITE;
SELECT tablespace_name, status FROM dba_tablespaces WHERE tablespace_name='${CLONE_TS_ENC}';
EXIT
"
    # shellcheck disable=SC1078,SC1079
    lib_run in_dev '
KSPWD=$(cat '"${WALLET_DIR_CONTAINER}"'/wallet_pwd.txt)
sqlplus -S / as sysdba <<SQL 2>&1 | grep -viE "identified by"; _rc=${PIPESTATUS[0]}; [ "${_rc}" -eq 0 ] || { echo "ERROR: sqlplus exited ${_rc}" >&2; exit "${_rc}"; }
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SESSION SET CONTAINER='"${target_pdb}"';
ADMINISTER KEY MANAGEMENT SET KEY FORCE KEYSTORE IDENTIFIED BY "${KSPWD}"
  WITH BACKUP CONTAINER=CURRENT;
EXIT
SQL
'
    local mkid_rw tek_rw mek_after_rw
    mkid_rw="DRY-RUN"; tek_rw="DRY-RUN"; mek_after_rw="DRY-RUN"
    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        mkid_rw=$(get_masterkeyid "${DEV_SERVICE}" "${target_pdb}" "${CLONE_TS_ENC}")
        tek_rw=$(get_encryptedkey  "${DEV_SERVICE}" "${target_pdb}" "${CLONE_TS_ENC}")
        mek_after_rw=$(get_pdb_active_mek "${DEV_SERVICE}" "${target_pdb}")
    fi

    step_header "Collect evidence set '${LABEL}_rw' (after rotation, tablespace READ WRITE)"
    collect_evidence "${DEV_SERVICE}" "${target_pdb}" "${LABEL}_rw" "${CLONE_TS_ENC}"

    # Back to READ ONLY so the later steps keep a stable ciphertext reference
    sqlplus_dev "
WHENEVER SQLERROR CONTINUE
ALTER SESSION SET CONTAINER=${target_pdb};
ALTER TABLESPACE ${CLONE_TS_ENC} READ ONLY;
EXIT
"

    write_state "PDB_P5_MKID_BEFORE" "${mkid_before}"
    write_state "PDB_P5_TEK_BEFORE"  "${tek_before}"
    write_state "PDB_P5_MKID_AFTER"  "${mkid_after}"
    write_state "PDB_P5_TEK_AFTER"   "${tek_after}"

    # Two questions, two measurements. The customer form is "we only swap the
    # MEK", and it has to be answered on the ciphertext, not on a stored key.
    #   Phase A - tablespace READ ONLY: the PDB master key changes, but the
    #             tablespace entry keeps pointing at the OLD key. It cannot be
    #             re-wrapped while read only, so it stays bound to the source.
    #   Phase B - tablespace READ WRITE: the entry follows to the new master
    #             key, the wrapped key changes, and the data stays untouched.
    # In both phases the ciphertext must be byte-identical: a rotation
    # re-wraps, it never re-encrypts.
    local canary_a canary_a_rc canary_b canary_b_rc
    canary_a=""; canary_a_rc=0; canary_b=""; canary_b_rc=0
    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        canary_a=$(compare_canary_blocks "${LABEL}_before" "${LABEL}" \
                     "${DEV_SERVICE}" "${target_pdb}" "CANARY_CLONEENC") || canary_a_rc=$?
        echo "canary A (read only):  ${canary_a} (expect all identical)"
        canary_b=$(compare_canary_blocks "${LABEL}" "${LABEL}_rw" \
                     "${DEV_SERVICE}" "${target_pdb}" "CANARY_CLONEENC") || canary_b_rc=$?
        echo "canary B (read write): ${canary_b} (expect all identical)"
    fi

    write_state "PDB_P5_MEK_BEFORE"   "${mek_before}"
    write_state "PDB_P5_MEK_AFTER_RO" "${mek_after_ro}"
    write_state "PDB_P5_MEK_AFTER_RW" "${mek_after_rw}"
    write_state "PDB_P5_MKID_RW"      "${mkid_rw}"
    write_state "PDB_P5_TEK_RW"       "${tek_rw}"

    local verdict msg
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        verdict="PASS"; msg="DRY-RUN"
    elif [[ ${canary_a_rc} -eq 2 || ${canary_b_rc} -eq 2 ]]; then
        verdict="FAIL"
        msg="P5: canary blocks could not be compared - no verdict possible"
    elif [[ "${mek_after_ro}" == "${mek_before}" ]]; then
        verdict="FAIL"
        msg="P5: the PDB master key did not change (${mek_before}) - the rotation itself failed"
    elif [[ ${canary_a_rc} -ne 0 || ${canary_b_rc} -ne 0 ]]; then
        verdict="FAIL"
        msg="P5: the rotation changed the ciphertext (A: ${canary_a}, B: ${canary_b}) - a rotation re-wraps and must never rewrite data blocks"
    elif [[ "${mkid_after}" == "${mkid_before}" && "${mkid_rw}" == "${mek_after_rw}" && "${tek_rw}" != "${tek_after}" ]]; then
        verdict="PASS"
        msg="P5: rotating the PDB master key (${mek_before} -> ${mek_after_ro} -> ${mek_after_rw}) left the ciphertext byte-identical in both phases (A: ${canary_a}, B: ${canary_b}). While READ ONLY the tablespace could not be re-wrapped and kept pointing at the old key ${mkid_before}; only after READ WRITE did it follow to ${mkid_rw}. A read-only tablespace therefore stays bound to the source master key across a rotation"
    else
        verdict="FAIL"
        msg="P5: unexpected combination - ts key before ${mkid_before}, after read-only rotation ${mkid_after}, after read-write rotation ${mkid_rw}, active PDB key ${mek_after_rw}"
    fi

    print_key_summary "before rotation      " "${mkid_before}" "${tek_before}"
    print_key_summary "after rotation (RO)  " "${mkid_after}"  "${tek_after}"
    print_key_summary "after rotation (RW)  " "${mkid_rw}"     "${tek_rw}"
    echo ""
    echo "PDB master key:        ${mek_before} -> ${mek_after_ro} -> ${mek_after_rw}"
    echo "Tablespace key follows: read only $( [[ "${mkid_after}" == "${mkid_before}" ]] && echo "NO - still bound to the old master key" || echo "yes" ), read write $( [[ "${mkid_rw}" == "${mek_after_rw}" ]] && echo "yes" || echo "NO" )"

    print_verdict "${verdict}" "${msg}"
    lib_info "Done."
}

main "$@"
# --- EOF ----------------------------------------------------------------------
