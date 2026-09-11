#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: 71_pdb_p4b_nokeyimport.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026-09-10
# Version....: 0.1.0
# Purpose....: P4b - remote PDB clone WITHOUT importing the source master key.
#              The decisive experiment for the whole recommendation: does the
#              target ever need the source MEK, or does the clone leave it with
#              a self-contained key of its own?
#              Step 65 (P4) clones AND THEN exports/imports the source keys, so
#              it cannot answer this. This step removes the import and reads the
#              data.
#              Phases:
#              1. Preflight and state gate (needs step 61)
#              2. PROVE the starting condition: the source MEK is absent from
#                 the target keystore. Without this the run proves nothing.
#              3. Read the c##clone credential into memory
#              4. Create the DB link, drop a leftover target PDB
#              5. CREATE PLUGGABLE DATABASE ... FROM ...@link KEYSTORE IDENTIFIED BY
#              6. NO key export, NO key import - that is the point
#              7. Open the target and read the marker table
#              8. Verdict, key chain, state
# Notes......: BOTH outcomes are valid results, not pass/fail of the harness:
#              - marker readable          -> the target never needs the source
#                                           MEK; a per-stage keystore topology
#                                           is workable with this procedure
#              - ORA-28374 or ORA-28365   -> the clone depends on the source MEK
#                                           longer than assumed; the
#                                           recommendation needs qualification
#              The script therefore reports which one happened and does not
#              treat the second as an error.
#              The lab has no Oracle Key Vault. This measures the mechanism
#              against software keystores; whether two independent Key Vault
#              clusters behave the same is not decidable here.
# Reference..: https://github.com/oehrlis/oracle-free-labs
# License....: Apache License Version 2.0, January 2004 as shown
#              at http://www.apache.org/licenses/
# ------------------------------------------------------------------------------
# CHANGE LOG:
# 2026-09-10  oes  Initial release                                        0.1.0
# 2026-09-10  oes  Verdict rested on readability alone and reported a false  0.2.0
#                  INDEPENDENT. Now also checks the keystore contents and
#                  the key reference - the clone transports the source MEK.
# ------------------------------------------------------------------------------

set -euo pipefail
SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="0.2.0"
VERBOSE=${VERBOSE:-"FALSE"}
DRY_RUN=${DRY_RUN:-"FALSE"}
FORCE_YES=${FORCE_YES:-"FALSE"}

CLONE_SRC_PDB="PDBCLONE"
CLONE_TS_ENC="CLONE_ENC"
CLONE_USER="c##clone"
TARGET_PDB="PDBCLONE_P4B"
DB_LINK="prod_cdb_link_p4b"
PROD_HOST="odbencprod"
PROD_PORT="1521"
PROD_SERVICE_NAME="FREE.oradba.ch"
LABEL="pdb_p4b_nokeyimport"

# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

CLONE_PWD=""

usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

  P4b: remote clone of ${CLONE_SRC_PDB} via DB link, WITHOUT importing the
  source master key, then read the marker table.

  Answers: does the clone target ever need the source MEK?
  Both outcomes are results. Readable means no; ORA-28374 means yes.

  Prerequisite: step 61 (PDB testbed).

Options:
  -h, --help      Show this help and exit
  -v, --verbose   Enable verbose output
  -d, --dry-run   Show what would be done; change nothing
  -y, --yes       Do not prompt

EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)    usage; exit 0 ;;
        -v|--verbose) VERBOSE="TRUE"; shift ;;
        -d|--dry-run) DRY_RUN="TRUE"; shift ;;
        -y|--yes)     FORCE_YES="TRUE"; shift ;;
        *) lib_err "Unknown option: $1"; usage; exit 1 ;;
    esac
done

cleanup_cred() { CLONE_PWD=""; }

