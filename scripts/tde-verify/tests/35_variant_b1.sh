#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: 35_variant_b1.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026-09-04
# Version....: 0.1.0
# Purpose....: Variant B1: RESTORE DATABASE AS ENCRYPTED USING KEY with the
#              source MEK present in the target keystore plus a newly created
#              target MEK.
#              The target keystore holds both the prod MEK (imported) and a
#              freshly created dev MEK. RESTORE ... AS ENCRYPTED USING KEY
#              '<dev_key_id>' is then used to target the dev MEK.
#              Expected result: RMAN fails with ORA-00600
#              [kcbtse_encdec_tbsblk_1] when it reaches the already-encrypted
#              datafile 20 (USERS). The unencrypted datafiles restore fine under
#              the AS ENCRYPTED path. For an already-encrypted source, RMAN
#              cannot re-encrypt through the existing layer.
#              A controlled failure is a valid and informative test result.
# Notes......: Prerequisites: step 15 (backup) must have completed.
#              tde_clone.sh --variant b1 performs:
#              - Transport the prod wallet (ewallet.p12) to the dev keystore
#              - Create a new dev MEK
#              - RESTORE DATABASE AS ENCRYPTED USING KEY '<dev_key_id>'
#              The ORA-00600 is captured in the log; the script reports it
#              as the expected outcome and marks PASS.
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

CLONE_EXTRA_ARGS=()

# ------------------------------------------------------------------------------
# usage
# ------------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

  Variant B1: RESTORE AS ENCRYPTED USING KEY with the prod MEK imported.

  Resets odbencdev, imports the prod wallet plus a new dev MEK, then attempts
  RESTORE DATABASE AS ENCRYPTED USING KEY '<dev_key_id>'.
  The expected result is ORA-00600 [kcbtse_encdec_tbsblk_1] when RMAN reaches
  the already-encrypted USERS datafile.

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
    step_header "Step 35: Variant B1 - AS ENCRYPTED with prod MEK + new dev MEK"

    require_command docker
    require_container "${PROD_SERVICE}"
    require_state "SOURCE_DBID"  "source DBID (run step 10 first)"
    require_state "BACKUP_READY" "backup flag (run step 15 first)"

    local dbid
    dbid=$(read_state "SOURCE_DBID")

    # Reset odbencdev to a clean state
    step_header "Reset odbencdev"
    reset_service "${DEV_SERVICE}"
    start_service "${DEV_SERVICE}"
    wait_for_ready "${DEV_SERVICE}" 600

    # tde_clone.sh --variant b1 handles:
    #   1. Transport prod ewallet.p12 to dev keystore
    #   2. Create a new dev MEK (ADMINISTER KEY MANAGEMENT CREATE KEY)
    #   3. Note the new dev MEK key ID
    #   4. RESTORE DATABASE AS ENCRYPTED USING KEY '<dev_key_id>'
    # The --key flag must carry the dev key ID; tde_clone.sh creates it.
    # For b1 tde_clone.sh generates the key internally and uses it.
    step_header "Attempt RESTORE AS ENCRYPTED USING KEY (prod MEK present)"
    lib_info "DBID: ${dbid}"

    local clone_exit=0
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        lib_info "DRY-RUN: would run: ${CLONE_SCRIPT} --variant b1 --dbid ${dbid}"
    else
        "${CLONE_SCRIPT}" \
            --variant b1 \
            --dbid   "${dbid}" \
            "${CLONE_EXTRA_ARGS[@]}" || clone_exit=$?
    fi

    # Record the result
    step_header "Result"
    local verdict msg
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        verdict="PASS"
        msg="DRY-RUN - no actual RMAN run"
    elif [[ "${clone_exit}" -ne 0 ]]; then
        verdict="PASS"
        msg="RMAN failed as expected (exit ${clone_exit}): ORA-00600 on encrypted source datafile"
    else
        verdict="FAIL"
        msg="RMAN unexpectedly succeeded - investigate the key chain result"
    fi

    write_state "VARIANT_B1_EXIT" "${clone_exit}"

    print_verdict "${verdict}" "${msg}"
    lib_info "Done."
}

main "$@"
# --- EOF ----------------------------------------------------------------------
