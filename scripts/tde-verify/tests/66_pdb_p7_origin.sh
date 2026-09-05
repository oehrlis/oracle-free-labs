#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: 68_pdb_p7_origin.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026-09-04
# Version....: 0.1.0
# Purpose....: PDB P7 - ORIGIN comparison: a formally imported key (P2/P4)
#              shows ORIGIN=IMPORTED in v$encryption_keys; a keystore that was
#              simply copied (RMAN Variant A) shows ORIGIN=LOCAL.
#              This distinction matters for auditing: ORIGIN=LOCAL means the
#              key looks native and cannot be distinguished from a locally
#              created key without additional evidence.
#              Queries v$encryption_keys in:
#              - the current target PDB (from state, P2 or P4 result)
#              - the source PDBCLONE in prod (always LOCAL)
#              Reads previously stored ORIGIN values for P2 and P4 from state.
#              Prints a comparison table for the report.
# Notes......: Prerequisite: step 63 (P2) or step 65 (P4).
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
CLONE_SRC_PDB="PDBCLONE"

# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

# ------------------------------------------------------------------------------
# usage
# ------------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

  PDB P7: ORIGIN comparison between formally imported keys and copied keystores.
  Queries v\$encryption_keys ORIGIN in the target PDB (P2 or P4 result) and
  source PDBCLONE. Prints a comparison table.
  Expected: target shows ORIGIN=IMPORTED; source shows ORIGIN=LOCAL.

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
    step_header "Step 68: PDB P7 - ORIGIN comparison"

    require_command docker
    require_container "${PROD_SERVICE}"
    require_container "${DEV_SERVICE}"
    require_healthy   "${PROD_SERVICE}"
    require_healthy   "${DEV_SERVICE}"
    require_state "PDB_TARGET_READY" "target PDB in dev (run step 63 P2 or step 65 P4 first)"

    local target_pdb
    target_pdb=$(read_state "PDB_TARGET_NAME")
    if [[ -z "${target_pdb}" ]]; then
        target_pdb="PDBCLONE_P2"
        lib_warn "PDB_TARGET_NAME not in state, defaulting to ${target_pdb}"
    fi
    lib_info "Target PDB: ${target_pdb} in ${DEV_SERVICE}"

    # Full key chain query in target PDB
    step_header "v\$encryption_keys in target ${target_pdb} (dev)"
    sqlplus_dev "
SET HEADING ON FEEDBACK ON PAGESIZE 100 LINESIZE 200
ALTER SESSION SET CONTAINER=${target_pdb};
SELECT key_id, key_use, keystore_type, origin, backed_up, creation_time
FROM v\$encryption_keys
WHERE con_id = sys_context('userenv','con_id')
ORDER BY creation_time;
EXIT
"

    # Full key chain query in source PDBCLONE (prod)
    step_header "v\$encryption_keys in source ${CLONE_SRC_PDB} (prod)"
    sqlplus_prod "
SET HEADING ON FEEDBACK ON PAGESIZE 100 LINESIZE 200
ALTER SESSION SET CONTAINER=${CLONE_SRC_PDB};
SELECT key_id, key_use, keystore_type, origin, backed_up, creation_time
FROM v\$encryption_keys
WHERE con_id = sys_context('userenv','con_id')
ORDER BY creation_time;
EXIT
"

    # ORIGIN of the key the data actually hangs on. Taking the first row of
    # v$encryption_keys answers a different question - a PDB can hold several
    # keys, and only the one referenced by the tablespace matters here.
    local origin_target ts_mek
    origin_target=""; ts_mek=""
    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        ts_mek=$(get_masterkeyid "${DEV_SERVICE}" "${target_pdb}" "${CLONE_TS_ENC}")
        lib_info "tablespace ${CLONE_TS_ENC} in ${target_pdb} depends on MEK ${ts_mek}"
        origin_target=$(get_origin_for_mek "${DEV_SERVICE}" "${target_pdb}" "${ts_mek}") || true
    else
        origin_target="IMPORTED"
        ts_mek="DRY-RUN"
    fi

    # Read ORIGIN values from state (stored by P2 / P4)
    local origin_p2 origin_p4
    origin_p2=$(read_state "PDB_P2_ORIGIN")
    origin_p4=$(read_state "PDB_P4_ORIGIN")

    write_state "PDB_P7_ORIGIN_TARGET" "${origin_target}"

    # Print comparison table
    echo ""
    echo "========================================================================"
    echo "== ORIGIN Comparison Table"
    echo "========================================================================"
    printf '  %-42s  %s\n' "Context" "ORIGIN"
    printf '  %-42s  %s\n' "------------------------------------------" "--------"
    printf '  %-42s  %s\n' "Source PDBCLONE in prod (native creation)" "LOCAL"
    printf '  %-42s  %s\n' "PDB archive import P2 (from state)" "${origin_p2:-n/a (P2 not run)}"
    printf '  %-42s  %s\n' "Remote clone + key import P4 (from state)" "${origin_p4:-n/a (P4 not run)}"
    printf '  %-42s  %s\n' "Current target ${target_pdb} (measured now)" "${origin_target:-unknown}"
    printf '  %-42s  %s\n' "RMAN Variant A (copied keystore, reference)" "LOCAL (documented)"
    echo ""
    echo "Key distinction: IMPORTED traces the key provenance; LOCAL does not."
    echo "A copied keystore (Variant A) leaves no audit trail in v\$encryption_keys."

    # This step observes; the ORIGIN value is the result, not a pass criterion.
    # It fails only when the measurement itself did not produce one.
    local verdict msg
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        verdict="PASS"; msg="DRY-RUN"
    elif [[ -z "${origin_target}" || "${origin_target}" == "NOT-IN-KEYSTORE" ]]; then
        verdict="FAIL"
        msg="P7: the key ${ts_mek} the tablespace depends on is not in the target keystore - no provenance statement possible"
    elif [[ "${origin_target}" == "LOCAL" ]]; then
        verdict="PASS"
        msg="P7: the key ${ts_mek} was transported out of production by EXPORT/IMPORT KEYS, yet the target reports ORIGIN=LOCAL. Nothing in v\$encryption_keys distinguishes a transported production key from one generated on the spot - the provenance question cannot be answered from the database"
    elif [[ "${origin_target}" == "IMPORTED" ]]; then
        verdict="PASS"
        msg="P7: ORIGIN=IMPORTED for key ${ts_mek} - the formal key import does leave a traceable marker in this configuration"
    else
        verdict="PASS"
        msg="P7: ORIGIN=${origin_target} for key ${ts_mek} - recorded, see the comparison above"
    fi

    print_verdict "${verdict}" "${msg}"
    lib_info "Done."
}

main "$@"
# --- EOF ----------------------------------------------------------------------
