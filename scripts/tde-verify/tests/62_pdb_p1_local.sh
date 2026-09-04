#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: 62_pdb_p1_local.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026-09-04
# Version....: 0.1.0
# Purpose....: PDB P1 - Local clone of PDBCLONE within the same CDB (odbencprod).
#              CREATE PLUGGABLE DATABASE PDBCLONE_P1 FROM PDBCLONE.
#              Reference case: same keystore, no key transport needed.
#              Expected: TEK identical to source, ORIGIN=LOCAL (same CDB).
#              Measures the key chain and ciphertext before/after to confirm
#              that a local clone does not alter TEK material.
# Notes......: Prerequisite: step 61 (PDB testbed) must have completed.
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
CLONE_P1_PDB="PDBCLONE_P1"
LABEL="pdb_p1_local"

# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

# ------------------------------------------------------------------------------
# usage
# ------------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

  PDB P1: local clone of PDBCLONE within the same CDB (odbencprod).
  Reference case: same keystore, no key transport needed.
  Expected result: TEK identical to source (ORIGIN=LOCAL, same CDB).

  Prerequisite: step 61 (PDB testbed) must have completed.

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
    step_header "Step 62: PDB P1 - local clone in same CDB"

    require_command docker
    require_container "${PROD_SERVICE}"
    require_healthy   "${PROD_SERVICE}"
    require_state "PDBCLONE_READY" "PDB testbed (run step 61 first)"

    # Clone PDBCLONE_P1 locally (idempotent: drop first)
    # Without OMF, CREATE PLUGGABLE DATABASE fails with ORA-65016.
    ensure_omf "${PROD_SERVICE}"

    # Measured: even a local clone inside the same CDB needs the keystore
    # password once the source has encrypted tablespaces - without the KEYSTORE
    # clause the CREATE fails with ORA-46697, "Keystore password required".
    # An auto-login keystore is not enough for this operation. Passed via stdin
    # so the password never appears in the host process list.
    step_header "Clone ${CLONE_SRC_PDB} -> ${CLONE_P1_PDB} (local)"
    # shellcheck disable=SC1078,SC1079
    lib_run in_prod_stdin '
KSPWD=$(cat '"${WALLET_DIR_CONTAINER}"'/wallet_pwd.txt)
sqlplus -S / as sysdba <<SQL 2>&1 | grep -viE "identified by"; _rc=${PIPESTATUS[0]}; [ "${_rc}" -eq 0 ] || { echo "ERROR: sqlplus exited ${_rc}" >&2; exit "${_rc}"; }
WHENEVER SQLERROR CONTINUE
ALTER PLUGGABLE DATABASE '"${CLONE_P1_PDB}"' CLOSE IMMEDIATE;
DROP PLUGGABLE DATABASE '"${CLONE_P1_PDB}"' INCLUDING DATAFILES;
WHENEVER SQLERROR EXIT SQL.SQLCODE
CREATE PLUGGABLE DATABASE '"${CLONE_P1_PDB}"' FROM '"${CLONE_SRC_PDB}"'
  KEYSTORE IDENTIFIED BY "${KSPWD}";
ALTER PLUGGABLE DATABASE '"${CLONE_P1_PDB}"' OPEN READ WRITE;
SELECT name, open_mode FROM v\$pdbs WHERE name='"'"''"${CLONE_P1_PDB}"''"'"';
EXIT
SQL
'

    # Query ORIGIN from the clone
    step_header "Query key chain in ${CLONE_P1_PDB}"
    sqlplus_prod "
SET HEADING ON FEEDBACK ON PAGESIZE 100 LINESIZE 200
ALTER SESSION SET CONTAINER=${CLONE_P1_PDB};
SELECT key_id, key_use, keystore_type, origin, backed_up
FROM v\$encryption_keys
WHERE con_id = sys_context('userenv','con_id')
ORDER BY creation_time;
SELECT RAWTOHEX(masterkeyid) AS masterkeyid,
       RAWTOHEX(encryptedkey) AS encryptedkey,
       key_version, encryptionalg
