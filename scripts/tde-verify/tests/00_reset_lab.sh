#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: 00_reset_lab.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026-09-04
# Version....: 0.1.0
# Purpose....: Reset both TDE lab services (odbencprod and odbencdev) to a clean
#              state, bring them up fresh, wait until each reports
#              "DATABASE IS READY TO USE", then scan the setup logs for
#              ORA-/SP2-/DBT- error lines and report the result.
# Notes......: This script is destructive: it calls `docker compose down -v`
#              and removes data/<service>/ for both services. It therefore
#              requires --yes (or FORCE_YES=TRUE in the environment) to proceed.
#              After a successful run the lab state file is cleared so that
#              subsequent test scripts start with a known-good baseline.
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
ENABLE_DELETE=${ENABLE_DELETE:-"FALSE"}
FORCE_YES=${FORCE_YES:-"FALSE"}

# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

# ------------------------------------------------------------------------------
# usage
# ------------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

  Reset both TDE lab services (odbencprod and odbencdev) to a clean state.
  Stops the containers, removes all data volumes, starts them fresh, waits
  for "DATABASE IS READY TO USE" in each service's logs, then checks for
  ORA-/SP2-/DBT- errors and reports pass/fail.

  This step is destructive - all data in both services is lost.

Options:
  -h, --help      Show this help and exit
  -v, --verbose   Enable verbose output
      --delete       Also clear data/xchange (drops the previous run's evidence)
  -d, --dry-run   Show what would be done; change nothing
  -y, --yes       Skip the confirmation prompt (required for unattended use)

Environment:
  FORCE_YES=TRUE  Equivalent to --yes
  VERBOSE=TRUE    Equivalent to --verbose
  DRY_RUN=TRUE    Equivalent to --dry-run

Examples:
  ${SCRIPT_NAME} --dry-run
  ${SCRIPT_NAME} --yes
  FORCE_YES=TRUE ${SCRIPT_NAME}

EOF
}

# ------------------------------------------------------------------------------
# Parse arguments
# ------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)    usage; exit 0 ;;
        -v|--verbose) VERBOSE="TRUE"; shift ;;
           --delete)   ENABLE_DELETE="TRUE"; shift ;;
        -d|--dry-run) DRY_RUN="TRUE"; shift ;;
        -y|--yes)     FORCE_YES="TRUE"; shift ;;
        *) lib_err "Unknown option: $1"; usage; exit 1 ;;
    esac
done

# ------------------------------------------------------------------------------
# Function: clean_xchange
# Purpose.: Remove the artefacts of previous runs from the exchange mount
# Args....: none
# Returns.: 0 always
# Output..: one line per removed item, or a warning when leftovers are kept
# Depends.: find
# Example.: clean_xchange
# Notes...: make reset only wipes data/<service>, so backup pieces, wallet
#           copies and evidence sets from earlier runs survive it. Stale
#           evidence labels next to fresh ones are easy to misread, and old
#           backup pieces can be catalogued by RMAN. Guarded by --delete
#           because it discards every measurement of the previous run.
#           README.md and the directory itself are kept.
# ------------------------------------------------------------------------------
clean_xchange() {
    local xh="${REPO_DIR}/data/xchange"
    [[ -d "${xh}" ]] || return 0

    if [[ "${ENABLE_DELETE}" != "TRUE" ]]; then
        local leftovers
        leftovers=$(find "${xh}" -mindepth 1 -maxdepth 1 ! -name 'README.md' 2>/dev/null | wc -l | tr -d ' ')
        if [[ "${leftovers}" -gt 0 ]]; then
            lib_warn "data/xchange still holds ${leftovers} item(s) from an earlier run"
            lib_warn "evidence sets and backup pieces would be mixed with this run"
            lib_warn "rerun with --delete to start from an empty exchange mount"
        fi
        return 0
    fi

    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        lib_info "DRY-RUN: would clear ${xh} except README.md"
        return 0
    fi

    local item
    while IFS= read -r item; do
        [[ -n "${item}" ]] || continue
        rm -rf "${item}"
        lib_info "removed ${item#"${REPO_DIR}/"}"
    done < <(find "${xh}" -mindepth 1 -maxdepth 1 ! -name 'README.md' 2>/dev/null)
    lib_info "exchange mount cleared"
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
main() {
    lib_info "Starting ${SCRIPT_NAME} ${VERSION}"
    step_header "Step 00: Reset lab services"

    require_command docker

    # Confirmation (destructive operation)
    if [[ "${FORCE_YES}" != "TRUE" && "${DRY_RUN}" != "TRUE" ]]; then
        lib_warn "This will destroy ALL data in odbencprod and odbencdev."
        read -rp "Confirm full lab reset? [y/N] " _reply
        [[ "${_reply}" == [yY] ]] || { lib_warn "aborted by user"; exit 1; }
    fi

    # Clear the lab state so subsequent scripts don't use stale values
    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        rm -f "${STATE_FILE}"
        mkdir -p "${EVIDENCE_ROOT}"
    else
        lib_info "DRY-RUN: would remove ${STATE_FILE}"
    fi

    # Reset and restart prod service
    step_header "Reset odbencprod"
    clean_xchange

    reset_service "${PROD_SERVICE}"
    start_service "${PROD_SERVICE}"
    wait_for_ready "${PROD_SERVICE}" 900

    # Reset and restart dev service
    step_header "Reset odbencdev"
    reset_service "${DEV_SERVICE}"
    start_service "${DEV_SERVICE}"
    wait_for_ready "${DEV_SERVICE}" 600

    # Scan setup logs for errors
    step_header "Log scan"
    local prod_errors=0 dev_errors=0
    check_logs_for_errors "${PROD_SERVICE}" || prod_errors=1
    check_logs_for_errors "${DEV_SERVICE}"  || dev_errors=1

    # Summary
    echo ""
    printf '%-20s %-10s %-10s\n' "Service" "Ready" "Log errors"
    printf '%-20s %-10s %-10s\n' "-------" "-----" "----------"
    printf '%-20s %-10s %-10s\n' "${PROD_SERVICE}" "yes" \
        "$( (( prod_errors == 0 )) && echo "none" || echo "FOUND")"
    printf '%-20s %-10s %-10s\n' "${DEV_SERVICE}" "yes" \
        "$( (( dev_errors == 0 )) && echo "none" || echo "FOUND")"

    if (( prod_errors > 0 || dev_errors > 0 )); then
        print_verdict "FAIL" "error lines found in setup logs - check output above"
        exit 1
    fi

    print_verdict "PASS" "both services are up, healthy, and clean"
    lib_info "Done."
}

main "$@"
# --- EOF ----------------------------------------------------------------------
