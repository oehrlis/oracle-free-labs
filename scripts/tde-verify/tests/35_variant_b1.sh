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
#              This step creates the dev MEK itself and hands the key ID to
#              tde_clone.sh, which then performs:
#              - Transport the prod wallet (ewallet.p12) to the dev keystore
#              - RESTORE DATABASE AS ENCRYPTED USING KEY '<dev_key_id>'
#              PASS requires an actual ORA-00600 in the output. A non-zero exit
#              without it is a failed run, not a measurement, and is reported
#              as FAIL.
# Reference..: https://github.com/oehrlis/oracle-free-labs
# License....: Apache License Version 2.0, January 2004 as shown
#              at http://www.apache.org/licenses/
# ------------------------------------------------------------------------------
# CHANGE LOG:
# 2026-09-04  oes  Initial release                                        0.1.0
# 2026-09-22  oes  Pass --key so the variant runs at all; derive the verdict
#                  from the output instead of a fixed string               0.2.0
# ------------------------------------------------------------------------------

set -euo pipefail
SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="0.2.0"
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
    step_header "Step 35: Variant B1 - AS ENCRYPTED with prod MEK + new dev MEK"

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

    # The target keystore must already hold its own MEK - tde_clone.sh imports
    # the prod MEK on top of it and restores AS ENCRYPTED USING KEY '<dev_key_id>'.
    # tde_clone.sh does NOT create that key; --key is required for variant b1.
    step_header "Create dev-own MEK (prod MEK is imported on top)"
    local dev_key_id
    dev_key_id=$(create_dev_key)
    if [[ -z "${dev_key_id}" ]]; then
        print_verdict "FAIL" "no dev MEK created - cannot run variant b1"
        return 1
    fi
    lib_info "dev key ID: ${dev_key_id:0:16}..."
    write_state "VARIANT_B1_DEV_KEY" "${dev_key_id}"

    step_header "Attempt RESTORE AS ENCRYPTED USING KEY (prod MEK present)"
    lib_info "DBID: ${dbid}, dev key: ${dev_key_id:0:16}..."

    local clone_exit=0 clone_out
    clone_out=$(mktemp)
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        lib_info "DRY-RUN: would run: ${CLONE_SCRIPT} --variant b1 --dbid ${dbid} --cf-piece ${cf_piece} --key <dev_key_id>"
    else
        set +e
        "${CLONE_SCRIPT}" \
            --variant b1 \
            --dbid     "${dbid}" \
            --cf-piece "${cf_piece}" \
            --key      "${dev_key_id}" \
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
        verdict="PASS"
        msg="RMAN failed as expected (exit ${clone_exit}): $(grep -m1 -o "ORA-00600.*" "${clone_out}")"
    elif [[ "${clone_exit}" -ne 0 ]]; then
        # A non-zero exit alone proves nothing: a usage error looks identical to
        # a controlled RMAN failure. Only an ORA-00600 in the output is the
        # measurement this step exists for - anything else is a failed run and
        # must say so instead of reporting a result that was never obtained.
        verdict="FAIL"
        msg="clone aborted (exit ${clone_exit}) without ORA-00600 - RMAN never reached the encrypted datafile: $(grep -m1 -iE "ERROR|ORA-[0-9]+" "${clone_out}" | tail -c 120)"
    else
        verdict="FAIL"
        msg="RMAN unexpectedly succeeded - investigate the key chain result"
    fi

    rm -f "${clone_out}"
    write_state "VARIANT_B1_EXIT" "${clone_exit}"

    print_verdict "${verdict}" "${msg}"
    lib_info "Done."
}

main "$@"
# --- EOF ----------------------------------------------------------------------
