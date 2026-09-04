#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: 40_variant_c.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026-09-04
# Version....: 0.1.0
# Purpose....: Variant C: DUPLICATE DATABASE ... AS ENCRYPTED
#              Uses RMAN DUPLICATE with BACKUP LOCATION instead of an active
#              connection to clone the prod backup into odbencdev.
#              Expected result: runs to completion, cloned DB opens, already-
#              encrypted USERS retains the original TEK and all 313 canary
#              blocks are ciphertext-identical to prod. The five formerly
#              unencrypted tablespaces are encrypted under the existing
#              Database Key of the PDB, NOT under new TEK material.
# Notes......: Prerequisites: step 15 (backup) must have completed.
#              CRITICAL: Variant C requires an unmodified Auxiliary instance.
#              If any previous variant has already run a RESTORE or modified the
#              target controlfile, DUPLICATE will abort with ORA-01507
#              "database not mounted". This script resets odbencdev to guarantee
#              a pristine Auxiliary before calling tde_clone.sh.
#              Service name is FREE.oradba.ch, not FREE - tnsping on the wrong
#              service name may report OK but the connection will fail with
#              ORA-12514.
#              The auto-login keystore cwallet.sso staged from prod is
#              host-bound (LOCAL). After transport, the dev container generates
#              a new LOCAL AUTO_LOGIN from the imported ewallet.p12.
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

LABEL="variant_c"
CLONE_EXTRA_ARGS=()

# ------------------------------------------------------------------------------
# usage
# ------------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

  Variant C: DUPLICATE DATABASE ... BACKUP LOCATION ... AS ENCRYPTED.

  Resets odbencdev to a pristine state (required by DUPLICATE), then runs
  RMAN DUPLICATE using the staged backup. Collects evidence set 'variant_c'
  and compares ciphertext blocks with 'baseline'.

  Prerequisite: step 15 (backup) must have completed.
  Note: DUPLICATE requires an unmodified Auxiliary instance. This script
  always resets odbencdev before running - do not skip the reset.

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
    step_header "Step 40: Variant C - DUPLICATE ... AS ENCRYPTED"

    require_command docker
    require_container "${PROD_SERVICE}"
    require_state "SOURCE_DBID"  "source DBID (run step 10 first)"
    require_state "BACKUP_READY" "backup flag (run step 15 first)"

    local dbid cf_piece
    dbid=$(read_state "SOURCE_DBID")
    # The source control file autobackup, recorded by step 15. Passing it
    # explicitly avoids restoring the target's own autobackup from a previous run.
    cf_piece=$(read_state "BACKUP_CF_PIECE")

    # DUPLICATE requires a pristine Auxiliary - always reset
    step_header "Reset odbencdev (required for DUPLICATE)"
    reset_service "${DEV_SERVICE}"
    start_service "${DEV_SERVICE}"
    wait_for_ready "${DEV_SERVICE}" 600

    # tde_clone.sh --variant c handles:
    #   1. Transport prod ewallet.p12, create LOCAL AUTO_LOGIN on dev host
    #   2. Start auxiliary NOMOUNT
    #   3. DUPLICATE DATABASE TO FREE BACKUP LOCATION '...' NOFILENAMECHECK AS ENCRYPTED
    step_header "DUPLICATE DATABASE ... AS ENCRYPTED"
    lib_info "DBID: ${dbid}"

    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        lib_info "DRY-RUN: would run: ${CLONE_SCRIPT} --variant c --dbid ${dbid} --cf-piece ${cf_piece}"
    else
        "${CLONE_SCRIPT}" \
            --variant c \
            --dbid     "${dbid}" \
            --cf-piece "${cf_piece}" \
            "${CLONE_EXTRA_ARGS[@]}"
    fi

    # Collect evidence on the cloned dev database
    step_header "Collect evidence set '${LABEL}'"
    collect_evidence "${DEV_SERVICE}" "${PROD_PDB}" "${LABEL}" "USERS"

    # Compare ciphertext blocks with the baseline
    step_header "Compare '${LABEL}' vs 'baseline'"
    compare_evidence "baseline" "${LABEL}"

    # Read key values from the clone
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

    # Report the canary data blocks separately. The overall block counts are
    # dominated by never used blocks, which RMAN does not back up and writes
    # fresh on restore - they differ in every variant and carry no meaning.
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
    elif [[ "${tek_clone}" == "${tek_source}" ]]; then
        if [[ ${canary_rc} -eq 2 ]]; then
            verdict="FAIL"
            msg="TEK is identical but the canary blocks could not be compared - no verdict possible"
        elif [[ ${canary_rc} -eq 0 ]]; then
            verdict="PASS"
            msg="TEK IDENTICAL and canary ciphertext IDENTICAL (${canary_cmp}) - DUPLICATE preserved the existing TEK, no new TEK for encrypted source"
        else
            verdict="FAIL"
            msg="TEK is identical but the canary ciphertext changed (${canary_cmp}) - contradictory, investigate before using this result"
        fi
    else
        verdict="FAIL"
        msg="TEK differs from baseline (unexpected for variant C)"
    fi

    write_state "VARIANT_C_MKID" "${mkid_clone}"
    write_state "VARIANT_C_TEK"  "${tek_clone}"

    print_key_summary "variant_c (clone)" "${mkid_clone}" "${tek_clone}"
    print_key_summary "baseline  (source)" "${mkid_source}" "${tek_source}"

    echo ""
    echo "TEK comparison: $( [[ "${tek_clone}" == "${tek_source}" ]] && echo "IDENTICAL" || echo "DIFFERENT")"

    print_verdict "${verdict}" "${msg}"
    lib_info "Done."
}

main "$@"
# --- EOF ----------------------------------------------------------------------
