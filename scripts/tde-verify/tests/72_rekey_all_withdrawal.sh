#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: 72_rekey_all_withdrawal.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026-10-24
# Version....: 0.2.0
# Purpose....: Rekey everything a restored target holds under the source keys,
#              then withdraw the source master keys and check whether the
#              target still opens and reads its data.
#              Step 70 rekeyed USERS only and left the master keys untouched;
#              its withdrawal test stopped at MOUNTED with ORA-28374, because
#              the new tablespace key and both container database keys were
#              still wrapped under the source MEKs. This step closes that gap:
#              1. Preflight and state gate (needs step 15 backup)
#              2. Reset dev, restore via variant A (source keystore in place)
#              3. Inventory: encrypted tablespaces, database keys, source MEKs
#              4. Encrypted READ ONLY tablespaces to READ WRITE
#              5. SET KEY in CDB$ROOT and in every open PDB, one at a time
#              6. ONLINE REKEY of every encrypted tablespace, plus probes on
#                 SYSTEM / SYSAUX / UNDO / TEMP to record what can be rekeyed
#              7. ALTER DATABASE DICTIONARY REKEY CREDENTIALS (SYSKM in root)
#              8. Inventory after: nothing may still point at a source MEK;
#                 collect 'rekey_all' and compare canary blocks vs baseline
#              9. Withdrawal: keystore with the new dev MEKs only, restart,
#                 open, read the canary
# Notes......: Prerequisites: step 15 (backup) must have completed.
#              ONLINE REKEY is technically available in Oracle Free 26ai; in a
#              licensed environment it needs Enterprise Edition with ASO.
#              The verdict is PASS only if the target opens without the source
#              master keys AND reads its canary AND the canary comparison
#              completed with "differs" (rc 3) and 0 identical blocks. A database that stays MOUNTED, or a
#              canary blocked by ORA-28374, is reported as FAIL with the error,
#              because then the procedure does not deliver independence.
# Reference..: https://github.com/oehrlis/oracle-free-labs
# License....: Apache License Version 2.0, January 2004 as shown
#              at http://www.apache.org/licenses/
# ------------------------------------------------------------------------------
# CHANGE LOG:
# 2026-10-24  oes  Initial release                                        0.1.0
# 2026-10-24  oes  PASS needs canary rc 3 and "identical 0"; phase 4/5/6
#                  failures end in a FAIL verdict; key export deleted by
#                  default (--keep); ORA-28365 is UNCLEAR                   0.2.0
# ------------------------------------------------------------------------------

set -euo pipefail
SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="0.2.0"
VERBOSE=${VERBOSE:-"FALSE"}
DRY_RUN=${DRY_RUN:-"FALSE"}
FORCE_YES=${FORCE_YES:-"FALSE"}
KEEP_KEYS_FILE=${KEEP_KEYS_FILE:-"FALSE"}

# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

LABEL="rekey_all"
KEYS_FILE="${XCHANGE_CONTAINER}/rekey72_dev_keys.exp"
WALLET_ASIDE="${XCHANGE_CONTAINER}/wallet_source_used_72"
WALLET_BACKUP="${XCHANGE_CONTAINER}/wallet_withdrawal_backup_72"
# Transport secret for the key export, generated per run - same construction as
# 45_zdlra_aux_pdb_clone.sh. It only has to match between export and import.
REKEY_SECRET="$(openssl rand -base64 48 | LC_ALL=C tr -dc "A-Za-z0-9" | cut -c1-24)"
# Tablespaces probed for the record, encrypted or not. In this lab only USERS is
# encrypted; the probes document what ONLINE REKEY says about the others.
PROBE_TS="SYSTEM SYSAUX UNDOTBS1 TEMP"
# The root container name, literally - the $ is part of the Oracle name.
# shellcheck disable=SC2016 # literal Oracle container name, no expansion wanted
ROOT_CON='CDB$ROOT'
CLONE_EXTRA_ARGS=()