FROM v\$encrypted_tablespaces
WHERE ts# = (SELECT ts# FROM v\$tablespace WHERE name='${CLONE_TS_ENC}' AND con_id=sys_context('userenv','con_id'));
EXIT
"

    # Collect evidence
    step_header "Collect evidence set '${LABEL}'"
    collect_evidence "${PROD_SERVICE}" "${CLONE_P1_PDB}" "${LABEL}" "${CLONE_TS_ENC}"

    # Compare against pdb_baseline
    step_header "Compare '${LABEL}' vs 'pdb_baseline' (expect IDENTICAL)"
    compare_evidence "pdb_baseline" "${LABEL}"

    # Read key values
    local mkid_p1 tek_p1 mkid_src tek_src
    mkid_p1=""
    tek_p1=""
    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        mkid_p1=$(get_masterkeyid "${PROD_SERVICE}" "${CLONE_P1_PDB}" "${CLONE_TS_ENC}")
        tek_p1=$(get_encryptedkey  "${PROD_SERVICE}" "${CLONE_P1_PDB}" "${CLONE_TS_ENC}")
    else
        mkid_p1="DRY-RUN-MKID"
        tek_p1="DRY-RUN-TEK"
    fi
    mkid_src=$(read_state "PDBCLONE_MKID_ENC")
    tek_src=$(read_state  "PDBCLONE_TEK_ENC")

    write_state "PDB_P1_TEK"  "${tek_p1}"
    write_state "PDB_P1_MKID" "${mkid_p1}"

    # Measured, against the original expectation: a local clone does NOT
    # preserve the tablespace key. The MASTERKEYID is identical in source and
    # clone - same CDB, same keystore - so a differing wrapped key cannot come
    # from a re-wrap, which under an unchanged MEK would reproduce the same
    # value. It is new key material, and the ciphertext confirms it
    # independently. KEY_VERSION is 0 in both and says nothing here.
    local canary_cmp canary_rc
    canary_cmp=""
    canary_rc=0
    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        canary_cmp=$(compare_canary_blocks "pdb_baseline" "${LABEL}" \
                       "${PROD_SERVICE}" "${CLONE_P1_PDB}" "CANARY_CLONEENC") || canary_rc=$?
        echo "canary blocks:   ${canary_cmp} (expect all differing - clone re-encrypts)"
    fi

    local verdict msg
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        verdict="PASS"; msg="DRY-RUN"
    elif [[ ${canary_rc} -eq 2 ]]; then
        verdict="FAIL"
        msg="P1: canary blocks could not be compared - no verdict possible"
    elif [[ "${tek_p1}" != "${tek_src}" && ${canary_rc} -eq 1 ]]; then
        verdict="PASS"
        if [[ "${mkid_p1}" == "${mkid_src}" ]]; then
            msg="P1 local clone: NEW tablespace key material. The MASTERKEYID is unchanged, so the differing wrapped key cannot be a re-wrap, and the ciphertext changed with it (${canary_cmp}). A PDB clone re-encrypts - unlike every RMAN path measured"
        else
            msg="P1 local clone: TEK and MASTERKEYID both differ, ciphertext changed (${canary_cmp}) - new key material, but the MEK changed too, so the re-wrap argument does not apply"
        fi
    elif [[ "${tek_p1}" == "${tek_src}" && ${canary_rc} -eq 0 ]]; then
        verdict="PASS"
        msg="P1 local clone: TEK and ciphertext identical to source (${canary_cmp}) - the clone shares the key material"
    else
        verdict="FAIL"
        msg="P1 local clone: contradictory - wrapped key $( [[ "${tek_p1}" == "${tek_src}" ]] && echo identical || echo different ) but ciphertext ${canary_cmp}"
    fi

    print_key_summary "pdb_p1_local (${CLONE_P1_PDB})" "${mkid_p1}" "${tek_p1}"
    print_key_summary "pdb_baseline  (${CLONE_SRC_PDB})" "${mkid_src}" "${tek_src}"
    echo ""
    echo "Wrapped TEK:    $( [[ "${tek_p1}" == "${tek_src}" ]] && echo "IDENTICAL" || echo "DIFFERENT")"
    echo "MASTERKEYID:    $( [[ "${mkid_p1}" == "${mkid_src}" ]] && echo "IDENTICAL - a re-wrap would have reproduced the same wrapped key" || echo "DIFFERENT")"

    print_verdict "${verdict}" "${msg}"
    lib_info "Done."
}

main "$@"
# --- EOF ----------------------------------------------------------------------
