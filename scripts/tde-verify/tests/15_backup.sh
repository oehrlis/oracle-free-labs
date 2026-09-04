#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: 15_backup.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026-09-04
# Version....: 0.1.0
# Purpose....: Create an RMAN backup of odbencprod and stage the source keystore
#              for use by the restore variants:
#              - RMAN BACKUP DATABASE PLUS ARCHIVELOG into /opt/oracle/xchange/backup
#              - Controlfile autobackup with a known format so RESTORE CONTROLFILE
#                FROM AUTOBACKUP finds it during the clone steps
#              - Copy the source wallet (ewallet.p12 only, not cwallet.sso) to
#                /opt/oracle/xchange/wallet_prod so clone scripts can transport it
# Notes......: Prerequisite: step 10 must have completed (USERS and CANARY_PLAIN
#              are READ ONLY, state file has SOURCE_DBID).
#              The backup destination /opt/oracle/xchange is a shared bind mount
#              between odbencprod and odbencdev, so no external copy is needed.
#              cwallet.sso is intentionally NOT staged: a LOCAL auto-login keystore
#              is host-bound and opens with ORA-28365 on a different host.
#              Only ewallet.p12 travels; the clone script recreates auto-login
#              on the target host.
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

# Autobackup format kept in sync with tde_clone.sh
BACKUP_DIR="${XCHANGE_CONTAINER}/backup"
# %F is only valid in the controlfile autobackup format. Used in a plain
# BACKUP ... FORMAT clause it fails with ORA-19715. The autobackup is triggered
# by BACKUP DATABASE PLUS ARCHIVELOG anyway and picks up the configured format,
# so no explicit controlfile backup is needed here.
CF_FORMAT="${BACKUP_DIR}/cf_%F"

# ------------------------------------------------------------------------------
# usage
# ------------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

  Create an RMAN backup of odbencprod and stage the source keystore.

  Prerequisite: step 10 (baseline) must have completed successfully.

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
    step_header "Step 15: RMAN backup and keystore staging"

    require_command docker
    require_container "${PROD_SERVICE}"
    require_healthy   "${PROD_SERVICE}"
    require_state "SOURCE_DBID" "source DBID (run step 10 first)"

    local dbid
    dbid=$(read_state "SOURCE_DBID")

    # Ensure backup destination exists inside the container
    step_header "Prepare backup directory"
    lib_run in_prod "mkdir -p ${XCHANGE_CONTAINER}/backup"
    # A previous clone may have left the target's own control file autobackup
    # here, carrying the same DBID. Leaving it makes the piece selection below
    # ambiguous and the clone would restore the wrong control file.
    lib_run in_prod "rm -f ${XCHANGE_CONTAINER}/backup/cf_*"

    # RMAN backup
    step_header "RMAN BACKUP DATABASE PLUS ARCHIVELOG"
    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        printf '%s\n' "
