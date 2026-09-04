#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: 63_pdb_p2_archive.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026-09-04
# Version....: 0.1.0
# Purpose....: PDB P2 - Unplug PDBCLONE with key export (ENCRYPT USING),
#              plug into odbencdev with key import (DECRYPT USING).
#              The archive secret is a static lab constant; it is not a
#              production secret and is acceptable in script output.
#              Steps:
#              1. Close PDBCLONE in prod, UNPLUG INTO xchange/pdbclone_p2.pdb
#                 with ENCRYPT USING lab secret
#              2. DROP PDBCLONE INCLUDING DATAFILES
#              3. Re-plug PDBCLONE back into prod (COPY, DECRYPT USING) so
#                 PDBCLONE remains available for step 65 (P4 remote clone)
#              4. In dev: drop PDBCLONE_P2 if exists, CREATE PLUGGABLE
#                 DATABASE PDBCLONE_P2 USING archive DECRYPT USING
#              5. Collect evidence, compare vs pdb_baseline
#              6. Check ORIGIN (expect IMPORTED) and KEY_VERSION (may reset to 0)
# Notes......: Prerequisite: step 61 (PDB testbed).
#              This step modifies and replaces PDBCLONE in prod. Run only after
#              step 62 (P1) if you want P1 measurements, because P2 unplugs the
#              source. After step 63, PDBCLONE is re-created from the archive.
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
CLONE_P2_PDB="PDBCLONE_P2"
LABEL="pdb_p2_archive"
# Static lab constant - not a production secret
# Transport secret, generated per run. A fixed value in the repository would
# be a committed secret even in a lab, and it adds nothing: the secret only
# has to match between the export and the import within this one run.
# head -c would exit after 24 bytes, tr would get SIGPIPE, and with
# pipefail set -e aborts the script before it prints a single line.
# openssl produces a finite stream and cut reads it to the end.
P2_SECRET="$(openssl rand -base64 48 | LC_ALL=C tr -dc "A-Za-z0-9" | cut -c1-24)"

# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
ARCHIVE_PATH="${XCHANGE_CONTAINER}/pdbclone_p2.pdb"

# ------------------------------------------------------------------------------
# usage
# ------------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

  PDB P2: unplug PDBCLONE with ENCRYPT USING, plug into odbencdev.
  PDBCLONE is re-created in prod after unplugging so P4 (remote clone) can
  still use it.
  Expected: TEK identical to source, ORIGIN=IMPORTED (formal key transport).

  Prerequisite: step 61 (PDB testbed) must have completed.
  Note: this step modifies PDBCLONE in prod. Run step 62 (P1) first if needed.

