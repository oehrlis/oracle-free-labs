#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: 70_variant_g.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026-09-04
# Version....: 0.1.0
# Purpose....: Variant G: ALTER TABLESPACE USERS ENCRYPTION ONLINE REKEY
#              Tests whether ONLINE REKEY generates genuinely new TEK material.
#              Expected result: ciphertext DIFFERS from prod (KEY_VERSION
#              increments, new datafile created, nearly all blocks rewritten).
#              Note: contrary to the original protocol assumption, ONLINE REKEY
#              IS available in Oracle Free 26ai (measured 2026-09-03, KEY_VERSION
#              3->4, TEK changed, 2560 of 2561 blocks differ). It is an EE
#              feature from a licensing perspective but not technically blocked.
#              The licence implication must be documented in the protocol.
# Notes......: Prerequisites: step 15 (backup) must have completed.
#              This variant starts with a variant A base (RESTORE with prod
#              keystore) so that USERS is encrypted. USERS must be READ WRITE
#              before ONLINE REKEY.
#              ONLINE REKEY creates a new datafile on disk. The old datafile is
#              removed by Oracle after the operation. tde_evidence.sh compares
#              fingerprints by filename, so the new datafile name is the same;
#              the comparison will see all allocated blocks as changed.
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

LABEL="variant_g"
CLONE_EXTRA_ARGS=()