main() {
    lib_info "Starting ${SCRIPT_NAME} ${VERSION}"
    step_header "Step 71: P4b - remote clone without key import"

    require_command docker
    require_container "${PROD_SERVICE}"
    require_healthy   "${PROD_SERVICE}"
    ensure_independent_dev_cdb
    require_container "${DEV_SERVICE}"
    require_healthy   "${DEV_SERVICE}"
    require_state "PDBCLONE_READY" "PDB testbed (run step 61 first)"
    ensure_omf "${PROD_SERVICE}"
    ensure_omf "${DEV_SERVICE}"
    trap cleanup_cred EXIT

    # ------------------------------------------------------------------
    # Phase 2 - the starting condition. If the source MEK is already in the
    # target keystore the experiment is void, so this is a hard gate.
    # ------------------------------------------------------------------
    step_header "Phase 2: prove the source MEK is ABSENT from the target keystore"
    local src_mek="DRY-RUN"
    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        src_mek=$(get_masterkeyid "${PROD_SERVICE}" "${CLONE_SRC_PDB}" "${CLONE_TS_ENC}")
        if [[ -z "${src_mek}" ]]; then
            lib_err "could not read the source MASTERKEYID - is step 61 complete?"
            exit 1
        fi
        lib_info "source tablespace depends on MEK ${src_mek}"
        # get_key_id_for_mek prints the KEY_ID when the MEK is in that
        # container's keystore and nothing when it is not. Empty is the
        # condition this experiment requires.
        local present
        present=$(get_key_id_for_mek "${DEV_SERVICE}" "${src_mek}" 2>/dev/null || true)
        if [[ -n "${present}" ]]; then
            lib_err "the source MEK ${src_mek} is ALREADY present in ${DEV_SERVICE} (KEY_ID ${present})"
            lib_err "the experiment would prove nothing - reset the target keystore first"
            exit 1
        fi
        lib_info "confirmed: source MEK not in ${DEV_SERVICE} keystore"
    else
        lib_info "DRY-RUN: would verify the source MEK is absent from ${DEV_SERVICE}"
    fi

    # ------------------------------------------------------------------
    # Phase 3 - credential in memory only, never argv, never a file
    # ------------------------------------------------------------------
    step_header "Phase 3: read the ${CLONE_USER} credential into memory"
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        lib_info "DRY-RUN: would read ORACLE_PWD from ${PROD_SERVICE}"
    else
        CLONE_PWD=$(docker exec "${PROD_SERVICE}" bash -c 'printf %s "${ORACLE_PWD}"')
        [[ -n "${CLONE_PWD}" ]] || { lib_err "could not read ORACLE_PWD"; exit 1; }
        lib_info "credential in memory, not written to disk"
    fi

    # ------------------------------------------------------------------
    # Phase 4 - DB link and a clean target
    # ------------------------------------------------------------------
    step_header "Phase 4: DB link ${DB_LINK} and drop a leftover ${TARGET_PDB}"
    # shellcheck disable=SC1078,SC1079
    lib_run in_dev_stdin '
sqlplus -S / as sysdba <<SQL 2>&1 | grep -viE "identified by"; _rc=${PIPESTATUS[0]}; [ "${_rc}" -eq 0 ] || { echo "ERROR: sqlplus exited ${_rc}" >&2; exit "${_rc}"; }
WHENEVER SQLERROR CONTINUE
ALTER PLUGGABLE DATABASE '"${TARGET_PDB}"' CLOSE IMMEDIATE;
DROP PLUGGABLE DATABASE '"${TARGET_PDB}"' INCLUDING DATAFILES;
DROP DATABASE LINK '"${DB_LINK}"';
WHENEVER SQLERROR EXIT SQL.SQLCODE
CREATE DATABASE LINK '"${DB_LINK}"'
  CONNECT TO '"${CLONE_USER}"' IDENTIFIED BY "'"${CLONE_PWD}"'"
  USING '"'"'(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST='"${PROD_HOST}"')(PORT='"${PROD_PORT}"'))(CONNECT_DATA=(SERVICE_NAME='"${PROD_SERVICE_NAME}"')))'"'"';
SELECT '"'"'db link ok'"'"' AS link_status FROM dual@'"${DB_LINK}"';
EXIT
SQL
'

    # ------------------------------------------------------------------
    # Phase 5 - the clone. KEYSTORE IDENTIFIED BY is required as soon as the
    # source carries encrypted tablespaces (ORA-46697 without it, measured in
    # step 62). Note this opens the TARGET keystore - it does not import a key.
    # ------------------------------------------------------------------
    step_header "Phase 5: CREATE ${TARGET_PDB} FROM ${CLONE_SRC_PDB}@${DB_LINK}"
    # shellcheck disable=SC1078,SC1079
    lib_run in_dev_stdin '
KSPWD=$(cat '"${WALLET_DIR_CONTAINER}"'/wallet_pwd.txt)
sqlplus -S / as sysdba <<SQL 2>&1 | grep -viE "identified by"; _rc=${PIPESTATUS[0]}; [ "${_rc}" -eq 0 ] || { echo "ERROR: sqlplus exited ${_rc}" >&2; exit "${_rc}"; }
WHENEVER SQLERROR EXIT SQL.SQLCODE
CREATE PLUGGABLE DATABASE '"${TARGET_PDB}"'
  FROM '"${CLONE_SRC_PDB}"'@'"${DB_LINK}"'
  KEYSTORE IDENTIFIED BY "${KSPWD}";
SELECT name, open_mode FROM v\$pdbs WHERE name='"'"''"${TARGET_PDB}"''"'"';
EXIT
SQL
'

    # ------------------------------------------------------------------
    # Phase 6 - deliberately absent: no EXPORT KEYS, no IMPORT KEYS.
    # ------------------------------------------------------------------
    step_header "Phase 6: NO key export and NO key import - this is the experiment"
    lib_info "skipping the export/import that step 65 performs"

    # ------------------------------------------------------------------
    # Phase 7 - open and read. The read is the measurement.
    # ------------------------------------------------------------------
    step_header "Phase 7: open ${TARGET_PDB} and read the marker table"
    local read_out="" read_rc=0
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        lib_info "DRY-RUN: would open ${TARGET_PDB} and select from ${CANARY_OWNER}.CANARY_CLONEENC"
        read_out="DRY-RUN"
    else
        read_out=$(printf '%s\n' "
SET LINESIZE 200 PAGESIZE 100
WHENEVER SQLERROR CONTINUE
ALTER PLUGGABLE DATABASE ${TARGET_PDB} OPEN;
ALTER SESSION SET CONTAINER=${TARGET_PDB};
SELECT COUNT(*) AS marker_rows FROM ${CANARY_OWNER}.CANARY_CLONEENC;
SELECT COUNT(*) AS plain_rows  FROM ${CANARY_OWNER}.CANARY_CLONEPLAIN;
EXIT" | docker exec -i "${DEV_SERVICE}" sqlplus -S / as sysdba 2>&1) || read_rc=$?
        printf '%s\n' "${read_out}"
        lib_info "sqlplus exit code of the read: ${read_rc} (non-zero is expected in the DEPENDENT case)"
    fi

    # ------------------------------------------------------------------
    # Phase 8 - verdict. Both outcomes are results.
    # ------------------------------------------------------------------
    # A successful read does NOT mean the target is key-independent. That
    # inference was wrong in v0.1.0 and produced a false INDEPENDENT verdict on
    # 2026-09-10: the clone transports the source MEK into the target keystore
    # by itself, so the data reads while the dependency is fully intact.
    # The verdict rests on three observations, not one:
    #   a) is the source MEK in the target keystore AFTER the clone?
    #   b) does the target tablespace reference the source MEK or its own?
    #   c) does the marker table read?
    step_header "Phase 8: verdict - keystore contents, key reference, readability"
    local mek_after="" ts_mkid="" readable="no" verdict
    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        mek_after=$(get_key_id_for_mek "${DEV_SERVICE}" "${src_mek}" 2>/dev/null || true)
        ts_mkid=$(get_masterkeyid "${DEV_SERVICE}" "${TARGET_PDB}" "${CLONE_TS_ENC}" 2>/dev/null || true)
        printf '%s' "${read_out}" | grep -qE 'ORA-28374|ORA-28365|not found in wallet|not open' || readable="yes"
        if [[ -n "${mek_after}" ]]; then
            lib_info "source MEK ${src_mek} IS in the target keystore after the clone"
        else
            lib_info "source MEK ${src_mek} is absent from the target keystore"
        fi
        lib_info "target tablespace references MASTERKEYID: ${ts_mkid:-unknown}"
        lib_info "marker table readable: ${readable}"
    fi

    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        verdict="DRY-RUN - no measurement"
    elif [[ "${readable}" == "no" ]]; then
        verdict="DEPENDENT - marker unreadable: the clone needs a source key it does not have"
        lib_warn "${verdict}"
    elif [[ -n "${mek_after}" ]]; then
        verdict="KEY TRANSPORTED - the clone carried the source MEK into the target keystore by itself; the target tablespace is wrapped by ${ts_mkid}. Data reads, dependency intact"
        lib_warn "${verdict}"
        lib_warn "the clone alone does NOT separate. It needs SET KEY in the target and"
        lib_warn "removal of the source MEK afterwards - three steps, not one command."
        lib_warn "Read-only tablespaces must be opened before SET KEY or they keep the old binding (P5)."
    elif [[ "${ts_mkid}" == "${src_mek}" ]]; then
        verdict="UNCLEAR - tablespace references the source MEK but that MEK is not in the keystore; inspect the output"
        lib_warn "${verdict}"
    else
        verdict="INDEPENDENT - marker reads, source MEK absent, tablespace wrapped by ${ts_mkid}"
        lib_info "${verdict}"
    fi

    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        step_header "Key chain in ${TARGET_PDB} and keystore contents"
        sqlplus_dev "
SET LINESIZE 220 PAGESIZE 100
COLUMN key_id FORMAT A56
SELECT con_id, key_id, origin FROM v\$encryption_keys ORDER BY con_id;
ALTER SESSION SET CONTAINER=${TARGET_PDB};
SELECT RAWTOHEX(masterkeyid) AS masterkeyid, RAWTOHEX(encryptedkey) AS wrapped_tek, key_version
  FROM v\$encrypted_tablespaces
 WHERE ts# = (SELECT ts# FROM v\$tablespace WHERE name='${CLONE_TS_ENC}' AND con_id=sys_context('userenv','con_id'));
EXIT
" || true
        collect_evidence "${DEV_SERVICE}" "${TARGET_PDB}" "${LABEL}" "${CLONE_TS_ENC}" || true
        write_state "PDB_P4B_VERDICT" "${verdict}"
        write_state "PDB_P4B_SRC_MEK"   "${src_mek}"
        write_state "PDB_P4B_MEK_AFTER" "${mek_after:-absent}"
        write_state "PDB_P4B_TS_MKID"   "${ts_mkid}"
    fi

    echo ""
    echo "========================================================================"
    echo "VERDICT: ${verdict}"
    echo "========================================================================"
    lib_info "${SCRIPT_NAME} completed"
}

main "$@"