# ------------------------------------------------------------------------------
# usage
# ------------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

  Rekey all encrypted tablespaces and the master keys of a restored target,
  then withdraw the source master keys and check whether the target still
  opens and reads the canary.

  Resets odbencdev, restores via variant A, sets encrypted read-only
  tablespaces READ WRITE, runs SET KEY in CDB\$ROOT and each PDB, ONLINE REKEY
  on every encrypted tablespace, DICTIONARY REKEY CREDENTIALS, then replaces the
  keystore with one holding only the new dev master keys and restarts.

  Prerequisite: step 15 (backup) must have completed.

Options:
  -h, --help      Show this help and exit
  -v, --verbose   Enable verbose output
  -d, --dry-run   Show what would be done; change nothing
  -y, --yes       Skip the confirmation prompts (dev reset, withdrawal)
      --keep      Keep the key export file after the withdrawal (default:
                  delete it - it holds the dev master keys)

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
           --keep)    KEEP_KEYS_FILE="TRUE"; shift ;;
        *) lib_err "Unknown option: $1"; usage; exit 1 ;;
    esac
done

# ------------------------------------------------------------------------------
# Function: dev_query
# Purpose.: Run a query in the dev CDB root without headings
# Args....: $1  SQL text (without SET and EXIT)
# Returns.: 0 always, the output is the measurement
# Output..: the raw rows
# Depends.: docker, sqlplus
# Example.: dev_query "SELECT name FROM v\$pdbs;"
# ------------------------------------------------------------------------------
dev_query() {
    local sql="$1"
    printf '%s\n' "SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 300 TRIMSPOOL ON
${sql}
EXIT" | docker exec -i "${DEV_SERVICE}" sqlplus -S / as sysdba 2>/dev/null || true
}

# ------------------------------------------------------------------------------
# Function: print_key_inventory
# Purpose.: Show every key reference a restored CDB holds
# Args....: $1  heading text
# Returns.: 0
# Output..: encrypted tablespaces, database keys and keystore keys per container
# Depends.: sqlplus_dev
# Example.: print_key_inventory "before"
# Notes...: v$ views queried from CDB$ROOT cover all open containers.
#           v$database_key_info is the container database key that encrypts
#           SYSTEM/SYSAUX/UNDO/TEMP content of encrypted data; it is wrapped under
#           the container MEK just like a tablespace key and was the reference
#           that kept the step 70 target at MOUNTED after the withdrawal.
# ------------------------------------------------------------------------------
print_key_inventory() {
    local what="$1"
    step_header "Key inventory ${what}"
    sqlplus_dev "
SET LINESIZE 250 PAGESIZE 200 FEEDBACK ON
WHENEVER SQLERROR CONTINUE
COLUMN con_name FORMAT A14
COLUMN ts_name FORMAT A14
COLUMN status FORMAT A10
COLUMN masterkeyid FORMAT A32
COLUMN encryptedkey FORMAT A64
PROMPT == Encrypted tablespaces (all containers) ==
SELECT c.name AS con_name, t.name AS ts_name, e.encryptionalg, e.key_version,
       RAWTOHEX(e.masterkeyid) AS masterkeyid, RAWTOHEX(e.encryptedkey) AS encryptedkey
  FROM v\$encrypted_tablespaces e
  JOIN v\$tablespace t ON t.ts# = e.ts# AND t.con_id = e.con_id
  JOIN v\$containers c ON c.con_id = e.con_id
 ORDER BY c.con_id, t.name;
PROMPT == Tablespaces with ENCRYPTED and STATUS (all open containers) ==
SELECT c.name AS con_name, d.tablespace_name AS ts_name, d.encrypted, d.status, d.contents
  FROM cdb_tablespaces d JOIN v\$containers c ON c.con_id = d.con_id
 ORDER BY c.con_id, d.tablespace_name;
PROMPT == Container database keys ==
SELECT c.name AS con_name, k.encryptionalg, RAWTOHEX(k.masterkeyid) AS masterkeyid,
       k.masterkey_activated, SUBSTR(RAWTOHEX(k.encryptedkey),1,64) AS encryptedkey
  FROM v\$database_key_info k JOIN v\$containers c ON c.con_id = k.con_id
 ORDER BY k.con_id;
PROMPT == Keys in the keystore ==
COLUMN key_id FORMAT A54
COLUMN creator_pdbname FORMAT A14
SELECT con_id, key_id, origin, creator_pdbname, activation_time
  FROM v\$encryption_keys ORDER BY creation_time;
EXIT
" || lib_warn "inventory query reported an error - see above"
}