CONFIGURE CONTROLFILE AUTOBACKUP ON;
CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '${CF_FORMAT}';
RUN {
  ALLOCATE CHANNEL c1 DEVICE TYPE DISK FORMAT '${BACKUP_DIR}/%U';
  BACKUP DATABASE PLUS ARCHIVELOG;
  RELEASE CHANNEL c1;
}
EXIT
" | docker exec -i "${PROD_SERVICE}" rman target /

        # Without FORMAT on the channel the pieces silently land in
        # $ORACLE_HOME/dbs instead of the exchange mount, and every later clone
        # step would then catalog an empty directory. Verify rather than assume.
        local piece_count cf_count
        piece_count=$(docker exec "${PROD_SERVICE}" bash -c \
            "find ${BACKUP_DIR} -maxdepth 1 -type f ! -name 'cf_*' 2>/dev/null | wc -l" | tr -d ' ')
        cf_count=$(docker exec "${PROD_SERVICE}" bash -c \
            "find ${BACKUP_DIR} -maxdepth 1 -name 'cf_*' 2>/dev/null | wc -l" | tr -d ' ')
        lib_info "backup pieces in ${BACKUP_DIR}: ${piece_count}, controlfile autobackups: ${cf_count}"
        if [[ "${piece_count}" -lt 1 ]]; then
            lib_err "no backup pieces in ${BACKUP_DIR}"
            lib_err "the channel FORMAT is missing or wrong - the clone steps would catalog nothing"
            return 1
        fi
        if [[ "${cf_count}" -lt 1 ]]; then
            lib_err "no controlfile autobackup in ${BACKUP_DIR}"
            lib_err "RESTORE CONTROLFILE FROM AUTOBACKUP would fail in the clone steps"
            return 1
        fi
    else
        lib_info "DRY-RUN: would run RMAN backup in ${PROD_SERVICE}"
        lib_info "  CONFIGURE CONTROLFILE AUTOBACKUP FORMAT: ${CF_FORMAT}"
        lib_info "  BACKUP DATABASE PLUS ARCHIVELOG"
    fi

    # Stage the source wallet (ewallet.p12 only, not cwallet.sso)
    step_header "Stage source keystore to ${XCHANGE_CONTAINER}/wallet_prod"
    lib_run in_prod "
mkdir -p ${XCHANGE_CONTAINER}/wallet_prod/tde
# Copy only ewallet.p12 - cwallet.sso is LOCAL auto-login and host-bound
if [ -f ${WALLET_DIR_CONTAINER}/tde/ewallet.p12 ]; then
    cp ${WALLET_DIR_CONTAINER}/tde/ewallet.p12 ${XCHANGE_CONTAINER}/wallet_prod/tde/
    echo 'ewallet.p12 staged'
else
    echo 'ERROR: ewallet.p12 not found in ${WALLET_DIR_CONTAINER}/tde/'
    exit 1
fi
# Copy wallet_pwd.txt for the open_keystore step in tde_clone.sh
if [ -f ${WALLET_DIR_CONTAINER}/wallet_pwd.txt ]; then
    cp ${WALLET_DIR_CONTAINER}/wallet_pwd.txt ${XCHANGE_CONTAINER}/wallet_prod/
fi
ls -la ${XCHANGE_CONTAINER}/wallet_prod/tde/
"

    # Verify backup pieces exist on the host side
    local backup_host_dir="${REPO_DIR}/data/xchange/backup"
    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        local piece_count
        piece_count=$(find "${backup_host_dir}" -type f 2>/dev/null | wc -l | tr -d ' ')
        lib_info "backup pieces on host: ${piece_count} file(s) in ${backup_host_dir}"
        if [[ "${piece_count}" -eq 0 ]]; then
            lib_err "no backup pieces found in ${backup_host_dir}"
            exit 1
        fi
        # Locate the control file autobackup
        local cf_piece
        # Exactly one autobackup is expected here because the directory was
        # cleared above. Take the oldest if there are several - the source's own
        # is always written first.
        cf_piece=$(find "${backup_host_dir}" -name "cf_c-${dbid}-*" -type f 2>/dev/null | sort | head -1 || true)
        if [[ -z "${cf_piece}" ]]; then
            lib_err "controlfile autobackup not found in ${backup_host_dir} for DBID ${dbid}"
            exit 1
        fi
        lib_info "controlfile autobackup: ${cf_piece##*/}"
        write_state "BACKUP_CF_PIECE" "${cf_piece##*/}"
    fi

    write_state "BACKUP_READY" "TRUE"

    echo ""
    echo "Backup summary:"
    printf '  DBID         : %s\n' "${dbid}"
    printf '  Backup dir   : %s\n' "${XCHANGE_CONTAINER}/backup"
    printf '  CF format    : %s\n' "${CF_FORMAT}"
    printf '  Wallet staged: %s/wallet_prod\n' "${XCHANGE_CONTAINER}"

    print_verdict "PASS" "RMAN backup complete, source keystore staged"
    lib_info "Done."
}

main "$@"
# --- EOF ----------------------------------------------------------------------