Options:
  -h, --help      Show this help and exit
  -v, --verbose   Enable verbose output
  -d, --dry-run   Show what would be done; change nothing
  -y, --yes       Skip confirmation prompt

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
    step_header "Step 63: PDB P2 - unplug with key export, plug into dev"

    require_command docker
    require_container "${PROD_SERVICE}"
    require_container "${DEV_SERVICE}"
    require_healthy   "${PROD_SERVICE}"
    # Before the dev health requirement: the RMAN variants leave dev as a
    # restore of prod - same DBID - and with a CDB temp file that no longer
    # verifies, which is exactly what makes the health check fail. P2/P7/P8
    # claim a foreign CDB, so rebuilding is part of the method.
    ensure_independent_dev_cdb
    require_healthy   "${DEV_SERVICE}"
    require_state "PDBCLONE_READY" "PDB testbed (run step 61 first)"

    if [[ "${FORCE_YES}" != "TRUE" && "${DRY_RUN}" != "TRUE" ]]; then
        lib_warn "This step unplugs and re-plugs ${CLONE_SRC_PDB} in prod."
        read -rp "Continue? [y/N] " _reply
        [[ "${_reply}" == [yY] ]] || { lib_warn "aborted by user"; exit 1; }
    fi

    # The source PDB must still exist. Phase 1 unplugs and drops it, and the
    # transport secret is generated per run - so a retry of this step alone
    # would find neither the PDB nor a matching archive. Fail with the fix
    # instead of an ORA-65011 that looks like something else.
    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        local pdb_exists
        pdb_exists=$(printf '%s\n' "
SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT COUNT(*) FROM v\$pdbs WHERE name = '${CLONE_SRC_PDB}';
EXIT" | docker exec -i "${PROD_SERVICE}" sqlplus -S / as sysdba 2>/dev/null \
            | awk 'NF && $1 ~ /^[0-9]+$/ { print $1; exit }')
        if [[ "${pdb_exists}" != "1" ]]; then
            lib_err "${CLONE_SRC_PDB} does not exist in ${PROD_SERVICE} - phase 1 dropped it in an earlier attempt"
            lib_err "re-run step 61 first: run_all.sh --from 61 --yes"
            exit 1
        fi
    fi

    # UNPLUG refuses to overwrite an existing archive (ORA-65288), so a retried
    # step would fail on the leftover from the previous attempt.
    step_header "Remove a leftover PDB archive if present"
    lib_run in_prod "if [ -f ${ARCHIVE_PATH} ]; then rm -f ${ARCHIVE_PATH} && echo 'removed leftover archive ${ARCHIVE_PATH}'; else echo 'no leftover archive at ${ARCHIVE_PATH}'; fi"

    # The transport secret takes double quotes. Measured with a syntax probe
    # against a non-existent PDB: single quotes give ORA-00922, double quotes
    # get through to ORA-65011. Same for WITH SECRET on EXPORT/IMPORT KEYS,
    # where single quotes are rejected with ORA-46609.
    # Phase 1: Close and UNPLUG PDBCLONE with ENCRYPT USING
    # PDBs are created in both containers here; without OMF every
    # CREATE PLUGGABLE DATABASE fails with ORA-65016.
    ensure_omf "${PROD_SERVICE}"
    ensure_omf "${DEV_SERVICE}"

    step_header "Phase 1: UNPLUG ${CLONE_SRC_PDB} with key encryption"
    sqlplus_prod "
WHENEVER SQLERROR CONTINUE
-- Tolerated: an aborted earlier attempt leaves the PDB MOUNTED, and closing
-- an already closed PDB fails with ORA-65020.
ALTER PLUGGABLE DATABASE ${CLONE_SRC_PDB} CLOSE IMMEDIATE;
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER PLUGGABLE DATABASE ${CLONE_SRC_PDB}
  UNPLUG INTO '${ARCHIVE_PATH}'
  ENCRYPT USING \"${P2_SECRET}\";
DROP PLUGGABLE DATABASE ${CLONE_SRC_PDB} INCLUDING DATAFILES;
SELECT 'PDBCLONE unplugged and dropped' AS status FROM dual;
EXIT
"

    # Phase 2: Re-plug PDBCLONE back into prod so P4 can use it
    step_header "Phase 2: Re-plug ${CLONE_SRC_PDB} back into prod"
    # The plug-in needs the keystore password too - same ORA-46697 as the clone
    # in step 62. Every PDB operation touching encrypted tablespaces requires
    # it; an auto-login keystore does not satisfy any of them.
    # shellcheck disable=SC1078,SC1079
    lib_run in_prod_stdin '
KSPWD=$(cat '"${WALLET_DIR_CONTAINER}"'/wallet_pwd.txt)
sqlplus -S / as sysdba <<SQL 2>&1 | grep -viE "identified by|decrypt using"; _rc=${PIPESTATUS[0]}; [ "${_rc}" -eq 0 ] || { echo "ERROR: sqlplus exited ${_rc}" >&2; exit "${_rc}"; }
WHENEVER SQLERROR EXIT SQL.SQLCODE
CREATE PLUGGABLE DATABASE '"${CLONE_SRC_PDB}"'
  USING '"'"''"${ARCHIVE_PATH}"''"'"'
  DECRYPT USING "'"${P2_SECRET}"'"
  KEYSTORE IDENTIFIED BY "${KSPWD}"
  COPY TEMPFILE REUSE;
ALTER PLUGGABLE DATABASE '"${CLONE_SRC_PDB}"' OPEN READ WRITE;
ALTER PLUGGABLE DATABASE '"${CLONE_SRC_PDB}"' SAVE STATE;
SELECT name, open_mode FROM v\$pdbs WHERE name='"'"''"${CLONE_SRC_PDB}"''"'"';
EXIT
SQL
'

    # Phase 3: Drop PDBCLONE_P2 in dev if it exists (idempotency)
    step_header "Phase 3: Prepare dev - drop ${CLONE_P2_PDB} if exists"
    sqlplus_dev "
WHENEVER SQLERROR CONTINUE
ALTER PLUGGABLE DATABASE ${CLONE_P2_PDB} CLOSE IMMEDIATE;
DROP PLUGGABLE DATABASE ${CLONE_P2_PDB} INCLUDING DATAFILES;
WHENEVER SQLERROR EXIT SQL.SQLCODE
SELECT 'dev cleanup done' AS status FROM dual;
EXIT
"

    # Phase 4: Plug PDBCLONE_P2 into dev
    step_header "Phase 4: CREATE ${CLONE_P2_PDB} in dev from archive"
    # shellcheck disable=SC1078,SC1079
    lib_run in_dev_stdin '
KSPWD=$(cat '"${WALLET_DIR_CONTAINER}"'/wallet_pwd.txt)
sqlplus -S / as sysdba <<SQL 2>&1 | grep -viE "identified by|decrypt using"; _rc=${PIPESTATUS[0]}; [ "${_rc}" -eq 0 ] || { echo "ERROR: sqlplus exited ${_rc}" >&2; exit "${_rc}"; }
WHENEVER SQLERROR EXIT SQL.SQLCODE
CREATE PLUGGABLE DATABASE '"${CLONE_P2_PDB}"'
  USING '"'"''"${ARCHIVE_PATH}"''"'"'
  DECRYPT USING "'"${P2_SECRET}"'"
  KEYSTORE IDENTIFIED BY "${KSPWD}"
  -- No TEMPFILE REUSE when plugging into the other CDB: the temp file path
  -- recorded in the archive is /opt/oracle/oradata/FREE/temp01.dbf, and both
  -- containers run the same image, so REUSE tries to adopt the target CDB own
  -- temp file and fails with ORA-01187 on data file 1025. Without the clause
  -- Oracle creates a fresh temp file under db_create_file_dest.
  COPY;
ALTER PLUGGABLE DATABASE '"${CLONE_P2_PDB}"' OPEN READ WRITE;
SELECT name, open_mode FROM v\$pdbs WHERE name='"'"''"${CLONE_P2_PDB}"''"'"';
EXIT
SQL
'

    # Phase 5: Query key chain in clone
    step_header "Phase 5: Query key chain in ${CLONE_P2_PDB}"
    sqlplus_dev "
SET HEADING ON FEEDBACK ON PAGESIZE 100 LINESIZE 200
ALTER SESSION SET CONTAINER=${CLONE_P2_PDB};
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
    collect_evidence "${DEV_SERVICE}" "${CLONE_P2_PDB}" "${LABEL}" "${CLONE_TS_ENC}"

    # Compare against pdb_baseline
    step_header "Compare '${LABEL}' vs 'pdb_baseline' (expect TEK identical)"
    compare_evidence "pdb_baseline" "${LABEL}"

    # Read key values and ORIGIN
    local mkid_p2 tek_p2 kv_p2 origin_p2
    mkid_p2=""; tek_p2=""; kv_p2=""; origin_p2=""
    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        mkid_p2=$(get_masterkeyid "${DEV_SERVICE}" "${CLONE_P2_PDB}" "${CLONE_TS_ENC}")
        tek_p2=$(get_encryptedkey  "${DEV_SERVICE}" "${CLONE_P2_PDB}" "${CLONE_TS_ENC}")
        kv_p2=$(printf '%s\n' "
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 80 TRIMSPOOL ON
ALTER SESSION SET CONTAINER=${CLONE_P2_PDB};
SELECT key_version FROM v\$encrypted_tablespaces WHERE ts# = (SELECT ts# FROM v\$tablespace WHERE name='${CLONE_TS_ENC}' AND con_id=sys_context('userenv','con_id'));
EXIT" | docker exec -i "${DEV_SERVICE}" sqlplus -S / as sysdba 2>/dev/null \
            | awk 'NF && $1 ~ /^[0-9]+$/ { print $1; exit }')
        origin_p2=$(printf '%s\n' "
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 80 TRIMSPOOL ON
ALTER SESSION SET CONTAINER=${CLONE_P2_PDB};
SELECT origin FROM v\$encryption_keys
WHERE con_id = sys_context('userenv','con_id') AND rownum=1;
EXIT" | docker exec -i "${DEV_SERVICE}" sqlplus -S / as sysdba 2>/dev/null \
            | awk 'NF && /^[A-Z]+$/ { print $1; exit }')
    else
        mkid_p2="DRY-RUN-MKID"; tek_p2="DRY-RUN-TEK"; kv_p2="0"; origin_p2="IMPORTED"
    fi

    local tek_src
    tek_src=$(read_state "PDBCLONE_TEK_ENC")
    local mkid_src
    mkid_src=$(read_state "PDBCLONE_MKID_ENC")

    write_state "PDB_P2_TEK"         "${tek_p2}"
    write_state "PDB_P2_MKID"        "${mkid_p2}"
    write_state "PDB_P2_KEY_VERSION" "${kv_p2}"
    write_state "PDB_P2_ORIGIN"      "${origin_p2}"
    write_state "PDB_TARGET_READY"   "TRUE"
    write_state "PDB_TARGET_NAME"    "${CLONE_P2_PDB}"
    write_state "PDB_TARGET_SERVICE" "${DEV_SERVICE}"

    local verdict msg
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        verdict="PASS"; msg="DRY-RUN"
    elif [[ "${tek_p2}" == "${tek_src}" ]]; then
        verdict="PASS"
        msg="P2: TEK preserved through archive transport, ORIGIN=${origin_p2}, KEY_VERSION=${kv_p2}"
    else
        verdict="FAIL"
        msg="P2: TEK DIFFERS from source - unexpected for PDB archive plug-in"
    fi

    print_key_summary "pdb_p2_archive (${CLONE_P2_PDB})" "${mkid_p2}" "${tek_p2}" \
        "ORIGIN=${origin_p2} KEY_VERSION=${kv_p2}"
    print_key_summary "pdb_baseline   (${CLONE_SRC_PDB})" "${mkid_src}" "${tek_src}"
    echo ""
    echo "TEK comparison:  $( [[ "${tek_p2}" == "${tek_src}" ]] && echo "IDENTICAL (expected)" || echo "DIFFERENT")"
    echo "ORIGIN in clone: ${origin_p2} (expect: IMPORTED)"
    echo "KEY_VERSION:     ${kv_p2} (doc: may reset to 0 after foreign plug-in)"

    print_verdict "${verdict}" "${msg}"
    lib_info "Done."
}

main "$@"
# --- EOF ----------------------------------------------------------------------