# ------------------------------------------------------------------------------
# Function: mek_refs
# Purpose.: List the distinct non-zero MEK ids referenced by tablespace keys and
#           container database keys
# Args....: none
# Returns.: 0
# Output..: one MASTERKEYID hex per line
# Depends.: dev_query
# Example.: src=$(mek_refs)
# ------------------------------------------------------------------------------
mek_refs() {
    dev_query "
SELECT DISTINCT RAWTOHEX(masterkeyid) FROM (
  SELECT masterkeyid FROM v\$encrypted_tablespaces
  UNION ALL
  SELECT masterkeyid FROM v\$database_key_info)
 WHERE RAWTOHEX(masterkeyid) <> RPAD('0', 32, '0');" \
        | awk 'NF && $1 ~ /^[0-9A-F]{32}$/ { print $1 }' | sort -u
}

# ------------------------------------------------------------------------------
# Function: open_pdbs
# Purpose.: List the open PDBs other than PDB$SEED
# Args....: none
# Returns.: 0
# Output..: one PDB name per line
# Depends.: dev_query
# Example.: for p in $(open_pdbs); do ...; done
# ------------------------------------------------------------------------------
open_pdbs() {
    dev_query "SELECT name FROM v\$pdbs WHERE name <> 'PDB\$SEED' AND open_mode LIKE 'READ%' ORDER BY con_id;" \
        | awk 'NF && $1 ~ /^[A-Z0-9_$#]+$/ { print $1 }'
}

# ------------------------------------------------------------------------------
# Function: encrypted_ts_list
# Purpose.: List the encrypted tablespaces as container:tablespace:status
# Args....: none
# Returns.: 0
# Output..: one entry per line, e.g. ODBENCPROD:USERS:READ ONLY
# Depends.: dev_query
# Example.: encrypted_ts_list
# ------------------------------------------------------------------------------
encrypted_ts_list() {
    dev_query "
SELECT c.name || ':' || d.tablespace_name || ':' || d.status
  FROM cdb_tablespaces d JOIN v\$containers c ON c.con_id = d.con_id
 WHERE d.encrypted = 'YES' ORDER BY c.con_id, d.tablespace_name;" \
        | awk 'NF && /:/ { print }'
}

