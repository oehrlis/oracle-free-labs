#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: 69_pdb_p8_keyver.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026-09-04
# Version....: 0.1.0
# Purpose....: PDB P8 - KEY_VERSION after plug-in to a foreign CDB.
#              Oracle documentation states that KEY_VERSION resets to 0 after a
#              PDB is plugged into a different CDB. This step verifies that claim
#              by comparing KEY_VERSION of CLONE_ENC in the source PDBCLONE
#              (prod) against the target PDB in dev.
#              The result is informational: both the observed value and any
#              deviation from the documented expectation are recorded.
# Notes......: Prerequisite: step 63 (P2) or step 65 (P4).
#              KEY_VERSION may change further if step 66 (P5 MEK rotation) or
#              step 67 (P6 ONLINE REKEY) ran before this step.
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
CLONE_TS_ENC="CLONE_ENC"
CLONE_TS_PLAIN="CLONE_PLAIN"

# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

# ------------------------------------------------------------------------------
# usage
# ------------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

  PDB P8: KEY_VERSION after plug-in to foreign CDB.
  Compares KEY_VERSION of ${CLONE_TS_ENC} between source PDBCLONE (prod) and
  the target PDB in dev. Oracle doc: KEY_VERSION resets to 0 after plug-in.
  Informational step - records measured values regardless of the outcome.

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
    step_header "Step 69: PDB P8 - KEY_VERSION after plug-in to foreign CDB"

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

    # Full tablespace encryption info from source
    step_header "v\$encrypted_tablespaces in source ${CLONE_SRC_PDB} (prod)"
    sqlplus_prod "
SET HEADING ON FEEDBACK ON PAGESIZE 100 LINESIZE 200
ALTER SESSION SET CONTAINER=${CLONE_SRC_PDB};
SELECT t.name, et.encryptionalg, et.key_version,
       RAWTOHEX(et.masterkeyid) AS masterkeyid
FROM v\$encrypted_tablespaces et, v\$tablespace t
WHERE et.ts# = t.ts# AND et.con_id = t.con_id
AND t.name IN ('${CLONE_TS_ENC}','${CLONE_TS_PLAIN}')
ORDER BY t.name;
EXIT
"

    # Full tablespace encryption info from target
    step_header "v\$encrypted_tablespaces in target ${target_pdb} (dev)"
    sqlplus_dev "
SET HEADING ON FEEDBACK ON PAGESIZE 100 LINESIZE 200
ALTER SESSION SET CONTAINER=${target_pdb};
SELECT t.name, et.encryptionalg, et.key_version,
       RAWTOHEX(et.masterkeyid) AS masterkeyid
FROM v\$encrypted_tablespaces et, v\$tablespace t
WHERE et.ts# = t.ts# AND et.con_id = t.con_id
AND t.name IN ('${CLONE_TS_ENC}','${CLONE_TS_PLAIN}')
ORDER BY t.name;
EXIT
"

    # Read KEY_VERSION from source
    local kv_source
    kv_source=""
    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        kv_source=$(printf '%s\n' "
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 80 TRIMSPOOL ON
ALTER SESSION SET CONTAINER=${CLONE_SRC_PDB};
SELECT key_version FROM v\$encrypted_tablespaces WHERE ts# = (SELECT ts# FROM v\$tablespace WHERE name='${CLONE_TS_ENC}' AND con_id=sys_context('userenv','con_id'));
EXIT" | docker exec -i "${PROD_SERVICE}" sqlplus -S / as sysdba 2>/dev/null \
            | awk 'NF && /^[0-9]+$/ { print $1; exit }')
    else
        kv_source="1"
    fi

    # Read KEY_VERSION from target
    local kv_target
    kv_target=""
    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        kv_target=$(printf '%s\n' "
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 80 TRIMSPOOL ON
ALTER SESSION SET CONTAINER=${target_pdb};
SELECT key_version FROM v\$encrypted_tablespaces WHERE ts# = (SELECT ts# FROM v\$tablespace WHERE name='${CLONE_TS_ENC}' AND con_id=sys_context('userenv','con_id'));
EXIT" | docker exec -i "${DEV_SERVICE}" sqlplus -S / as sysdba 2>/dev/null \
            | awk 'NF && /^[0-9]+$/ { print $1; exit }')
    else
        kv_target="0"
    fi

    # Read stored KEY_VERSION from state if P2 or P4 recorded it
    local kv_p2 kv_p4
    kv_p2=$(read_state "PDB_P2_KEY_VERSION")
    kv_p4=$(read_state "PDB_P4_KEY_VERSION")

    write_state "PDB_P8_KV_SOURCE" "${kv_source}"
    write_state "PDB_P8_KV_TARGET" "${kv_target}"

    # Print comparison
    echo ""
    echo "========================================================================"
    echo "== KEY_VERSION Comparison"
    echo "========================================================================"
    printf '  %-44s  %s\n' "Context" "KEY_VERSION"
    printf '  %-44s  %s\n' "--------------------------------------------" "-----------"
    printf '  %-44s  %s\n' "Source PDBCLONE/${CLONE_TS_ENC} (prod)" "${kv_source:-n/a}"
    printf '  %-44s  %s\n' "Target ${target_pdb}/${CLONE_TS_ENC} (dev, now)" "${kv_target:-n/a}"
    printf '  %-44s  %s\n' "Target at P2 plug-in (from state)" "${kv_p2:-n/a (P2 not run)}"
    printf '  %-44s  %s\n' "Target at P4 plug-in (from state)" "${kv_p4:-n/a (P4 not run)}"
    echo ""
    echo "Oracle documentation: KEY_VERSION may reset to 0 after plug-in to a"
    echo "foreign CDB. Subsequent MEK rotation (P5) or ONLINE REKEY (P6)"
    echo "will increment KEY_VERSION further."

    local verdict msg
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        verdict="PASS"; msg="DRY-RUN"
    elif [[ "${kv_source}" == "${kv_target}" ]]; then
        verdict="PASS"
        msg="P8 informational: KEY_VERSION unchanged (${kv_source}) - doc reset to 0 not observed here"
    elif [[ "${kv_target}" == "0" ]]; then
        verdict="PASS"
        msg="P8 informational: KEY_VERSION reset to 0 in target after foreign plug-in (matches doc)"
    else
        verdict="PASS"
        msg="P8 informational: source KEY_VERSION=${kv_source}, target=${kv_target} - recorded"
    fi

    print_verdict "${verdict}" "${msg}"
    lib_info "Done."
}

main "$@"
# --- EOF ----------------------------------------------------------------------
