#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: 45_zdlra_aux_pdb_clone.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026-09-11
# Version....: 0.4.0
# Purpose....: Auxiliary restore plus PDB clone - the chain a customer needs
#              when the copy has to come from a backup appliance (ZDLRA) and
#              the target must still be cryptographically independent.
#              Measures the one link that steps 20/40 and 62/65 leave open:
#              does a PDB clone taken OUT OF a restored auxiliary produce new
#              tablespace key material, and does the clone survive the removal
#              of the source master key while its own source PDB does not.
#              Phases:
#              1. Preflight and state gate (needs step 15 backup)
#              2. Reset dev to a pristine auxiliary instance
#              3. Restore/duplicate the auxiliary from the staged backup with
#                 the source keystore in place
#              4. Verify the auxiliary PDB is readable, collect 'aux_restored'
#              5. Create and activate a dev-owned MEK in the auxiliary CDB
#              6. Clone the auxiliary PDB into the target PDB
#              7. Collect 'aux_clone', compare canary blocks vs baseline
#              8. Withdrawal test - the discriminator: target PDB must open,
#                 auxiliary PDB must fail with ORA-28374
#              9. Evidence, verdict, state
# Notes......: First passing run 2026-10-24, artefacts/run_20261024_094125.log;
#              registered as step 45 in run_all.sh. Every phase supports
#              --dry-run.
#
#              Lab limitation, stated on purpose: the lab has two containers,
#              so the auxiliary and the target PDB live in the SAME dev CDB and
#              share one keystore. That is why phase 8 is the decisive step -
#              it is the only way to tell an independent clone from a dependent
#              one inside a shared keystore. The three-zone variant (separate
#              auxiliary and target CDBs, separate keystores) needs a third
#              service odbencaux and is the natural follow-up.
#              The lab has no Oracle Key Vault. Whether a clone across two
#              INDEPENDENT Key Vault clusters behaves the same, and what
#              credentials ORA-46697 then demands on each side, is not
#              measurable here.
# Reference..: https://github.com/oehrlis/oracle-free-labs
# License....: Apache License Version 2.0, January 2004 as shown
#              at http://www.apache.org/licenses/
# ------------------------------------------------------------------------------
# CHANGE LOG:
# 2026-09-10  oes  Initial release - prepared, not yet executed              0.1.0
# 2026-09-11  oes  Phases 3, 5 and 8 implemented; phase 6 password handling
#                  moved off the SQL text into the container               0.2.0
# 2026-10-24  oes  First real runs: SET KEY in CDB$ROOT reached SQL*Plus as
#                  "CDB" (unquoted heredoc), stale CDB temp file (ORA-01187),
#                  clone keystore closed (ORA-28365); withdrawal and canary
#                  read moved to lib.sh; registered as step 45             0.3.0
# 2026-10-24  oes  Phase 6 via sqlplus_kspwd without WHENEVER SQLERROR
#                  CONTINUE, FAIL if a non-seed keystore stays CLOSED; key
#                  export deleted by default (--keep); canary rc 3 =
#                  differs; ORA-28365 is UNCLEAR; failed withdrawal is FAIL 0.4.0
# ------------------------------------------------------------------------------

set -euo pipefail
SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="0.4.0"
VERBOSE=${VERBOSE:-"FALSE"}
DRY_RUN=${DRY_RUN:-"FALSE"}
FORCE_YES=${FORCE_YES:-"FALSE"}

# CANARY_MARKER is deliberately NOT set here. This step works on the baseline
# data set in USERS, which 10_baseline.sh creates with the lib.sh default
# OEHRLI-CANARY-01. Overriding it with the PDB series marker
# (OEHRLI-CANARY-2026-09-03, set in 61_pdb_testbed.sh for its own tables in
# CLONE_ENC) would make the plaintext scan search for a needle that is not in
# this haystack: zero hits, which reads as "encrypted" and proves nothing.
AUX_PDB="${AUX_PDB:-ODBENCPROD}"          # the PDB as it arrives from the restore
TARGET_PDB="${TARGET_PDB:-PDBAUX_CLONE}"  # the clone, the actual deliverable
AUX_TS_ENC="${AUX_TS_ENC:-USERS}"
PDB_ONLY="FALSE"                          # see --pdb-only
KEEP_KEYS_FILE="${KEEP_KEYS_FILE:-FALSE}"  # see --keep
LABEL_AUX="aux_restored"
LABEL_CLONE="aux_clone"