# ------------------------------------------------------------------------------
# Function: set_mek_in
# Purpose.: Create and activate a new MEK in one container
# Args....: $1  container (CDB$ROOT or PDB name)
# Returns.: exit code of SQL*Plus
# Output..: the SET KEY result and the container keys
# Depends.: sqlplus_kspwd
# Example.: set_mek_in ODBENCPROD
# Notes...: One container per call. CONTAINER=ALL fails with ORA-46663 because
#           PDB$SEED holds no key (measured in 50_variant_d.sh).
# ------------------------------------------------------------------------------
set_mek_in() {
    local container="$1"
    sqlplus_kspwd "${DEV_SERVICE}" "
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET LINESIZE 200 PAGESIZE 100 FEEDBACK ON
ALTER SESSION SET CONTAINER=${container};
ADMINISTER KEY MANAGEMENT SET KEY USING TAG 'rekey72_${container}' FORCE KEYSTORE IDENTIFIED BY \"__KSPWD__\" WITH BACKUP;
EXIT
"
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
main() {
    lib_info "Starting ${SCRIPT_NAME} ${VERSION}"
    step_header "Step 72: Rekey all + database keys, then withdraw the source MEK"

    # Phase 1: preflight
    require_command docker
    require_command python3
    require_command openssl
    require_container "${PROD_SERVICE}"
    require_state "SOURCE_DBID"     "source DBID (run step 10 first)"
    require_state "BACKUP_READY"    "backup flag (run step 15 first)"
    require_state "BACKUP_CF_PIECE" "source control file autobackup (run step 15 first)"

    local dbid cf_piece
    dbid=$(read_state "SOURCE_DBID")
    cf_piece=$(read_state "BACKUP_CF_PIECE")

    # Phase 2: reset dev and restore via variant A
    step_header "Phase 2: Reset ${DEV_SERVICE} and restore via variant A"
    reset_service "${DEV_SERVICE}"
    start_service "${DEV_SERVICE}"
    wait_for_ready "${DEV_SERVICE}" 600
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        lib_info "DRY-RUN: would run: ${CLONE_SCRIPT} --variant a --dbid ${dbid} --cf-piece ${cf_piece} --delete"
    else
        "${CLONE_SCRIPT}" --variant a --dbid "${dbid}" --cf-piece "${cf_piece}" --delete \
            "${CLONE_EXTRA_ARGS[@]}"
    fi

    # Phase 3: inventory before - which MEK ids does the target depend on
    local src_meks="DRY-RUN" mek
    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        print_key_inventory "BEFORE (restored target, source keystore)"
        src_meks=$(mek_refs)
        if [[ -z "${src_meks}" ]]; then
            lib_err "no MEK references found in the restored target - inventory query broken"
            return 1
        fi
        lib_info "source MEK ids referenced by the restored target:"
        while IFS= read -r mek; do printf '  %s\n' "${mek}"; done <<<"${src_meks}"
    fi
    write_state "REKEY72_SOURCE_MEKS" "$(printf '%s' "${src_meks}" | paste -sd, -)"

    # Phase 4: encrypted READ ONLY tablespaces to READ WRITE. Neither SET KEY
    # nor REKEY can touch a read-only tablespace (P5 in steps 66-68).
    step_header "Phase 4: Encrypted READ ONLY tablespaces to READ WRITE"
    local entry con ts status ts_list=""
    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        ts_list=$(encrypted_ts_list)
        printf '%s\n' "${ts_list}"
        while IFS= read -r entry; do
            [[ -n "${entry}" ]] || continue
            con="${entry%%:*}"; ts="${entry#*:}"; status="${ts#*:}"; ts="${ts%%:*}"
            if [[ "${status}" == "READ ONLY" ]]; then
                lib_info "setting ${con}.${ts} READ WRITE"
                sqlplus_dev "
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SESSION SET CONTAINER=${con};
ALTER TABLESPACE ${ts} READ WRITE;
EXIT
" || {
                    print_verdict "FAIL" "phase 4: ALTER TABLESPACE ${con}.${ts} READ WRITE failed - SET KEY and REKEY cannot re-wrap a read-only tablespace, no result possible"
                    return 1
                }
            else
                lib_info "${con}.${ts} is ${status} - nothing to do"
            fi
        done <<<"${ts_list}"
    else
        lib_info "DRY-RUN: would set every encrypted READ ONLY tablespace READ WRITE"
    fi

    # Phase 5: new MEK in CDB$ROOT and in each open PDB
    step_header "Phase 5: SET KEY in CDB\$ROOT and in every open PDB"
    local pdbs="${PROD_PDB}" pdb
    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        pdbs=$(open_pdbs)
    fi
    lib_info "PDBs: ${pdbs//$'\n'/ }"
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        lib_info "DRY-RUN: would run SET KEY in CDB\$ROOT and in: ${pdbs}"
    else
        for con in "${ROOT_CON}" ${pdbs}; do
            set_mek_in "${con}" || {
                print_verdict "FAIL" "phase 5: SET KEY in ${con} failed - the target still uses the source master key there, no result possible"
                return 1
            }
        done
    fi

    # Phase 6: ONLINE REKEY of every encrypted tablespace, then the probes
    step_header "Phase 6: ONLINE REKEY of every encrypted tablespace"
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        lib_info "DRY-RUN: would run ALTER TABLESPACE <ts> ENCRYPTION ONLINE REKEY per encrypted tablespace"
    else
        while IFS= read -r entry; do
            [[ -n "${entry}" ]] || continue
            con="${entry%%:*}"; ts="${entry#*:}"; ts="${ts%%:*}"
            lib_info "ONLINE REKEY ${con}.${ts}"
            sqlplus_dev "
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SESSION SET CONTAINER=${con};
ALTER TABLESPACE ${ts} ENCRYPTION ONLINE REKEY;
EXIT
" || {
                print_verdict "FAIL" "phase 6: ONLINE REKEY of ${con}.${ts} failed - the tablespace keeps its old key, no result possible"
                return 1
            }
        done <<<"${ts_list}"
    fi

    # Inventory between the USERS rekey and the probes. The first run showed
    # the container database keys changing, but the probes below also ran
    # ONLINE REKEY on SYSTEM/SYSAUX/UNDO - without this snapshot it is open
    # whether SET KEY (re-wrap) or a probe changed them.
    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        print_key_inventory "AFTER SET KEY + REKEY of the encrypted tablespaces (before probes)"
    fi

    # The probes are informational: they record what Oracle answers for the
    # tablespaces that are not encrypted here. Errors are the expected output.
    step_header "Phase 6b: Probe ONLINE REKEY on ${PROBE_TS} (record only)"
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        lib_info "DRY-RUN: would probe ONLINE REKEY on ${PROBE_TS} in CDB\$ROOT and ${pdbs}"
    else
        local probe_sql=""
        for con in "${ROOT_CON}" ${pdbs}; do
            probe_sql+="ALTER SESSION SET CONTAINER=${con};
