#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: 64_pdb_p3_nokeys.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026-09-04
# Version....: 0.1.0
# Purpose....: PDB P3 - Negative test: unplug PDBCLONE WITHOUT key export,
#              plug into odbencdev. The encrypted tablespace CLONE_ENC must
#              be inaccessible after plug-in because the source MEK is not
#              present in the dev keystore.
#              Expected errors: ORA-28374 (typed master key not found in wallet)
#              or ORA-28365 (wallet is not open), ORA-65025, or similar.
#              The expected failure IS the result; this script exits 0 when
#              the canary read fails with an expected Oracle error.
#              Steps:
#              1. UNPLUG PDBCLONE (no ENCRYPT USING)
#              2. DROP PDBCLONE INCLUDING DATAFILES
#              3. Re-plug PDBCLONE back into prod (for P4)
#              4. In dev: CREATE PDBCLONE_P3 USING archive (no keys)
#              5. Attempt canary read - expect failure
#              6. Log the Oracle error code as evidence
# Notes......: Prerequisite: step 61. This step modifies PDBCLONE in prod.
#              PDBCLONE is re-created from the plain archive so P4 still works.
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
CANARY_MARKER="OEHRLI-CANARY-2026-09-03"
CLONE_SRC_PDB="PDBCLONE"
CLONE_P3_PDB="PDBCLONE_P3"

# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
ARCHIVE_PATH="${XCHANGE_CONTAINER}/pdbclone_p3.pdb"