# Transport secret for the key export in phase 8, generated per run. A fixed
# value in the repository would be a committed secret even in a lab, and it adds
# nothing: the secret only has to match between the export and the import within
# this one run. Same construction as 65_pdb_p4_remote.sh - head -c would exit
# early, tr would get SIGPIPE, and with pipefail set -e aborts the script.
AUX_KEY_SECRET="$(openssl rand -base64 48 | LC_ALL=C tr -dc "A-Za-z0-9" | cut -c1-24)"

# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

KEYS_FILE="${XCHANGE_CONTAINER}/aux45_dev_keys.exp"
# The root container name, literally - the $ is part of the Oracle name.
# shellcheck disable=SC2016 # literal Oracle container name, no expansion wanted
ROOT_CON='CDB$ROOT'
WALLET_ASIDE="${XCHANGE_CONTAINER}/wallet_source_used_45"
WALLET_BACKUP="${XCHANGE_CONTAINER}/wallet_withdrawal_backup_45"

# ------------------------------------------------------------------------------
# usage
# ------------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

  Auxiliary restore plus PDB clone. Restores the staged backup into odbencdev
  as an auxiliary, clones the encrypted PDB inside it, then removes the source
  master key and checks which of the two PDBs still opens.

  Expected outcome if the chain works:
    - auxiliary PDB   : canary readable, keys identical to production
    - cloned PDB      : new wrapped key, 0 of N canary blocks identical
    - after withdrawal: cloned PDB opens, auxiliary PDB fails with ORA-28374

  Prerequisite: step 15 (RMAN backup + staged source keystore).

Options:
  -h, --help       Show this help and exit
  -v, --verbose    Enable verbose output
  -d, --dry-run    Show what would be done; change nothing
  -y, --yes        Do not prompt before destructive steps
      --keep       Keep the key export file after the withdrawal (default:
                   delete it - it holds the dev master keys)
      --pdb-only   Restrict the restore to a single PDB plus the auxiliary set
                   instead of duplicating the whole CDB. UNVERIFIED - the exact
                   supported syntax is what this option is meant to establish.

Examples:
  ${SCRIPT_NAME} --dry-run
  ${SCRIPT_NAME} --verbose
  ${SCRIPT_NAME} --pdb-only --dry-run

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
        --pdb-only)   PDB_ONLY="TRUE"; shift ;;
        --keep)       KEEP_KEYS_FILE="TRUE"; shift ;;
        *) lib_err "Unknown option: $1"; usage; exit 1 ;;
    esac
done

# ------------------------------------------------------------------------------
# Function: restore_auxiliary
# Purpose.: Bring the staged backup up in dev as an auxiliary
# Args....: none
# Returns.: 0 the auxiliary is restored and open, 1 otherwise
# Output..: the RMAN and SQL*Plus output of tde_clone.sh
# Depends.: tde_clone.sh, read_state
# Example.: restore_auxiliary
# ------------------------------------------------------------------------------
# The whole-CDB path is the one already measured in step 40, so it is the
# default and keeps this script's new content to the clone question. The
# --pdb-only path is the open one: RMAN documents a restricted duplicate, but
# which clause carries it, and what the auxiliary set must contain for an
# encrypted PDB, is exactly what has to be established.
restore_auxiliary() {
    if [[ "${PDB_ONLY}" == "TRUE" ]]; then
        step_header "Phase 3a: Restore restricted to PDB ${AUX_PDB} (UNVERIFIED)"
        lib_warn "--pdb-only is unverified: the restricted-duplicate syntax and the"
        lib_warn "composition of the auxiliary set for an encrypted PDB are open."
        lib_warn "Expect this phase to need iteration; that is its purpose."
        if [[ "${DRY_RUN}" == "TRUE" ]]; then
            lib_info "DRY-RUN: would run DUPLICATE ... PLUGGABLE DATABASE ${AUX_PDB}"
            lib_info "DRY-RUN: candidate clause to measure:"
            lib_info "  DUPLICATE DATABASE TO FREE PLUGGABLE DATABASE ${AUX_PDB}"
            lib_info "    BACKUP LOCATION '${XCHANGE_CONTAINER}/backup'"
            return 0
        fi
        lib_err "--pdb-only is not implemented yet - establish the syntax with"
        lib_err "--dry-run and the RMAN reference first, then fill this branch in."
        return 1
    fi

    step_header "Phase 3b: Restore the whole CDB as the auxiliary"

    local dbid cf_piece
    dbid=$(read_state "SOURCE_DBID")
    # The named control file autobackup of the SOURCE. RESTORE CONTROLFILE FROM
    # AUTOBACKUP takes the newest piece, and once the target carries the source
    # DBID its own autobackups land in the same cf_c-<dbid>-* namespace in the
    # shared directory - the newest one is then the target's, and recovery asks
    # for sequence 1 of that incarnation (RMAN-06054). tde_clone.sh takes the
    # piece by name via --cf-piece and does not catalog the backup directory,
    # which is the second trap: CATALOG START WITH registers a previous clone's
    # autobackup and silently makes the target's incarnation the current one
    # (ORA-19912 on recovery).
    cf_piece=$(read_state "BACKUP_CF_PIECE")
    if [[ -z "${cf_piece}" ]]; then
        lib_err "BACKUP_CF_PIECE is unset - run step 15 first"
        return 1
    fi
    lib_info "DBID ${dbid}, control file autobackup ${cf_piece}"

    # Variant 'a', not 'c'. Variant c duplicates AS ENCRYPTED; the auxiliary
    # does not need that - it only has to be readable, and a plain RESTORE is
    # both the shorter path and one variable fewer in the chain under test.
    # Variant a is exactly that: transport the source keystore, restore the
    # named control file, plain RESTORE DATABASE, RECOVER, OPEN RESETLOGS, and
    # recreate the auto-login afterwards. It also leaves the untouched dev
    # keystore behind in ${XCHANGE_CONTAINER}/wallet_dev_pristine, which is why
    # --delete is required and why phase 8 has a rollback copy to fall back on.
    local clone_args
    clone_args=(--variant a --dbid "${dbid}" --cf-piece "${cf_piece}" --delete)
    if [[ "${VERBOSE}" == "TRUE" ]]; then
        clone_args+=(--verbose)
    fi
    if [[ "${FORCE_YES}" == "TRUE" ]]; then
        clone_args+=(--yes)
    fi
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        lib_info "DRY-RUN: would run: ${CLONE_SCRIPT} ${clone_args[*]}"
        return 0
    fi
    "${CLONE_SCRIPT}" "${clone_args[@]}"
}

