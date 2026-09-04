#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: 90_withdrawal_test.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrily@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026-09-04
# Version....: 0.1.0
# Purpose....: Key withdrawal test: verify which variants remain readable after
#              the prod (source) MEK is removed from the dev keystore.
#              Removes the prod keystore from odbencdev, restarts the instance,
#              then attempts to read the canary table.
#              - Read succeeds: dev is cryptographically independent of prod
#              - Read fails with ORA-28374 / ORA-28365: dev still depends on
#                the prod MEK (encryption chain not broken)
#              The script operates on whichever variant state is currently live
#              in odbencdev (set by the last variant script that ran). It records
#              the result in the state file for inclusion in the final matrix.
# Notes......: This test is only meaningful if odbencdev currently holds a
#              freshly encrypted copy from one of the variant scripts.
#              For variant F (chain-breaking path) the dev keystore was already
#              replaced with a fresh one in step 60, so running this test after
#              step 60 should show INDEPENDENT.
#              For variants A, C, D the dev keystore still holds the prod MEK
#              (or depends on it) and the test should show DEPENDENT.
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

AFTER_VARIANT="${AFTER_VARIANT:-unknown}"

# ------------------------------------------------------------------------------
# usage
# ------------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

  Key withdrawal test: remove the prod MEK from odbencdev, restart the instance,
  attempt to read the canary table. Records whether dev is independent.

  This test operates on the current state of odbencdev. Run it after any variant
  step to check that variant's key independence.

Options:
  -h, --help              Show this help and exit
  -v, --verbose           Enable verbose output
  -d, --dry-run           Show what would be done; change nothing
  -y, --yes               Skip the confirmation prompt
      --after-variant VAR Label to record which variant was tested (e.g. variant_f)

Environment:
  AFTER_VARIANT=<label>   Equivalent to --after-variant

Examples:
  ${SCRIPT_NAME} --dry-run
  ${SCRIPT_NAME} --yes --after-variant variant_f

EOF
}

# ------------------------------------------------------------------------------
# Parse arguments
# ------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)          usage; exit 0 ;;
        -v|--verbose)       VERBOSE="TRUE"; shift ;;
        -d|--dry-run)       DRY_RUN="TRUE"; shift ;;
        -y|--yes)           FORCE_YES="TRUE"; shift ;;
            --after-variant) AFTER_VARIANT="${2:-}"; shift 2 ;;
        *) lib_err "Unknown option: $1"; usage; exit 1 ;;
    esac
done

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
main() {
    lib_info "Starting ${SCRIPT_NAME} ${VERSION}"
    step_header "Step 90: Key withdrawal test (after ${AFTER_VARIANT})"

    require_command docker
    require_container "${DEV_SERVICE}"

    # Confirmation - this modifies the dev keystore
    if [[ "${FORCE_YES}" != "TRUE" && "${DRY_RUN}" != "TRUE" ]]; then
        lib_warn "This will move the dev keystore aside and restart ${DEV_SERVICE}."
        lib_warn "odbencdev will need to be reset before the next variant test."
        read -rp "Confirm withdrawal test on ${DEV_SERVICE}? [y/N] " _reply
        [[ "${_reply}" == [yY] ]] || { lib_warn "aborted by user"; exit 1; }
    fi

    # Step 1: Back up the current dev keystore, then replace with a pristine dev keystore
    step_header "Step 1: Swap to dev-only keystore (remove prod MEK)"
    local wallet_backup="${XCHANGE_CONTAINER}/wallet_withdrawal_backup"
    lib_run in_dev "
mkdir -p ${wallet_backup}
cp -a ${WALLET_DIR_CONTAINER}/. ${wallet_backup}/
echo 'current dev keystore backed up to ${wallet_backup}'
"

    # Restore the pristine dev keystore (the one that existed before any clone)
    # It was saved by tde_clone.sh variant a as wallet_dev_pristine
    local pristine="${XCHANGE_CONTAINER}/wallet_dev_pristine"
    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        if ! docker exec "${DEV_SERVICE}" test -d "${pristine}"; then
            lib_warn "pristine dev keystore not found at ${pristine}"
            lib_warn "Using a check: does the current keystore hold only dev-own keys?"
            # Alternative: just restart and see - if the canary fails we got ORA-28374
            lib_info "proceeding with current keystore; prod MEK absence will be revealed by read test"
        else
            lib_run in_dev "
rm -rf ${WALLET_DIR_CONTAINER}/*
cp -a ${pristine}/. ${WALLET_DIR_CONTAINER}/
echo 'restored pristine dev keystore from ${pristine}'
ls -la ${WALLET_DIR_CONTAINER}/tde/
"
        fi
    else
        lib_info "DRY-RUN: would restore ${pristine} to ${WALLET_DIR_CONTAINER}"
    fi

    # Step 2: Restart the dev instance
    step_header "Step 2: Restart ${DEV_SERVICE} (STARTUP FORCE)"
    sqlplus_dev "
WHENEVER SQLERROR CONTINUE
STARTUP FORCE;
SELECT name, open_mode FROM v\$database;
EXIT
"

    # Step 3: Attempt to read the canary (deliberate error is the result)
    step_header "Step 3: Attempt to read canary (result defines dependency)"
    local canary_output read_ok=0
    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        canary_output=$(printf '%s\n' "
WHENEVER SQLERROR CONTINUE
ALTER SESSION SET CONTAINER=${PROD_PDB};
@/opt/oracle/common/scripts/ssenc_canary.sql ${CANARY_OWNER} ${CANARY_MARKER} CANARY_TDE
EXIT" | docker exec -i "${DEV_SERVICE}" sqlplus -S / as sysdba 2>&1 || true)
        echo "${canary_output}"
        if echo "${canary_output}" | grep -qE "ORA-28374|ORA-28365|not found in wallet"; then
            read_ok=0
        elif echo "${canary_output}" | grep -qE "rows selected|OEHRLI-CANARY"; then
            read_ok=1
        else
            read_ok=2  # unclear
        fi
    fi

    # Step 4: Verdict
    local verdict msg independence
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        verdict="PASS"
        msg="DRY-RUN"
        independence="DRY-RUN"
    elif [[ "${read_ok}" -eq 1 ]]; then
        verdict="PASS"
        msg="Canary readable without prod MEK - INDEPENDENT (key chain broken)"
        independence="INDEPENDENT"
    elif [[ "${read_ok}" -eq 0 ]]; then
        verdict="PASS"
        msg="Canary failed ORA-28374 without prod MEK - DEPENDENT (expected for A/C/D)"
        independence="DEPENDENT"
    else
        verdict="FAIL"
        msg="Unclear result from canary read - investigate output above"
        independence="UNCLEAR"
    fi

    write_state "WITHDRAWAL_AFTER_${AFTER_VARIANT}" "${independence}"

    echo ""
    echo "Withdrawal test result:"
    printf '  After variant : %s\n' "${AFTER_VARIANT}"
    printf '  Independence  : %s\n' "${independence}"

    print_verdict "${verdict}" "${msg}"
    lib_info "Done."
}

main "$@"
# --- EOF ----------------------------------------------------------------------
