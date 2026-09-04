#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: 20_variant_a.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026-09-04
# Version....: 0.1.0
# Purpose....: Variant A: plain RESTORE with the transported source keystore.
#              This is the customer's current practice. The source wallet
#              (ewallet.p12) is placed into the target's keystore directory
#              before the restore, so the target opens the prod database under
#              the prod master encryption key.
#              Expected result: all ciphertext blocks are IDENTICAL to prod -
#              no re-encryption, no new TEK. The target is fully dependent on
#              the prod MEK for the rest of its life.
# Notes......: Prerequisites: step 15 (backup) must have completed.
#              The dev service is reset to a fresh state at the start of this
#              step so the target is clean before the restore.
#              Fallstricke:
#              - cwallet.sso is LOCAL auto-login; it will not open on a
#                different host (ORA-28365). Do not stage it; open by password.
#              - A foreign cwallet.sso blocks CREATE LOCAL AUTO_LOGIN KEYSTORE
#                with ORA-46630. Keep only ewallet.p12 on the target.
#              - Online redo logs of the target collide with the restored
#                controlfile (ORA-19698). quarantine_stale_redo in tde_clone.sh
#                moves them; verify the xchange/stale_redo dir afterwards.
#              - SET UNTIL SEQUENCE <n+1> is required to avoid RMAN-06054.
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

LABEL="variant_a"
CLONE_EXTRA_ARGS=()

# ------------------------------------------------------------------------------
# usage
# ------------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

  Variant A: plain RESTORE with transported source keystore.

  Resets odbencdev, restores the prod backup using the prod keystore, collects
  evidence set 'variant_a', and compares ciphertext blocks with 'baseline'.

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
    step_header "Step 20: Variant A - plain RESTORE with source keystore"

    require_command docker
    require_container "${PROD_SERVICE}"
    require_state "SOURCE_DBID"  "source DBID (run step 10 first)"
    require_state "BACKUP_READY" "backup flag (run step 15 first)"

    local dbid cf_piece
    dbid=$(read_state "SOURCE_DBID")
    # The source control file autobackup, recorded by step 15. Passing it
    # explicitly avoids restoring the target's own autobackup from a previous run.
    cf_piece=$(read_state "BACKUP_CF_PIECE")

    # Reset odbencdev to a clean state
    step_header "Reset odbencdev"
    reset_service "${DEV_SERVICE}"
    start_service "${DEV_SERVICE}"
    wait_for_ready "${DEV_SERVICE}" 600

    # Run the clone via tde_clone.sh (variant a handles wallet transport)
    # --delete is required because variant a replaces the target keystore
    step_header "Clone via tde_clone.sh --variant a"
    lib_info "DBID: ${dbid}"
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        lib_info "DRY-RUN: would run: ${CLONE_SCRIPT} --variant a --dbid ${dbid} --cf-piece ${cf_piece} --delete --yes"
    else
        "${CLONE_SCRIPT}" \
            --variant a \
            --dbid     "${dbid}" \
            --cf-piece "${cf_piece}" \
            --delete \
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

    # Verdict
    local verdict="PASS" msg=""
    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        if [[ "${tek_clone}" == "${tek_source}" ]]; then
            msg="TEK IDENTICAL to baseline - pure re-wrap, no new TEK (expected for variant A)"
        else
            verdict="FAIL"
            msg="TEK differs from baseline (unexpected for variant A)"
        fi
    else
        msg="DRY-RUN - no comparison performed"
    fi

    write_state "VARIANT_A_MKID" "${mkid_clone}"
    write_state "VARIANT_A_TEK"  "${tek_clone}"

    print_key_summary "variant_a (clone)" "${mkid_clone}" "${tek_clone}"
    print_key_summary "baseline  (source)" "${mkid_source}" "${tek_source}"

    echo ""
    echo "TEK comparison: $( [[ "${tek_clone}" == "${tek_source}" ]] && echo "IDENTICAL" || echo "DIFFERENT")"
    echo "MASTERKEYID:    $( [[ "${mkid_clone}" == "${mkid_source}" ]] && echo "IDENTICAL" || echo "DIFFERENT")"

    print_verdict "${verdict}" "${msg}"
    lib_info "Done."
}

main "$@"
# --- EOF ----------------------------------------------------------------------