# ------------------------------------------------------------------------------
# Function: set_dev_mek
# Purpose.: Create and activate a dev-owned master key in one container
# Args....: $1  container name inside the dev CDB (CDB\$ROOT or a PDB name)
# Returns.: 0 SET KEY was issued, 1 the call itself failed
# Output..: the resulting v$encryption_keys rows
# Depends.: sqlplus_kspwd
# Example.: set_dev_mek ODBENCPROD
# Notes...: One container per call, never CONTAINER=ALL. PDB\$SEED carries no
#           master key, so CONTAINER=ALL fails with ORA-46663, "master
#           encryption keys not created for all PDBs for REKEY", and leaves the
#           rotation half done - measured in 50_variant_d.sh.
# ------------------------------------------------------------------------------
set_dev_mek() {
    local container="$1"
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        lib_info "DRY-RUN: would run ADMINISTER KEY MANAGEMENT SET KEY in ${container}"
        return 0
    fi
    # The SQL goes through sqlplus_kspwd, whose heredoc is quoted. The first
    # version used an unquoted one, so CDB$ROOT reached SQL*Plus as "CDB" -
    # ORA-65011 - and WHENEVER SQLERROR CONTINUE let the run go on with the
    # source root key still active (measured 2026-10-24, first real run).
    sqlplus_kspwd "${DEV_SERVICE}" "
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET LINESIZE 200 PAGESIZE 100 FEEDBACK OFF
ALTER SESSION SET CONTAINER=${container};
ADMINISTER KEY MANAGEMENT SET KEY FORCE KEYSTORE IDENTIFIED BY \"__KSPWD__\" WITH BACKUP;
COLUMN key_id FORMAT A54
SELECT key_id, origin, con_id FROM v\$encryption_keys
 WHERE con_id = sys_context('userenv','con_id');
EXIT
"
}

