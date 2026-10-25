#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: 30_variant_b2.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026-09-04
# Version....: 0.3.0
# Purpose....: Variant B2: RESTORE DATABASE AS ENCRYPTED USING KEY without the
#              source MEK present in the target keystore.
#              This tests the documented RESTORE ... AS ENCRYPTED path where only
#              a dev-own target key is available and the prod MEK is absent.
#              Expected result: RMAN fails with ORA-28374 "typed master key not
#              found in wallet" (reported under ORA-19870), and without an
#              ORA-00600. RMAN must be able to read
#              the source blocks (which are encrypted under the prod MEK) to re-
#              encrypt them. Without the prod MEK the blocks are unreadable.
#              A controlled failure is a valid and informative test result.
# Notes......: Prerequisites: step 15 (backup) must have completed.
#              tde_clone.sh --variant b2 performs:
#              - Set up a dev-own keystore and create a new MEK
#              - DO NOT import the prod MEK
#              - RESTORE DATABASE AS ENCRYPTED USING KEY '<dev_key_id>'
#              The resulting ORA-19870 / ORA-28374 is captured in the log;
#              the script does not abort - the error IS the result.
#              PASS requires ORA-28374 and no ORA-00600. ORA-19870 alone is
#              only the RMAN wrapper; together with ORA-00600 it is the B1
#              signature (source key present), not B2.
# Reference..: https://github.com/oehrlis/oracle-free-labs
# License....: Apache License Version 2.0, January 2004 as shown
#              at http://www.apache.org/licenses/
# ------------------------------------------------------------------------------
# CHANGE LOG:
# 2026-09-04  oes  Initial release                                        0.1.0
# 2026-10-24  oes  Derive the verdict from the RMAN output: PASS needs
#                  ORA-19870 or ORA-28374, a bare non-zero exit is FAIL    0.2.0
# 2026-10-24  oes  PASS requires ORA-28374 and no ORA-00600; ORA-00600 is
#                  FAIL (source key present - B1); FAIL message no longer
#                  aborts under set -e; clone output removed by a trap      0.3.0
# ------------------------------------------------------------------------------

set -euo pipefail
SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="0.3.0"
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

  Variant B2: RESTORE AS ENCRYPTED USING KEY without the source MEK.

  Resets odbencdev, creates a dev-own MEK, then attempts
  RESTORE DATABASE AS ENCRYPTED USING KEY '<dev_key_id>' without staging
  the prod wallet. Captures the expected ORA-28374 failure (under ORA-19870);
  an ORA-00600 in the output means the source key was present and is FAIL.

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
# Helper: create a fresh dev MEK and return its key ID
# ------------------------------------------------------------------------------
create_dev_key() {
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        echo "DRY-RUN-DEV-KEY-ID"
        return 0
    fi
    local keyid
    # Create the keystore, set a new MEK, return its KEY_ID
    keyid=$(docker exec "${DEV_SERVICE}" bash -c '
KSPWD=$(cat '"${WALLET_DIR_CONTAINER}"'/wallet_pwd.txt)
sqlplus -S / as sysdba <<SQL 2>/dev/null
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 200 TRIMSPOOL ON
ADMINISTER KEY MANAGEMENT SET KEY IDENTIFIED BY "${KSPWD}" WITH BACKUP CONTAINER=ALL;
SELECT key_id FROM v\$encryption_keys WHERE keystore_type != '"'"'UNKNOWN'"'"' AND rownum=1;
EXIT
SQL
' 2>/dev/null | grep -viE "identified by" \
    | awk 'NF && length($1) > 10 { print $1; exit }')
    printf '%s\n' "${keyid}"
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
main() {
    lib_info "Starting ${SCRIPT_NAME} ${VERSION}"
    step_header "Step 30: Variant B2 - AS ENCRYPTED without prod MEK"

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

    # Create a fresh dev MEK (no prod MEK imported)
    step_header "Create dev-own MEK (no prod MEK)"
    local dev_key_id
    dev_key_id=$(create_dev_key)
    lib_info "dev key ID: ${dev_key_id:0:16}..."

    write_state "VARIANT_B2_DEV_KEY" "${dev_key_id}"

    # Attempt the clone - this is expected to fail with ORA-28374
    step_header "Attempt RESTORE AS ENCRYPTED USING KEY (expected to fail)"
    lib_info "DBID: ${dbid}, dev key: ${dev_key_id:0:16}..."

    local clone_exit=0
    # Not local: the EXIT trap runs after main has returned.
    CLONE_OUT=$(mktemp)
    trap 'rm -f "${CLONE_OUT}"' EXIT
    local clone_out="${CLONE_OUT}"
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        lib_info "DRY-RUN: would run: ${CLONE_SCRIPT} --variant b2 --dbid ${dbid} --cf-piece ${cf_piece} --key <dev_key_id>"
    else
        set +e
        "${CLONE_SCRIPT}" \
            --variant b2 \
            --dbid     "${dbid}" \
            --cf-piece "${cf_piece}" \
            --key    "${dev_key_id}" \
            "${CLONE_EXTRA_ARGS[@]}" 2>&1 | tee "${clone_out}"
        clone_exit=${PIPESTATUS[0]}
        set -e
    fi

    # Record the result
    step_header "Result"
    local verdict msg
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        verdict="PASS"
        msg="DRY-RUN - no actual RMAN run"
    elif [[ "${clone_exit}" -ne 0 ]] && grep -q "ORA-00600" "${clone_out}"; then
        # ORA-19870 together with ORA-00600 is the B1 signature: RMAN could
        # read the source blocks, so the source key was in the keystore.
        verdict="FAIL"
        msg="RMAN failed with ORA-00600 (exit ${clone_exit}): source key present - this is B1, not B2: $({ grep -m1 -o "ORA-00600.*" "${clone_out}" || true; } | tail -c 120)"
    elif [[ "${clone_exit}" -ne 0 ]] && grep -qE "^ORA-28374:" "${clone_out}"; then
        verdict="PASS"
        msg="RMAN failed as expected (exit ${clone_exit}): $({ grep -E "^ORA-(19870|28374):" "${clone_out}" || true; } | sed 's/ \/opt.*//' | paste -sd ' ' -)"
    elif [[ "${clone_exit}" -ne 0 ]]; then
        # Same trap as in step 35 before 2026-09-22: a fixed PASS text on any
        # non-zero exit turns a usage error into a measurement. ORA-19870
        # without ORA-28374 does not name the missing key either.
        verdict="FAIL"
        msg="clone aborted (exit ${clone_exit}) without ORA-28374: $({ grep -m1 -iE "ERROR|ORA-[0-9]+" "${clone_out}" || true; } | tail -c 120)"
    else
        verdict="FAIL"
        msg="RMAN unexpectedly succeeded without prod MEK - investigate"
    fi

    write_state "VARIANT_B2_EXIT" "${clone_exit}"

    print_verdict "${verdict}" "${msg}"
    lib_info "Done."
}

main "$@"
# --- EOF ----------------------------------------------------------------------