# ------------------------------------------------------------------------------
# usage
# ------------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

  Variant G: ALTER TABLESPACE USERS ENCRYPTION ONLINE REKEY.

  Resets odbencdev, restores via variant A (USERS is encrypted), sets USERS
  READ WRITE, then runs ONLINE REKEY. Collects evidence set 'variant_g' and
  compares ciphertext with 'baseline'. Expects blocks to differ (new TEK).

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
    step_header "Step 70: Variant G - ONLINE REKEY"

    require_command docker
    require_container "${PROD_SERVICE}"
    require_state "SOURCE_DBID"  "source DBID (run step 10 first)"
    require_state "BACKUP_READY" "backup flag (run step 15 first)"

    local dbid
    dbid=$(read_state "SOURCE_DBID")

    # Reset odbencdev
    step_header "Reset odbencdev"
    reset_service "${DEV_SERVICE}"
    start_service "${DEV_SERVICE}"
    wait_for_ready "${DEV_SERVICE}" 600

    # Phase 1: variant A base (RESTORE with transported prod keystore)
    step_header "Phase 1: Variant A base (RESTORE with prod keystore)"
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        lib_info "DRY-RUN: would run: ${CLONE_SCRIPT} --variant a --dbid ${dbid} --delete"
    else
        "${CLONE_SCRIPT}" \
            --variant a \
            --dbid   "${dbid}" \
            --delete \
            "${CLONE_EXTRA_ARGS[@]}"
    fi

    # Capture the TEK and key version BEFORE rekey
    step_header "Capture key chain BEFORE ONLINE REKEY"
    local tek_before kv_before
    tek_before=""
    kv_before=""
    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        tek_before=$(get_encryptedkey "${DEV_SERVICE}" "${PROD_PDB}" "USERS")
        kv_before=$(printf '%s\n' "
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 80 TRIMSPOOL ON
ALTER SESSION SET CONTAINER=${PROD_PDB};
SELECT key_version FROM v\$encrypted_tablespaces WHERE ts# = (SELECT ts# FROM v\$tablespace WHERE name='USERS' AND con_id=sys_context('userenv','con_id'));
EXIT" | docker exec -i "${DEV_SERVICE}" sqlplus -S / as sysdba 2>/dev/null \
            | awk 'NF && $1 ~ /^[0-9]+$/ { print $1; exit }')
fi
    if [[ "${DRY_RUN}" != "TRUE" && -z "${kv_before}" ]]; then
        # An empty KEY_VERSION would slip into the verdict comparison and could
        # turn a failed measurement into a PASS.
        lib_err "KEY_VERSION query returned nothing (kv_before)"
        return 1
    fi
    lib_info "TEK before REKEY : ${tek_before:0:16}..."
    lib_info "KEY_VERSION before: ${kv_before}"

    # Phase 2: Set USERS READ WRITE (came back READ ONLY from restore)
    step_header "Phase 2: Set USERS READ WRITE"
    sqlplus_dev "
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SESSION SET CONTAINER=${PROD_PDB};
ALTER TABLESPACE USERS READ WRITE;
SELECT tablespace_name, status FROM dba_tablespaces WHERE tablespace_name='USERS';
EXIT
"

    # Phase 3: ONLINE REKEY
    step_header "Phase 3: ALTER TABLESPACE USERS ENCRYPTION ONLINE REKEY"
    sqlplus_dev "
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SESSION SET CONTAINER=${PROD_PDB};
ALTER TABLESPACE USERS ENCRYPTION ONLINE REKEY;
SELECT tablespace_name, encrypted FROM dba_tablespaces WHERE tablespace_name='USERS';
SELECT RAWTOHEX(masterkeyid), RAWTOHEX(encryptedkey), key_version, ciphermode
  FROM v\$encrypted_tablespaces WHERE ts# = (SELECT ts# FROM v\$tablespace WHERE name='USERS' AND con_id=sys_context('userenv','con_id'));
EXIT
"

    # Capture the TEK and key version AFTER rekey
    step_header "Capture key chain AFTER ONLINE REKEY"
    local tek_after kv_after
    tek_after=""
    kv_after=""
    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        tek_after=$(get_encryptedkey "${DEV_SERVICE}" "${PROD_PDB}" "USERS")
        kv_after=$(printf '%s\n' "
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 80 TRIMSPOOL ON
ALTER SESSION SET CONTAINER=${PROD_PDB};
SELECT key_version FROM v\$encrypted_tablespaces WHERE ts# = (SELECT ts# FROM v\$tablespace WHERE name='USERS' AND con_id=sys_context('userenv','con_id'));
EXIT" | docker exec -i "${DEV_SERVICE}" sqlplus -S / as sysdba 2>/dev/null \
            | awk 'NF && $1 ~ /^[0-9]+$/ { print $1; exit }')
fi
    if [[ "${DRY_RUN}" != "TRUE" && -z "${kv_before}" ]]; then
        # An empty KEY_VERSION would slip into the verdict comparison and could
        # turn a failed measurement into a PASS.
        lib_err "KEY_VERSION query returned nothing (kv_before)"
        return 1
    fi
    lib_info "TEK after REKEY  : ${tek_after:0:16}..."
    lib_info "KEY_VERSION after : ${kv_after}"

    # Collect evidence
    step_header "Collect evidence set '${LABEL}'"
    collect_evidence "${DEV_SERVICE}" "${PROD_PDB}" "${LABEL}" "USERS"

    # Compare with baseline
    step_header "Compare '${LABEL}' vs 'baseline' (expect DIFFERENT)"
    compare_evidence "baseline" "${LABEL}"

    local mkid_clone
    mkid_clone=""
    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        mkid_clone=$(get_masterkeyid "${DEV_SERVICE}" "${PROD_PDB}" "USERS")
    fi

    local tek_source
    tek_source=$(read_state "SOURCE_TEK")

    local verdict msg
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        verdict="PASS"
        msg="DRY-RUN"
    elif [[ "${tek_after}" != "${tek_source}" && "${tek_after}" != "${tek_before}" ]]; then
        verdict="PASS"
        msg="TEK changed by ONLINE REKEY (${kv_before} -> ${kv_after}), differs from prod baseline"
    elif [[ "${tek_after}" == "${tek_source}" ]]; then
        verdict="FAIL"
        msg="TEK still matches prod baseline after ONLINE REKEY - no new TEK generated"
    else
        verdict="FAIL"
        msg="TEK unchanged by ONLINE REKEY (KEY_VERSION did not increment)"
    fi

    write_state "VARIANT_G_MKID"       "${mkid_clone}"
    write_state "VARIANT_G_TEK_BEFORE" "${tek_before}"
    write_state "VARIANT_G_TEK_AFTER"  "${tek_after}"
    write_state "VARIANT_G_KV_BEFORE"  "${kv_before}"
    write_state "VARIANT_G_KV_AFTER"   "${kv_after}"

    echo ""
    echo "KEY_VERSION  : ${kv_before} -> ${kv_after}"
    echo "TEK before   : ${tek_before:0:32}..."
    echo "TEK after    : ${tek_after:0:32}..."
    echo "TEK vs prod  : $( [[ "${tek_after}" == "${tek_source}" ]] && echo "IDENTICAL" || echo "DIFFERENT (expected)")"
    echo "Note: ONLINE REKEY is available in Oracle Free 26ai but is an EE feature."

    print_verdict "${verdict}" "${msg}"
    lib_info "Done."
}

main "$@"
# --- EOF ----------------------------------------------------------------------