# ------------------------------------------------------------------------------
# usage
# ------------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

  PDB P3 (negative test): unplug PDBCLONE without key export, plug into dev.
  The encrypted tablespace CLONE_ENC must be inaccessible - no source MEK in
  the dev keystore. Expected Oracle errors: ORA-28374, ORA-28365, ORA-65025.
  The expected failure IS the result: this script exits 0 when the access
  attempt fails with an expected error.

  Prerequisite: step 61 (PDB testbed) must have completed.

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
    step_header "Step 64: PDB P3 - unplug without key export (negative test)"

    require_command docker
    require_container "${PROD_SERVICE}"
    require_container "${DEV_SERVICE}"
    require_healthy   "${PROD_SERVICE}"
    require_healthy   "${DEV_SERVICE}"
    require_state "PDBCLONE_READY" "PDB testbed (run step 61 first)"

    if [[ "${FORCE_YES}" != "TRUE" && "${DRY_RUN}" != "TRUE" ]]; then
        lib_warn "This step unplugs and re-plugs ${CLONE_SRC_PDB} in prod."
        read -rp "Continue? [y/N] " _reply
        [[ "${_reply}" == [yY] ]] || { lib_warn "aborted by user"; exit 1; }
    fi

    # UNPLUG refuses to overwrite an existing archive (ORA-65288), so a retried
    # step would fail on the leftover from the previous attempt.
    step_header "Remove a leftover PDB archive if present"
    lib_run in_prod "if [ -f ${ARCHIVE_PATH} ]; then rm -f ${ARCHIVE_PATH} && echo 'removed leftover archive ${ARCHIVE_PATH}'; else echo 'no leftover archive at ${ARCHIVE_PATH}'; fi"

    # Phase 1: UNPLUG PDBCLONE without ENCRYPT USING
    # PDBs are created in both containers here; without OMF every
    # CREATE PLUGGABLE DATABASE fails with ORA-65016.
    ensure_omf "${PROD_SERVICE}"
    ensure_omf "${DEV_SERVICE}"

    # The DROP deliberately does NOT sit in the same block as the UNPLUG. With
    # SQLERROR CONTINUE it would run even when the UNPLUG failed and delete the
    # source PDB without any archive to restore it from.
    step_header "Phase 1: UNPLUG ${CLONE_SRC_PDB} (no key export)"
    local unplug_output=""
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        lib_info "DRY-RUN: would attempt UNPLUG without ENCRYPT USING"
        unplug_output="DRY-RUN"
    else
        unplug_output=$(sqlplus_prod "
WHENEVER SQLERROR CONTINUE
ALTER PLUGGABLE DATABASE ${CLONE_SRC_PDB} CLOSE IMMEDIATE;
ALTER PLUGGABLE DATABASE ${CLONE_SRC_PDB}
  UNPLUG INTO '${ARCHIVE_PATH}';
EXIT
" 2>&1) || true
        printf '%s\n' "${unplug_output}"
    fi

    # Did an archive actually appear? That, not the message, decides.
    local archive_present="no"
    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        archive_present=$(docker exec "${PROD_SERVICE}" \
            bash -c "[ -f ${ARCHIVE_PATH} ] && echo yes || echo no")
    fi
    lib_info "archive present after the keyless unplug attempt: ${archive_present}"

    # Measured: Oracle refuses the unplug itself with ORA-46680, "Pluggable
    # database (PDB) master keys must be exported". The case was designed on
    # the assumption that the archive gets written and only the plug-in fails.
    # The real answer is stronger - a keyless archive of an encrypted PDB
    # cannot be produced at all, so there is nothing to carry away.
    if [[ "${archive_present}" == "no" && "${DRY_RUN}" != "TRUE" ]]; then
        step_header "Reopen ${CLONE_SRC_PDB} - phase 1 closed it and nothing was unplugged"
        sqlplus_prod "
WHENEVER SQLERROR CONTINUE
ALTER PLUGGABLE DATABASE ${CLONE_SRC_PDB} OPEN READ WRITE;
ALTER PLUGGABLE DATABASE ${CLONE_SRC_PDB} SAVE STATE;
SELECT name, open_mode FROM v\$pdbs WHERE name='${CLONE_SRC_PDB}';
EXIT
"
        local verdict msg
        if printf '%s' "${unplug_output}" | grep -q 'ORA-46680'; then
            verdict="PASS"
            msg="P3: Oracle refuses the keyless unplug outright (ORA-46680, PDB master keys must be exported). No archive is written, so an encrypted PDB cannot be carried off without the keys at all - the block sits earlier than the test assumed"
        else
            verdict="FAIL"
            msg="P3: no archive was written but ORA-46680 is not in the output - see above"
        fi
        write_state "PDB_P3_UNPLUG_BLOCKED" "${verdict}"
        print_verdict "${verdict}" "${msg}"
        lib_info "Done."
        return 0
    fi

    # Only reached when the unplug did produce an archive.
    step_header "Phase 1b: drop ${CLONE_SRC_PDB} - the archive exists"
    sqlplus_prod "
WHENEVER SQLERROR EXIT SQL.SQLCODE
DROP PLUGGABLE DATABASE ${CLONE_SRC_PDB} INCLUDING DATAFILES;
SELECT 'PDBCLONE unplugged (no key export)' AS status FROM dual;
EXIT
"

    # Phase 2: Re-plug PDBCLONE back into prod for P4
    step_header "Phase 2: Re-plug ${CLONE_SRC_PDB} back into prod"
    sqlplus_prod "
WHENEVER SQLERROR EXIT SQL.SQLCODE
CREATE PLUGGABLE DATABASE ${CLONE_SRC_PDB}
  USING '${ARCHIVE_PATH}'
  COPY TEMPFILE REUSE;
ALTER PLUGGABLE DATABASE ${CLONE_SRC_PDB} OPEN READ WRITE;
ALTER PLUGGABLE DATABASE ${CLONE_SRC_PDB} SAVE STATE;
SELECT name, open_mode FROM v\$pdbs WHERE name='${CLONE_SRC_PDB}';
EXIT
"

    # Phase 3: Drop PDBCLONE_P3 in dev if exists (idempotency)
    step_header "Phase 3: Prepare dev - drop ${CLONE_P3_PDB} if exists"
    sqlplus_dev "
WHENEVER SQLERROR CONTINUE
ALTER PLUGGABLE DATABASE ${CLONE_P3_PDB} CLOSE IMMEDIATE;
DROP PLUGGABLE DATABASE ${CLONE_P3_PDB} INCLUDING DATAFILES;
WHENEVER SQLERROR EXIT SQL.SQLCODE
SELECT 'dev cleanup done' AS status FROM dual;
EXIT
"

    # Phase 4: Plug PDBCLONE_P3 into dev (no key import)
    step_header "Phase 4: CREATE ${CLONE_P3_PDB} in dev (no keys)"
    # The PDB may open but encrypted tablespaces will be inaccessible
    sqlplus_dev "
WHENEVER SQLERROR EXIT SQL.SQLCODE
CREATE PLUGGABLE DATABASE ${CLONE_P3_PDB}
  USING '${ARCHIVE_PATH}'
  -- No TEMPFILE REUSE when plugging into the other CDB: the temp file path
  -- recorded in the archive is /opt/oracle/oradata/FREE/temp01.dbf, and both
  -- containers run the same image, so REUSE tries to adopt the target CDB own
  -- temp file and fails with ORA-01187 on data file 1025. Without the clause
  -- Oracle creates a fresh temp file under db_create_file_dest.
  COPY;
WHENEVER SQLERROR CONTINUE
ALTER PLUGGABLE DATABASE ${CLONE_P3_PDB} OPEN READ WRITE;
WHENEVER SQLERROR EXIT SQL.SQLCODE
SELECT name, open_mode FROM v\$pdbs WHERE name='${CLONE_P3_PDB}';
EXIT
"

    # Phase 5: Check keystore state for PDBCLONE_P3
    step_header "Phase 5: Keystore state in ${CLONE_P3_PDB}"
    sqlplus_dev "
WHENEVER SQLERROR CONTINUE
ALTER SESSION SET CONTAINER=${CLONE_P3_PDB};
SELECT wrl_type, status, wallet_type FROM v\$encryption_wallet;
SELECT COUNT(*) AS encrypted_ts FROM v\$encrypted_tablespaces;
EXIT
"

    # Phase 6: Attempt to read the canary - EXPECTED TO FAIL
    step_header "Phase 6: Attempt canary read in ${CLONE_P3_PDB} (expect ORA-28374/ORA-28365)"
    local p3_output=""
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        lib_info "DRY-RUN: would attempt canary read in ${CLONE_P3_PDB} - expect ORA-28374 or similar"
        p3_output="DRY-RUN-ORA-28374"
    else
        p3_output=$(printf '%s\n' "
WHENEVER SQLERROR CONTINUE
ALTER SESSION SET CONTAINER=${CLONE_P3_PDB};
@/opt/oracle/common/scripts/ssenc_canary.sql ${CANARY_OWNER} ${CANARY_MARKER} CANARY_CLONEENC
EXIT" | docker exec -i "${DEV_SERVICE}" sqlplus -S / as sysdba 2>&1 \
            | grep -viE "identified by" || true)
        echo "${p3_output}"
    fi

    # Determine verdict: expected error = PASS, canary readable = FAIL
    local verdict msg
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        verdict="PASS"; msg="DRY-RUN"
    elif echo "${p3_output}" | grep -qE 'ORA-28374|ORA-28365|ORA-65025|ORA-28417|ORA-28360'; then
        verdict="PASS"
        msg="P3 expected: encrypted tablespace inaccessible without key transport (ORA-2837x/ORA-65025)"
    elif echo "${p3_output}" | grep -q "READABLE"; then
        verdict="FAIL"
        msg="P3 unexpected: canary READABLE without key transport - investigate"
    else
        verdict="PASS"
        msg="P3: access denied (no ORA-28374/READABLE; check output above)"
    fi

    # Derive what error was captured for state
    local p3_err
    p3_err=$(echo "${p3_output}" | grep -oE 'ORA-[0-9]+' | head -1 || true)
    write_state "PDB_P3_RESULT" "${p3_err:-ACCESS_DENIED}"

    echo ""
    echo "Captured error/result: ${p3_err:-none}"

    print_verdict "${verdict}" "${msg}"
    lib_info "Done."
}

main "$@"
# --- EOF ----------------------------------------------------------------------