# ------------------------------------------------------------------------------
# Function: refresh_cdb_tempfiles
# Purpose.: Replace the CDB$ROOT temp files that the restore left stale
# Args....: none
# Returns.: 0 replaced, non-zero SQL*Plus exit code otherwise
# Output..: the resulting v$tempfile rows of CDB$ROOT
# Depends.: sqlplus_dev, ensure_omf (ADD TEMPFILE without a name needs OMF)
# Example.: refresh_cdb_tempfiles
# Notes...: Measured 2026-10-24, first real run: CREATE PLUGGABLE DATABASE ...
#           FROM failed with ORA-01187 on data file 1025, temp01.dbf. Temp
#           files are not backed up; after OPEN RESETLOGS the restored control
#           file points at the path the pristine dev CDB already used, and the
#           file there belongs to that former database and fails verification.
#           The PDB temp file lives under a new GUID path and is created fresh,
#           so only CDB$ROOT is affected. Same cause as the note in
#           ensure_independent_dev_cdb in lib.sh.
# ------------------------------------------------------------------------------
refresh_cdb_tempfiles() {
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        lib_info "DRY-RUN: would add a fresh temp file per CDB\$ROOT temp tablespace and drop the old ones"
        return 0
    fi
    sqlplus_dev "
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET SERVEROUTPUT ON LINESIZE 200 PAGESIZE 100
DECLARE
  TYPE t_tab IS TABLE OF VARCHAR2(600);
  l_ts t_tab;
  l_fn t_tab;
BEGIN
  -- v\$tempfile and v\$tablespace come from the control file and do not read
  -- the stale file header, unlike dba_temp_files.
  SELECT t.name, f.name BULK COLLECT INTO l_ts, l_fn
    FROM v\$tempfile f JOIN v\$tablespace t ON t.ts# = f.ts# AND t.con_id = f.con_id
   WHERE f.con_id = 1;
  FOR i IN 1 .. l_ts.COUNT LOOP
    -- Drop first: ADD TEMPFILE verifies the existing file of the tablespace
    -- and fails on the stale one with ORA-01122/ORA-01203 (measured).
    EXECUTE IMMEDIATE 'ALTER DATABASE TEMPFILE ''' || l_fn(i) || ''' DROP';
    EXECUTE IMMEDIATE 'ALTER TABLESPACE ' || l_ts(i) || ' ADD TEMPFILE SIZE 50M AUTOEXTEND ON';
    DBMS_OUTPUT.PUT_LINE('replaced temp file ' || l_fn(i) || ' of ' || l_ts(i));
  END LOOP;
END;
/
SELECT file#, name, status FROM v\$tempfile WHERE con_id = 1;
EXIT
"
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
main() {
    lib_info "Starting ${SCRIPT_NAME} ${VERSION}"
    step_header "Step 45: Auxiliary restore + PDB clone"

    # Phase 1: Preflight
    require_command docker
    require_container "${PROD_SERVICE}"
    require_healthy   "${PROD_SERVICE}"
    require_state "SOURCE_DBID"  "source DBID (run step 10 first)"
    require_state "BACKUP_READY" "RMAN backup (run step 15 first)"

    # Phase 2: pristine auxiliary. A duplicate refuses to run against a
    # modified auxiliary instance - same reason step 40 resets first.
    step_header "Phase 2: Reset ${DEV_SERVICE} to a pristine auxiliary"
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        lib_info "DRY-RUN: would reset and restart ${DEV_SERVICE}"
    else
        reset_service "${DEV_SERVICE}"
        start_service "${DEV_SERVICE}"
        wait_for_ready "${DEV_SERVICE}"
    fi
    require_container "${DEV_SERVICE}"
    require_healthy   "${DEV_SERVICE}"
    ensure_omf "${DEV_SERVICE}"

    # Phase 3: the restore
    restore_auxiliary

    # Phase 4: the auxiliary must be readable, and it must look like production.
    # If it does not, the chain is broken before the interesting part and the
    # rest of the run says nothing.
    step_header "Phase 4: Verify auxiliary PDB ${AUX_PDB} and collect '${LABEL_AUX}'"
    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        sqlplus_dev "
SET HEADING ON FEEDBACK ON PAGESIZE 100 LINESIZE 200
WHENEVER SQLERROR CONTINUE
ALTER PLUGGABLE DATABASE ${AUX_PDB} OPEN;
ALTER SESSION SET CONTAINER=${AUX_PDB};
SELECT COUNT(*) AS canary_rows FROM ${CANARY_OWNER}.CANARY_TDE;
SELECT RAWTOHEX(masterkeyid) AS masterkeyid,
       RAWTOHEX(encryptedkey) AS encryptedkey, key_version
FROM v\$encrypted_tablespaces
WHERE ts# = (SELECT ts# FROM v\$tablespace WHERE name='${AUX_TS_ENC}' AND con_id=sys_context('userenv','con_id'));
EXIT
" || lib_warn "the auxiliary verification query did not complete - see the output above"
    fi
    collect_evidence "${DEV_SERVICE}" "${AUX_PDB}" "${LABEL_AUX}" "${AUX_TS_ENC}"

    # The local clone in phase 6 needs a usable CDB temp file.
    step_header "Phase 4b: Replace the stale CDB\$ROOT temp files"
    refresh_cdb_tempfiles

    # Phase 5: the ordering subtlety, and the reason this step exists.
    # A clone wraps its new tablespace key with whatever MEK is active at the
    # time. If the source MEK is still the active one, the clone's key is
    # wrapped by production's key and phase 8 would fail for the wrong reason.
    # So a dev-owned MEK is created and activated BEFORE the clone.
    #
    # Where: in CDB$ROOT *and* in the auxiliary PDB, each on its own, never
    # CONTAINER=ALL - PDB$SEED has no key and CONTAINER=ALL then fails with
    # ORA-46663 leaving the rotation half done (measured in 50_variant_d.sh).
    # Both containers are needed, for two different reasons:
    #   - the PDB, because the clone's tablespace key is wrapped under the MEK
    #     active in the container the clone is taken from;
    #   - CDB$ROOT, because phase 8 removes the source keystore, and a CDB whose
    #     database key still points at the source MEK cannot adopt a new one
    #     afterwards - 60_variant_f.sh measured exactly that: SET KEY in
    #     CDB$ROOT after the keystore was gone failed with ORA-28374, and only
    #     _db_discard_lost_masterkey inside the PDB got past it. Rotating the
    #     root key here, while the source key is still present, avoids needing
    #     that underscore parameter at all.
    # Which of the two the clone actually inherits is not assumed: both key ids
    # are recorded below and phase 7 reports which one the clone's tablespace
    # key hangs on.
    step_header "Phase 5: Create and activate a dev-owned MEK before the clone"
    set_dev_mek "${ROOT_CON}"
    set_dev_mek "${AUX_PDB}"

    local mek_root mek_pdb
    mek_root="DRY-RUN"; mek_pdb="DRY-RUN"
    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        mek_root=$(get_pdb_active_mek "${DEV_SERVICE}" "${ROOT_CON}") || {
            lib_err "could not read the active MEK of CDB\$ROOT after SET KEY"
            return 1
        }
        mek_pdb=$(get_pdb_active_mek "${DEV_SERVICE}" "${AUX_PDB}") || {
            lib_err "could not read the active MEK of ${AUX_PDB} after SET KEY"
            return 1
        }
        lib_info "dev MEK in CDB\$ROOT : ${mek_root}"
        lib_info "dev MEK in ${AUX_PDB}: ${mek_pdb}"
    fi
    write_state "AUX_DEV_MEK_ROOT" "${mek_root}"
    write_state "AUX_DEV_MEK_PDB"  "${mek_pdb}"

    # Phase 6: the clone. Local, because the lab has two containers.
    # The keystore password is read inside the container and handed to SQL*Plus
    # over stdin. The skeleton had it as a ${WALLET_PWD} placeholder in the SQL
    # text, which SQL*Plus does not substitute; and putting it on a "docker exec
    # bash -c" command line would publish it in the host process list.
    step_header "Phase 6: Clone ${AUX_PDB} into ${TARGET_PDB}"
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        lib_info "DRY-RUN: would clone ${AUX_PDB} to ${TARGET_PDB} with KEYSTORE IDENTIFIED BY"
    else
        # A leftover clone from an earlier attempt is dropped first. Checked
        # explicitly instead of running CLOSE/DROP under WHENEVER SQLERROR
        # CONTINUE, which also swallowed every other error of those statements.
        local existing
        existing=$(printf '%s\n' "SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT COUNT(*) FROM v\$pdbs WHERE name = '${TARGET_PDB}';
EXIT" | docker exec -i "${DEV_SERVICE}" sqlplus -S / as sysdba 2>/dev/null \
            | awk 'NF && $1 ~ /^[0-9]+$/ { print $1; exit }' || true)
        if [[ "${existing}" == "1" ]]; then
            lib_info "dropping the leftover ${TARGET_PDB} of an earlier attempt"
            sqlplus_dev "
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER PLUGGABLE DATABASE ${TARGET_PDB} CLOSE IMMEDIATE;
DROP PLUGGABLE DATABASE ${TARGET_PDB} INCLUDING DATAFILES;
EXIT
" || {
                print_verdict "FAIL" "phase 6: could not drop the leftover ${TARGET_PDB} - no clean clone possible"
                return 1
            }
        elif [[ "${existing}" != "0" ]]; then
            print_verdict "FAIL" "phase 6: could not determine whether ${TARGET_PDB} exists (got '${existing}')"
            return 1
        fi
        # The keystore password stays in the container: sqlplus_kspwd replaces
        # __KSPWD__ there from wallet_pwd.txt, nothing reaches the host process
        # list. Every statement runs under WHENEVER SQLERROR EXIT.
        sqlplus_kspwd "${DEV_SERVICE}" "
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET LINESIZE 200 PAGESIZE 100 FEEDBACK ON
-- The source of a local clone has to be READ ONLY.
ALTER PLUGGABLE DATABASE ${AUX_PDB} CLOSE IMMEDIATE;
ALTER PLUGGABLE DATABASE ${AUX_PDB} OPEN READ ONLY;
-- KEYSTORE IDENTIFIED BY is mandatory as soon as the source carries encrypted
-- tablespaces; without it the clone fails with ORA-46697, and an auto-login
-- keystore does not satisfy the clause (measured in 62_pdb_p1_local.sh).
CREATE PLUGGABLE DATABASE ${TARGET_PDB} FROM ${AUX_PDB}
  KEYSTORE IDENTIFIED BY \"__KSPWD__\";
ALTER PLUGGABLE DATABASE ${TARGET_PDB} OPEN READ WRITE;
ALTER PLUGGABLE DATABASE ${AUX_PDB} CLOSE IMMEDIATE;
ALTER PLUGGABLE DATABASE ${AUX_PDB} OPEN READ WRITE;
-- A freshly created or reopened PDB does not inherit the open password
-- keystore: the next query on USERS in the clone failed with ORA-28365 and
-- v\$encryption_wallet showed CLOSED / UNKNOWN for it (measured 2026-10-24).
-- With CONTAINER=ALL and FORCE KEYSTORE the statement succeeded in the
-- 2026-10-24 run (keystore altered); the check below verifies the outcome.
ADMINISTER KEY MANAGEMENT SET KEYSTORE OPEN FORCE KEYSTORE IDENTIFIED BY \"__KSPWD__\" CONTAINER=ALL;
COLUMN name FORMAT A20
SELECT name, open_mode FROM v\$pdbs ORDER BY name;
COLUMN status FORMAT A20
COLUMN wallet_type FORMAT A16
SELECT con_id, status, wallet_type FROM v\$encryption_wallet ORDER BY con_id;
EXIT
" || {
            print_verdict "FAIL" "phase 6: the clone of ${AUX_PDB} into ${TARGET_PDB} failed (see the SQL*Plus output above)"
            return 1
        }
        local closed
        closed=$(count_closed_keystores "${DEV_SERVICE}")
        if [[ "${closed}" != "0" ]]; then
            print_verdict "FAIL" "phase 6: after SET KEYSTORE OPEN ${closed:-an unknown number of} non-seed container(s) still have a closed keystore - the reads below would fail with ORA-28365, not for a missing key"
            return 1
        fi
        lib_info "keystore open in every container except PDB\$SEED"
    fi

    # Phase 7: evidence and the ciphertext comparison
    step_header "Phase 7: Collect '${LABEL_CLONE}' and compare canary blocks"
    collect_evidence "${DEV_SERVICE}" "${TARGET_PDB}" "${LABEL_CLONE}" "${AUX_TS_ENC}"
    compare_evidence "${LABEL_AUX}" "${LABEL_CLONE}"

    local canary_cmp canary_rc
    canary_cmp=""
    canary_rc=0
    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        canary_cmp=$(compare_canary_blocks "${LABEL_AUX}" "${LABEL_CLONE}" \
                       "${DEV_SERVICE}" "${TARGET_PDB}" "CANARY_TDE") || canary_rc=$?
        echo "canary blocks:   ${canary_cmp} (expect all differing - a clone re-encrypts)"
        # Reported, not used as a gate. The ciphertext says whether the clone
        # got new tablespace key material; phase 8 says whether that material
        # is independent of the source. Both are needed, and only the second
        # one can fail in a way that invalidates the run.
        case "${canary_rc}" in
            0) lib_warn "the clone reproduced the auxiliary ciphertext exactly - no new tablespace key material" ;;
            3) lib_info "clone ciphertext differs from the auxiliary - new tablespace key material" ;;
            *) lib_warn "the canary blocks could not be compared - the ciphertext half of the evidence is missing" ;;
        esac
    fi

    # Which MEK the clone's tablespace key actually hangs on. This is the
    # measurement that answers the CDB$ROOT-or-PDB question for phase 5, and it
    # decides which key ids have to survive the withdrawal in phase 8.
    local mek_clone key_id_clone key_id_root key_ids
    mek_clone="DRY-RUN"; key_id_clone="DRY-RUN"; key_id_root="DRY-RUN"; key_ids="'DRY-RUN'"
    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        mek_clone=$(get_masterkeyid "${DEV_SERVICE}" "${TARGET_PDB}" "${AUX_TS_ENC}") || {
            lib_err "could not read the MASTERKEYID of ${AUX_TS_ENC} in ${TARGET_PDB}"
            return 1
        }
        lib_info "clone tablespace key is wrapped under MEK ${mek_clone}"
        if [[ "${mek_clone}" == "${mek_pdb}" ]]; then
            lib_info "that is the dev MEK set in ${AUX_PDB} - the PDB-level SET KEY is the decisive one"
        elif [[ "${mek_clone}" == "${mek_root}" ]]; then
            lib_info "that is the dev MEK set in CDB\$ROOT - the root-level SET KEY is the decisive one"
        else
            lib_warn "the clone uses neither dev MEK - it created a key of its own, or it still"
            lib_warn "hangs on the source key. Phase 8 is what settles it; do not conclude here."
        fi
        key_id_clone=$(get_key_id_for_mek "${DEV_SERVICE}" "${mek_clone}") || {
            lib_err "no key with id ${mek_clone} found in ${DEV_SERVICE} - cannot carry it over"
            return 1
        }
        key_id_root=$(get_key_id_for_mek "${DEV_SERVICE}" "${mek_root}") || {
            lib_err "no key with id ${mek_root} found in ${DEV_SERVICE} - the CDB could not be opened"
            lib_err "after the withdrawal, and the test would fail for the wrong reason"
            return 1
        }
        # The CDB root key is carried over as well, always: without it the
        # container database itself has no usable master key after the swap and
        # nothing opens - which would look like a dependent clone.
        if [[ "${key_id_clone}" == "${key_id_root}" ]]; then
            key_ids="'${key_id_clone}'"
        else
            key_ids="'${key_id_clone}', '${key_id_root}'"
        fi
    fi
    write_state "AUX_CLONE_MEK" "${mek_clone}"

    # Phase 8: the discriminator. Both PDBs sit in one CDB and share one
    # keystore, so only the withdrawal separates them: the clone must survive
    # the loss of the source master key, its own source must not.
    step_header "Phase 8: Withdrawal test - remove the source MEK"
    if [[ "${FORCE_YES}" != "TRUE" && "${DRY_RUN}" != "TRUE" ]]; then
        lib_warn "This replaces the keystore in ${DEV_SERVICE} and restarts it."
        lib_warn "A copy is kept in ${WALLET_BACKUP}, the source keystore in ${WALLET_ASIDE}."
        read -rp "Confirm the withdrawal test on ${DEV_SERVICE}? [y/N] " _reply
        [[ "${_reply}" == [yY] ]] || { lib_warn "withdrawal test aborted by user"; return 1; }
    fi
    local withdraw_rc=0
    withdraw_keystore_to_keys "${key_ids}" "${KEYS_FILE}" "${WALLET_ASIDE}" "${WALLET_BACKUP}" "${AUX_KEY_SECRET}" \
        || withdraw_rc=$?
    # The export holds the dev master keys. Removed by default, also after a
    # failed withdrawal; --keep retains it for a manual rerun of the import.
    if [[ "${KEEP_KEYS_FILE}" == "TRUE" ]]; then
        lib_info "--keep: key export kept at ${KEYS_FILE} (mode 600)"
    else
        lib_run in_dev "rm -f ${KEYS_FILE} && echo 'removed ${KEYS_FILE}'" \
            || lib_warn "could not remove ${KEYS_FILE} - remove it by hand"
    fi
    if [[ ${withdraw_rc} -ne 0 ]]; then
        print_verdict "FAIL" "the keystore withdrawal failed (see above) - no withdrawal result, rollback copy in ${WALLET_BACKUP}"
        return 1
    fi

    step_header "Phase 8a: Restart ${DEV_SERVICE} without the source master key"
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        lib_info "DRY-RUN: would run SHUTDOWN IMMEDIATE + STARTUP and report the open mode"
    else
        sqlplus_dev "
WHENEVER SQLERROR CONTINUE
-- Measured 2026-10-24: with the auxiliary PDB open at shutdown, ALTER DATABASE
-- OPEN of the whole CDB fails with ORA-28374 - the alert log names the
-- missing key as the source PDB MEK in container 4 - after STARTUP FORCE and
-- after SHUTDOWN IMMEDIATE alike. The alert log line Crash Recovery
-- excluding pdb 2 which was cleanly closed shows the way out: a PDB closed
-- explicitly before the shutdown is not part of the open. So the auxiliary is
-- closed first and its saved state discarded; each PDB is opened on its own
-- in phases 8b and 8c, where its dependency shows separately.
ALTER PLUGGABLE DATABASE ${AUX_PDB} CLOSE IMMEDIATE;
ALTER PLUGGABLE DATABASE ${AUX_PDB} DISCARD STATE;
SHUTDOWN IMMEDIATE
STARTUP
SELECT 'OPEN_MODE=' || open_mode AS state FROM v\$database;
SELECT con_id, status, wallet_type FROM v\$encryption_wallet ORDER BY con_id;
EXIT
" || lib_warn "the restart reported an error - the reads below are still the measurement"
    fi

    # Both PDBs, not one. A failing auxiliary read is the expected outcome and
    # is reported as a measurement; only an unclear result is a harness problem.
    step_header "Phase 8b: Read the canary in ${TARGET_PDB} (must succeed)"
    local clone_rc=0
    read_canary_in_pdb "${DEV_SERVICE}" "${TARGET_PDB}" || clone_rc=$?

    step_header "Phase 8c: Read the canary in ${AUX_PDB} (must fail with ORA-28374)"
    local aux_rc=0
    read_canary_in_pdb "${DEV_SERVICE}" "${AUX_PDB}" || aux_rc=$?

    local clone_state aux_state
    # rc 3 is a closed keystore (ORA-28365): a harness state, not a missing
    # key, so it is UNCLEAR and never counts as "blocked".
    case "${clone_rc}" in
        0) clone_state="READABLE" ;;
        1) clone_state="BLOCKED (ORA-28374)" ;;
        3) clone_state="UNCLEAR (keystore closed, ORA-28365)" ;;
        *) clone_state="UNCLEAR" ;;
    esac
    case "${aux_rc}" in
        0) aux_state="READABLE" ;;
        1) aux_state="BLOCKED (ORA-28374)" ;;
        3) aux_state="UNCLEAR (keystore closed, ORA-28365)" ;;
        *) aux_state="UNCLEAR" ;;
    esac

    write_state "AUX_WITHDRAWAL_CLONE" "${clone_state}"
    write_state "AUX_WITHDRAWAL_SOURCE" "${aux_state}"

    # Phase 9: state and verdict
    step_header "Phase 9: Record state"
    write_state "AUX_CHAIN_READY" "TRUE"
    write_state "AUX_TARGET_NAME" "${TARGET_PDB}"

    echo ""
    echo "Withdrawal test result (source master key removed):"
    printf '  clone %s: %s\n' "${TARGET_PDB}" "${clone_state}"
    printf '  auxiliary %s: %s\n' "${AUX_PDB}" "${aux_state}"
    printf '  clone MEK: %s\n' "${mek_clone}"
    printf '  dev MEK %s: %s\n' "${ROOT_CON}" "${mek_root}"
    printf '  dev MEK %s: %s\n' "${AUX_PDB}" "${mek_pdb}"
    if [[ -n "${canary_cmp}" ]]; then
        printf '  canary blocks: %s\n' "${canary_cmp}"
    fi

    local verdict msg
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        verdict="PASS"
        msg="DRY-RUN"
    elif [[ ${clone_rc} -ge 2 || ${aux_rc} -ge 2 ]]; then
        verdict="FAIL"
        msg="at least one canary read gave an unclear result (clone ${clone_state}, auxiliary ${aux_state}) - no verdict possible, investigate the output above"
    elif [[ ${clone_rc} -eq 0 && ${aux_rc} -eq 1 ]]; then
        verdict="PASS"
        msg="a PDB clone taken out of a restored auxiliary is cryptographically independent of the backup source: without the source master key the clone still reads its canary (${canary_cmp}), while the auxiliary PDB it came from fails with ORA-28374"
    elif [[ ${clone_rc} -eq 1 ]]; then
        verdict="FAIL"
        msg="the clone lost its data along with the source master key (clone ${clone_state}, auxiliary ${aux_state}) - the clone is NOT independent, or the dev MEK of phase 5 was not carried over"
    else
        verdict="FAIL"
        msg="the auxiliary PDB is still readable after the withdrawal (${aux_state}) - the source master key was not actually removed, so the clone's independence is not demonstrated"
    fi

    print_verdict "${verdict}" "${msg}"
    lib_info "${SCRIPT_NAME} completed"
}

main "$@"
# --- EOF ----------------------------------------------------------------------