PROMPT == probes in ${con} ==
"
            for ts in ${PROBE_TS}; do
                probe_sql+="PROMPT -- ${con}.${ts}: ALTER TABLESPACE ${ts} ENCRYPTION ONLINE REKEY
ALTER TABLESPACE ${ts} ENCRYPTION ONLINE REKEY;
"
            done
        done
        sqlplus_dev "
WHENEVER SQLERROR CONTINUE
SET FEEDBACK ON
${probe_sql}
EXIT
" || true
    fi

    # Phase 7: dictionary credentials key. The statement needs SYSKM. A SYSKM
    # session cannot switch containers - the first run got ORA-01031 on ALTER
    # SESSION SET CONTAINER and silently stayed in CDB$ROOT - so SYSKM runs in
    # the root only, and each PDB is inspected as SYSDBA, where the REKEY
    # attempt is recorded as whatever Oracle answers.
    step_header "Phase 7: ALTER DATABASE DICTIONARY REKEY CREDENTIALS"
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        lib_info "DRY-RUN: would run ALTER DATABASE DICTIONARY REKEY CREDENTIALS in CDB\$ROOT (SYSKM) and ${pdbs} (SYSDBA)"
    else
        lib_info "CDB\$ROOT as SYSKM"
        printf '%s\n' "WHENEVER SQLERROR CONTINUE
SET FEEDBACK ON LINESIZE 200
PROMPT == CDB\$ROOT (SYSKM): dictionary_credentials_encrypt ==
SELECT sys_context('userenv','con_name') AS con, enforcement FROM dictionary_credentials_encrypt;
PROMPT == CDB\$ROOT (SYSKM): ALTER DATABASE DICTIONARY REKEY CREDENTIALS ==
ALTER DATABASE DICTIONARY REKEY CREDENTIALS;
EXIT" | docker exec -i "${DEV_SERVICE}" sqlplus -S / as syskm 2>&1 || true
        for pdb in ${pdbs}; do
            lib_info "${pdb} as SYSDBA"
            sqlplus_dev "
