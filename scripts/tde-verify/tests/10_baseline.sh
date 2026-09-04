#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: 10_baseline.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026-09-04
# Version....: 0.1.0
# Purpose....: Collect the prod baseline for the TDE restore verification test:
#              - Create the canary table SCOTT.CANARY_TDE in the encrypted
#                USERS tablespace and SCOTT.CANARY_PLAIN_TAB in CANARY_PLAIN
#              - Set both tablespaces READ ONLY (block stability for ciphertext
#                comparison)
#              - Collect evidence set 'baseline' via tde_evidence.sh
#                (V$ key chain snapshot, datafile fingerprints, plaintext scan)
#              - Locate the wrapped TEK and MASTERKEYID in the datafile header
#              - Save DBID, MASTERKEYID and wrapped TEK to the lab state file
# Notes......: Prerequisite: odbencprod is running and healthy (step 00).
#              The canary marker OEHRLI-CANARY-01 is written into every row,
#              making the plaintext scan falsifiable: present in CANARY_PLAIN,
#              absent in USERS (encrypted).
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
# --yes accepted for runner compatibility (no destructive operations in this step)
FORCE_YES=${FORCE_YES:-"FALSE"}

# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

# ------------------------------------------------------------------------------
# usage
# ------------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

  Collect the prod baseline for the TDE restore verification test.
  Creates canary tables in the encrypted USERS and unencrypted CANARY_PLAIN
  tablespaces, sets both READ ONLY, and collects evidence set 'baseline'.

  Prerequisite: step 00 (reset lab) must have completed successfully.

Options:
  -h, --help      Show this help and exit
  -v, --verbose   Enable verbose output
  -d, --dry-run   Show what would be done; change nothing

Environment:
  VERBOSE=TRUE    Equivalent to --verbose
  DRY_RUN=TRUE    Equivalent to --dry-run

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
    step_header "Step 10: Collect prod baseline"

    require_command docker
    require_command python3
    require_container "${PROD_SERVICE}"
    require_healthy   "${PROD_SERVICE}"

    # Create the canary in the encrypted USERS tablespace
    step_header "Create canary in USERS (encrypted)"
    sqlplus_prod "
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SESSION SET CONTAINER=${PROD_PDB};
@/opt/oracle/common/scripts/csenc_canary.sql ${CANARY_OWNER} USERS ${CANARY_MARKER} ${CANARY_ROWS} CANARY_TDE
EXIT
"

    # Create control canary in the unencrypted CANARY_PLAIN tablespace
    step_header "Create control canary in CANARY_PLAIN (unencrypted)"
    sqlplus_prod "
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SESSION SET CONTAINER=${PROD_PDB};
@/opt/oracle/common/scripts/csenc_canary.sql ${CANARY_OWNER} CANARY_PLAIN ${CANARY_MARKER} ${CANARY_ROWS} CANARY_PLAIN_TAB
EXIT
"

    # Freeze both tablespaces for stable ciphertext comparison
    step_header "Set USERS and CANARY_PLAIN to READ ONLY"
    sqlplus_prod "
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SESSION SET CONTAINER=${PROD_PDB};
ALTER TABLESPACE USERS READ ONLY;
ALTER TABLESPACE CANARY_PLAIN READ ONLY;
SELECT tablespace_name, status FROM dba_tablespaces
  WHERE tablespace_name IN ('USERS','CANARY_PLAIN')
  ORDER BY 1;
EXIT
"

    # Collect the baseline evidence set (keychain + fingerprints + plaintext scan)
    step_header "Collect evidence set 'baseline'"
    collect_evidence "${PROD_SERVICE}" "${PROD_PDB}" "baseline" "USERS"

    # Also collect fingerprints for the control tablespace
    lib_info "collecting evidence for CANARY_PLAIN (control group)"
    collect_evidence "${PROD_SERVICE}" "${PROD_PDB}" "baseline_plain" "CANARY_PLAIN"

    # Read key values for the state file and summary
    step_header "Read key values"
    local dbid masterkeyid tek
    dbid=""
    masterkeyid=""
    tek=""
    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        dbid=$(get_dbid "${PROD_SERVICE}")
        masterkeyid=$(get_masterkeyid "${PROD_SERVICE}" "${PROD_PDB}" "USERS")
        tek=$(get_encryptedkey "${PROD_SERVICE}" "${PROD_PDB}" "USERS")
    else
        dbid="DRY-RUN-DBID"
        masterkeyid="DRY-RUN-MKID"
        tek="DRY-RUN-TEK"
    fi

    write_state "SOURCE_DBID"        "${dbid}"
    write_state "SOURCE_MASTERKEYID" "${masterkeyid}"
    write_state "SOURCE_TEK"         "${tek}"
    write_state "BASELINE_LABEL"     "baseline"

    # Locate TEK and MASTERKEYID in the datafile header via ssenc_filehdr
    step_header "Dump datafile header (Oracle side)"
    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        local df_path
        df_path=$(docker exec "${PROD_SERVICE}" bash -c \
            "sqlplus -S / as sysdba <<'SQL'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 200 TRIMSPOOL ON
ALTER SESSION SET CONTAINER=${PROD_PDB};
SELECT file_name FROM dba_data_files WHERE tablespace_name='USERS' AND rownum=1;
EXIT
SQL
" 2>/dev/null | awk 'NF { print $1; exit }')
        if [[ -n "${df_path}" ]]; then
            sqlplus_prod "
ALTER SESSION SET CONTAINER=${PROD_PDB};
@/opt/oracle/common/scripts/ssenc_filehdr.sql '${df_path}' 1
EXIT
" || lib_warn "ssenc_filehdr.sql had non-zero exit (trace still written)"
        fi
    fi

    # Print summary
    print_key_summary "baseline" "${masterkeyid}" "${tek}" \
        "DBID=${dbid}, set READ ONLY, evidence in ${EVIDENCE_ROOT}/baseline"

    print_verdict "PASS" "baseline collected, MASTERKEYID and TEK saved to state"
    lib_info "Done."
}

main "$@"
# --- EOF ----------------------------------------------------------------------