WHENEVER SQLERROR CONTINUE
SET FEEDBACK ON LINESIZE 200
ALTER SESSION SET CONTAINER=${pdb};
PROMPT == ${pdb} (SYSDBA): dictionary_credentials_encrypt ==
SELECT sys_context('userenv','con_name') AS con, enforcement FROM dictionary_credentials_encrypt;
PROMPT == ${pdb} (SYSDBA): ALTER DATABASE DICTIONARY REKEY CREDENTIALS ==
ALTER DATABASE DICTIONARY REKEY CREDENTIALS;
EXIT
" || true
        done
    fi

    # Phase 8: inventory after and the ciphertext comparison
    local after_meks="DRY-RUN" stale=""
    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        print_key_inventory "AFTER (SET KEY + ONLINE REKEY + probes)"
        after_meks=$(mek_refs)
        lib_info "MEK ids referenced after the rekey:"
        while IFS= read -r mek; do printf '  %s\n' "${mek}"; done <<<"${after_meks}"
        for mek in ${after_meks}; do
            if grep -qx "${mek}" <<<"${src_meks}"; then
                stale+="${mek} "
            fi
        done
        if [[ -n "${stale}" ]]; then
            lib_warn "still referencing a source MEK after the rekey: ${stale}"
        else
            lib_info "no tablespace key and no database key references a source MEK any more"
        fi
    fi
    write_state "REKEY72_AFTER_MEKS" "$(printf '%s' "${after_meks}" | paste -sd, -)"

    step_header "Phase 8b: Collect '${LABEL}' and compare canary blocks vs baseline"
    collect_evidence "${DEV_SERVICE}" "${PROD_PDB}" "${LABEL}" "USERS"
    local canary_cmp="" canary_rc=0
    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        canary_cmp=$(compare_canary_blocks "baseline" "${LABEL}" \
                       "${DEV_SERVICE}" "${PROD_PDB}" "CANARY_TDE") || canary_rc=$?
        echo "canary blocks: ${canary_cmp} (expect all differing)"
    fi

    # Phase 9: withdrawal - a keystore with the new dev MEKs only
    step_header "Phase 9: Withdrawal - keystore with the new dev MEKs only"
    if [[ "${FORCE_YES}" != "TRUE" && "${DRY_RUN}" != "TRUE" ]]; then
        lib_warn "This replaces the keystore in ${DEV_SERVICE} and restarts it."
        read -rp "Confirm the withdrawal test on ${DEV_SERVICE}? [y/N] " _reply
        [[ "${_reply}" == [yY] ]] || { lib_warn "withdrawal aborted by user"; return 1; }
    fi
    local key_ids="'DRY-RUN'" kid
    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        key_ids=""
        for mek in ${after_meks}; do
            if grep -qx "${mek}" <<<"${src_meks}"; then
                continue
            fi
            kid=$(get_key_id_for_mek "${DEV_SERVICE}" "${mek}") || {
                lib_err "no keystore key for MEK ${mek} - cannot carry it over"
                return 1
            }
            key_ids+="${key_ids:+, }'${kid}'"
        done
        if [[ -z "${key_ids}" ]]; then
            lib_err "no dev MEK to carry over - SET KEY in phase 5 did not take effect"
            return 1
        fi
        lib_info "carrying over the dev MEK key ids: ${key_ids}"
    fi
    local withdraw_rc=0
    withdraw_keystore_to_keys "${key_ids}" "${KEYS_FILE}" "${WALLET_ASIDE}" "${WALLET_BACKUP}" "${REKEY_SECRET}" \
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

    step_header "Phase 9a: Clean restart without the source MEKs"
    local startup_out="" open_mode=""
    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        startup_out=$(sqlplus_dev "
WHENEVER SQLERROR CONTINUE
-- Clean restart. In step 45 a PDB that was open at shutdown and needed a
-- missing key blocked ALTER DATABASE OPEN of the whole CDB with ORA-28374,
-- with STARTUP FORCE and SHUTDOWN IMMEDIATE alike. Here the only PDB is the
-- target itself, so a blocked open is the dependency result, not an artefact.
SHUTDOWN IMMEDIATE
STARTUP
SELECT 'OPEN_MODE=' || open_mode AS state FROM v\$database;
SELECT con_id, status, wallet_type FROM v\$encryption_wallet ORDER BY con_id;
EXIT
" 2>&1 || true)
        printf '%s\n' "${startup_out}"
        open_mode=$(printf '%s' "${startup_out}" \
            | sed -n 's/.*OPEN_MODE=\([A-Z ]*[A-Z]\).*/\1/p' | head -1)
        lib_info "database open mode after restart: ${open_mode:-unknown}"
    fi

    step_header "Phase 9b: Read the canary in ${PROD_PDB}"
    local read_rc=0
    if [[ "${DRY_RUN}" != "TRUE" && "${open_mode}" == *"READ"* ]]; then
        read_canary_in_pdb "${DEV_SERVICE}" "${PROD_PDB}" || read_rc=$?
    elif [[ "${DRY_RUN}" != "TRUE" ]]; then
        read_rc=10
        lib_warn "the CDB did not open - no canary read possible"
    else
        read_canary_in_pdb "${DEV_SERVICE}" "${PROD_PDB}" || read_rc=$?
    fi

    # Verdict
    local result verdict msg
    case "${read_rc}" in
        0) result="READABLE" ;;
        1) result="BLOCKED (ORA-28374)" ;;
        3) result="UNCLEAR (keystore closed, ORA-28365)" ;;
        10) result="CDB NOT OPEN (${open_mode:-unknown})" ;;
        *) result="UNCLEAR" ;;
    esac
    write_state "REKEY72_WITHDRAWAL" "${result}"
    write_state "REKEY72_CANARY" "${canary_cmp}"

    echo ""
    echo "Rekey-all withdrawal result:"
    printf '  source MEKs : %s\n' "${src_meks//$'\n'/ }"
    printf '  after MEKs  : %s\n' "${after_meks//$'\n'/ }"
    printf '  stale refs  : %s\n' "${stale:-none}"
    printf '  canary      : %s\n' "${canary_cmp}"
    printf '  open mode   : %s\n' "${open_mode:-n/a}"
    printf '  canary read : %s\n' "${result}"

    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        verdict="PASS"; msg="DRY-RUN"
    elif [[ ${read_rc} -eq 0 && ${canary_rc} -eq 3 && "${canary_cmp}" == "identical 0 "* && -z "${stale}" ]]; then
        verdict="PASS"
        msg="after SET KEY in every container and ONLINE REKEY of every encrypted tablespace the target opens without the source master keys and reads its canary; ciphertext differs from the baseline (${canary_cmp}) - independent"
    elif [[ ${read_rc} -eq 0 ]]; then
        verdict="FAIL"
        msg="the target reads its canary without the source MEKs, but the evidence is incomplete (canary rc ${canary_rc}: ${canary_cmp}; stale refs: ${stale:-none})"
    elif [[ ${read_rc} -eq 10 ]]; then
        verdict="FAIL"
        msg="the target does not open without the source master keys: $(printf '%s' "${startup_out}" | grep -m1 -oE 'ORA-[0-9]{5}.*' || echo "no ORA- error, open mode ${open_mode:-unknown}") - still dependent"
    elif [[ ${read_rc} -eq 1 ]]; then
        verdict="FAIL"
        msg="the CDB opens, but the canary is blocked without the source master keys (${result}) - still dependent"
    elif [[ ${read_rc} -eq 3 ]]; then
        verdict="FAIL"
        msg="the keystore was closed at the canary read (ORA-28365) - says nothing about the source key, no verdict possible"
    else
        verdict="FAIL"
        msg="unclear canary read after the withdrawal - investigate the output above"
    fi
    print_verdict "${verdict}" "${msg}"
    lib_info "Done."
}

main "$@"
# --- EOF ----------------------------------------------------------------------
