#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: tde_clone.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026-09-03
# Version....: 0.1.0
# Purpose....: Clone the TDE enabled source database into the target container
#              using one of the variants under test, so that each variant is
#              executed identically and is reproducible from the protocol.
# Notes......: Variants:
#                a   plain RESTORE with the transported source wallet
#                b1  RESTORE ... AS ENCRYPTED USING KEY, source MEK imported
#                b2  RESTORE ... AS ENCRYPTED USING KEY, source MEK NOT present
#                c   DUPLICATE ... AS ENCRYPTED
#              Only the wallet preparation and the RESTORE clause differ between
#              a, b1 and b2 - everything else is held constant on purpose, so a
#              difference in the result cannot come from the procedure.
#              No datafile is ever deleted. After restoring the source control
#              file only the source paths are in use; the target's own former
#              datafiles are left as orphans. That keeps this script free of
#              destructive operations at the cost of some disk.
#              The source wallet must have been staged to
#              ${XCHANGE}/wallet_prod beforehand (see the protocol, phase 1).
# Reference..: https://github.com/oehrlis/oracle-free-labs
#              doc/tde-restore-as-encrypted.md
# License....: Apache License Version 2.0, January 2004 as shown
#              at http://www.apache.org/licenses/
# ------------------------------------------------------------------------------
# CHANGE LOG:
# 2026-09-03  oes  Initial release                                        0.1.0
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# Default Values
# ------------------------------------------------------------------------------
set -euo pipefail
SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")
VERSION="0.1.0"
VERBOSE=${VERBOSE:-"FALSE"}
DRY_RUN=${DRY_RUN:-"FALSE"}
FORCE_YES=${FORCE_YES:-"FALSE"}
ENABLE_DELETE=${ENABLE_DELETE:-"FALSE"}

TARGET="odbencdev"
VARIANT=""
SOURCE_DBID=""
CF_PIECE=""
TARGET_DB_NAME="${TARGET_DB_NAME:-FREE}"
TARGET_KEY_ID=""
XCHANGE="/opt/oracle/xchange"
WALLET_DIR="/opt/oracle/dbconfig/FREE/wallet"

# ------------------------------------------------------------------------------
# Function: log_info, log_warn, log_error, log_debug
# Purpose.: Consistent logging to stdout/stderr
# ------------------------------------------------------------------------------
log_info()  { echo "$(date '+%Y-%m-%d %H:%M:%S') INFO  $*"; }
log_warn()  { echo "$(date '+%Y-%m-%d %H:%M:%S') WARN  $*" >&2; }
log_error() { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR $*" >&2; }
log_debug() {
    [[ "${VERBOSE}" == "TRUE" ]] || return 0
    echo "$(date '+%Y-%m-%d %H:%M:%S') DEBUG $*"
}

# ------------------------------------------------------------------------------
# usage: show script usage
# ------------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} --variant <a|b1|b2|c> --dbid <source_dbid> [OPTIONS]

  Clone the TDE source database into the target container using one variant.

Variants:
  a    plain RESTORE, source wallet transported to the target
  b1   RESTORE DATABASE AS ENCRYPTED USING KEY '<target_key>', source MEK imported
  b2   RESTORE DATABASE AS ENCRYPTED USING KEY '<target_key>', source MEK absent
  c    DUPLICATE TARGET DATABASE ... AS ENCRYPTED

Options:
  -V, --variant NAME   Variant to run (required)
  -D, --dbid ID        DBID of the source database (required for a, b1, b2)
  -C, --cf-piece FILE  Control file autobackup of the SOURCE, file name only.
                       Without it the newest autobackup is used, which after a
                       previous clone is the TARGET's own - see the note below.
  -k, --key KEY_ID     Target master key id, required for b1 and b2
  -t, --target NAME    Target container (default: ${TARGET})
  -h, --help           Show this help and exit
  -v, --verbose        Enable verbose output
  -d, --dry-run        Print the RMAN and SQL steps, execute nothing
  -y, --yes            Skip the confirmation prompt
      --delete         Allow removing the target keystore (required for variant a)

Examples:
  ${SCRIPT_NAME} --variant a  --dbid 1515066983 --dry-run
  ${SCRIPT_NAME} --variant b1 --dbid 1515066983 --key 'AYonWJ...' --yes

EOF
}

# ------------------------------------------------------------------------------
# Function: confirm
# Purpose.: Ask once before touching the target database
# Args....: $1  message
# Returns.: 0   confirmed, 1 aborted
# Output..: prompt on stdout
# Depends.: none
# Example.: confirm "overwrite odbencdev?"
# ------------------------------------------------------------------------------
confirm() {
    local msg="$1" reply
    if [[ "${FORCE_YES}" == "TRUE" || "${DRY_RUN}" == "TRUE" ]]; then
        return 0
    fi
    read -rp "${msg} [y/N] " reply
    [[ "${reply}" == [yY] ]] || { log_warn "aborted by user"; return 1; }
}

# ------------------------------------------------------------------------------
# Function: in_container
# Purpose.: Run a shell command inside the target container
# Args....: $@  command line
# Returns.: exit code of the command
# Output..: command output
# Depends.: docker
# Example.: in_container ls -l /opt/oracle/xchange
# ------------------------------------------------------------------------------
in_container() {
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        log_info "DRY-RUN [shell] $*"
        return 0
    fi
    docker exec "${TARGET}" bash -c "$*"
}

# ------------------------------------------------------------------------------
# Function: run_sqlplus
# Purpose.: Feed a SQL*Plus script to the target as SYSDBA
# Args....: $1  SQL text
# Returns.: exit code of SQL*Plus
# Output..: SQL*Plus output
# Depends.: docker, sqlplus in the container
# Example.: run_sqlplus 'SELECT 1 FROM dual;'
# ------------------------------------------------------------------------------
run_sqlplus() {
    local sql="$1"
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        echo "--- DRY-RUN [sqlplus] ---"; printf '%s\n' "${sql}"; echo "--- end ---"
        return 0
    fi
    printf '%s\n' "${sql}" | docker exec -i "${TARGET}" sqlplus -S / as sysdba
}

# ------------------------------------------------------------------------------
# Function: run_rman
# Purpose.: Feed an RMAN script to the target
# Args....: $1  RMAN text
# Returns.: exit code of RMAN
# Output..: RMAN output
# Depends.: docker, rman in the container
# Example.: run_rman 'REPORT SCHEMA;'
# ------------------------------------------------------------------------------
run_rman() {
    local cmds="$1"
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        echo "--- DRY-RUN [rman] ---"; printf '%s\n' "${cmds}"; echo "--- end ---"
        return 0
    fi
    printf '%s\n' "${cmds}" | docker exec -i "${TARGET}" rman target /
}

# ------------------------------------------------------------------------------
# Function: prepare_wallet
# Purpose.: Put the target keystore into the state the variant requires
# Args....: $1  variant
# Returns.: 0   success
# Output..: progress on stdout
# Depends.: docker
# Example.: prepare_wallet a
# ------------------------------------------------------------------------------
prepare_wallet() {
    local variant="$1"
    case "${variant}" in
        a)
            # The customer's current practice: transport the source keystore.
            # This removes the target keystore, so it needs the explicit --delete
            # opt-in and a verified backup first - a keystore lost without a copy
            # makes every encrypted datafile in that database unreadable.
            log_info "variant a: replacing the target keystore with the source keystore"
            if [[ "${ENABLE_DELETE}" != "TRUE" ]]; then
                log_error "variant a removes the target keystore - rerun with --delete"
                return 1
            fi
            log_info "backing the target keystore up to ${XCHANGE}/wallet_dev_pristine"
            in_container "mkdir -p ${XCHANGE}/wallet_dev_pristine && cp -a ${WALLET_DIR}/. ${XCHANGE}/wallet_dev_pristine/"
            if [[ "${DRY_RUN}" != "TRUE" ]]; then
                if ! docker exec "${TARGET}" test -s "${XCHANGE}/wallet_dev_pristine/tde/ewallet.p12"; then
                    log_error "backup verification failed: ${XCHANGE}/wallet_dev_pristine/tde/ewallet.p12 missing or empty"
                    log_error "refusing to remove the target keystore"
                    return 1
                fi
                log_info "backup verified, keystore file present and non-empty"
            fi
            log_info "staging the source keystore into ${WALLET_DIR}"
            in_container "rm -rf ${WALLET_DIR}/tde ${WALLET_DIR}/tde_seps && cp -a ${XCHANGE}/wallet_prod/. ${WALLET_DIR}/"
            ;;
        b1)
            # Target keeps its own key and additionally holds the source key, so
            # RMAN can read the source blocks at all.
            log_info "variant b1: target keystore keeps its own MEK, source MEK imported"
            in_container "mkdir -p ${XCHANGE}/wallet_dev_pristine"
            log_warn "import of the source MEK is a separate documented step, see protocol"
            ;;
        b2)
            log_info "variant b2: target keystore holds only its own MEK, source MEK absent"
            ;;
        c)
            # DUPLICATE needs the source keystore on the auxiliary, and Oracle
            # documents that it must be open. The instance is restarted several
            # times by DUPLICATE's own memory scripts, so a password-opened
            # keystore does not survive - the auto-login has to be created here,
            # on this host, before the duplicate starts.
            log_info "variant c: staging the source keystore on the auxiliary"
            in_container "mkdir -p ${XCHANGE}/wallet_dev_pristine && cp -a ${WALLET_DIR}/. ${XCHANGE}/wallet_dev_pristine/"
            in_container "rm -rf ${WALLET_DIR}/tde ${WALLET_DIR}/tde_seps && cp -a ${XCHANGE}/wallet_prod/. ${WALLET_DIR}/"
            ensure_autologin
            ;;
        *)
            log_error "unknown variant '${variant}'"
            return 1
            ;;
    esac
}

# ------------------------------------------------------------------------------
# Function: restore_clause
# Purpose.: Return the RESTORE DATABASE clause for the given variant
# Args....: $1  variant
# Returns.: 0   success, 1 for an unknown variant
# Output..: the clause on stdout
# Depends.: none
# Example.: restore_clause b1
# ------------------------------------------------------------------------------
restore_clause() {
    case "$1" in
        a)      echo "RESTORE DATABASE;" ;;
        b1|b2)  echo "RESTORE DATABASE AS ENCRYPTED USING KEY '${TARGET_KEY_ID}';" ;;
        *)      log_error "no restore clause for variant '$1'"; return 1 ;;
    esac
}

# ------------------------------------------------------------------------------
# Function: quarantine_stale_redo
# Purpose.: Move the target's online redo logs out of the way before recovery
# Args....: none
# Returns.: 0   success
# Output..: one line per moved file
# Depends.: docker
# Example.: quarantine_stale_redo
# Notes...: The source control file lists the same redo log paths that the
#           target already uses, but the files on disk still belong to the
#           target's former database. Recovery then aborts with ORA-19698
#           "is from different database". OPEN RESETLOGS recreates them, so the
#           files are only moved, never deleted - no --delete needed and the
#           former database stays recoverable from the quarantine.
# ------------------------------------------------------------------------------
quarantine_stale_redo() {
    local dest="${XCHANGE}/stale_redo_${TARGET}"
    log_info "moving stale online redo logs to ${dest}"
    in_container "mkdir -p ${dest} && for f in /opt/oracle/oradata/FREE/redo*.log; do [ -e \"\$f\" ] && mv \"\$f\" ${dest}/ && echo \"moved \$f\"; done; true"
}

# ------------------------------------------------------------------------------
# Function: open_keystore
# Purpose.: Open the target keystore explicitly if it is not open already
# Args....: none
# Returns.: 0   keystore open or no password file present
# Output..: the resulting v$encryption_wallet rows
# Depends.: docker, sqlplus
# Example.: open_keystore
# Notes...: A transported keystore cannot rely on auto-login: the source creates
#           a LOCAL auto-login keystore, and that is bound to the host it was
#           created on. On the target it stays CLOSED with WALLET_TYPE UNKNOWN,
#           and RESTORE ... AS ENCRYPTED then fails with ORA-28365. The password
#           is read inside the container so it never reaches this script's output.
#           A plain RESTORE does not need this - it copies ciphertext and needs
#           no key at all. Only the AS ENCRYPTED path touches the blocks.
# ------------------------------------------------------------------------------
open_keystore() {
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        log_info "DRY-RUN: would open the keystore using ${WALLET_DIR}/wallet_pwd.txt"
        return 0
    fi
    if ! docker exec "${TARGET}" test -s "${WALLET_DIR}/wallet_pwd.txt"; then
        log_warn "no ${WALLET_DIR}/wallet_pwd.txt - relying on auto-login"
        return 0
    fi
    log_info "opening the target keystore with the stored keystore password"
    docker exec "${TARGET}" bash -c '
KSPWD=$(cat '"${WALLET_DIR}"'/wallet_pwd.txt)
sqlplus -S / as sysdba <<SQL
SET LINESIZE 200 PAGESIZE 100 FEEDBACK OFF
WHENEVER SQLERROR CONTINUE
ADMINISTER KEY MANAGEMENT SET KEYSTORE OPEN FORCE KEYSTORE IDENTIFIED BY "${KSPWD}" CONTAINER=ALL;
COLUMN status FORMAT A14
COLUMN wallet_type FORMAT A16
SELECT con_id, status, wallet_type FROM v\$encryption_wallet ORDER BY con_id;
EXIT
SQL
' 2>&1 | grep -viE "identified by"
}

# ------------------------------------------------------------------------------
# Function: ensure_autologin
# Purpose.: Give the target its own auto-login keystore after the clone
# Args....: none
# Returns.: 0 keystore open, 1 otherwise
# Output..: the resulting v$encryption_wallet rows
# Depends.: docker, sqlplus
# Example.: ensure_autologin
# Notes...: A transported keystore carries the source cwallet.sso, which is a
#           LOCAL auto-login file bound to the host that created it. It does not
#           open here, and it also blocks creating a new one with ORA-46630. The
#           password-based open done before the restore does not survive the
#           instance restart that OPEN RESETLOGS performs, so without this the
#           first query after the clone fails with ORA-28365. Move the foreign
#           .sso aside, keep ewallet.p12 with the keys, create the auto-login
#           locally.
# ------------------------------------------------------------------------------
ensure_autologin() {
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        log_info "DRY-RUN: would recreate the auto-login keystore on the target"
        return 0
    fi
    if ! docker exec "${TARGET}" test -s "${WALLET_DIR}/wallet_pwd.txt"; then
        log_warn "no ${WALLET_DIR}/wallet_pwd.txt - cannot recreate auto-login"
        return 0
    fi

    log_info "recreating the auto-login keystore on the target host"
    # The inner script is passed through a quoted heredoc, so nothing expands on
    # this side. Container paths are literal and the SQL keeps its own $ escaped.
    # Earlier attempts nested three levels of quoting and produced ORA-46604 for
    # the keystore path and ORA-00942 for a v$ view whose name got eaten.
    docker exec -i "${TARGET}" bash -s <<'INNER' | grep -viE "identified by"
set -u
W="/opt/oracle/dbconfig/FREE/wallet"
XCH="/opt/oracle/xchange"
mkdir -p "${XCH}/sso_foreign"
mv "${W}"/tde/cwallet*.sso "${XCH}/sso_foreign/" 2>/dev/null || true
PW="$(cat "${W}/wallet_pwd.txt")"
sqlplus -S / as sysdba >/tmp/autologin.$$.log 2>&1 <<SQL
WHENEVER SQLERROR CONTINUE
SET LINESIZE 200 PAGESIZE 100 FEEDBACK OFF
ADMINISTER KEY MANAGEMENT SET KEYSTORE OPEN FORCE KEYSTORE IDENTIFIED BY "${PW}" CONTAINER=ALL;
ADMINISTER KEY MANAGEMENT CREATE LOCAL AUTO_LOGIN KEYSTORE FROM KEYSTORE '${W}/tde' IDENTIFIED BY "${PW}";
COLUMN status FORMAT A20
COLUMN wallet_type FORMAT A16
SELECT con_id, status, wallet_type FROM v\$encryption_wallet ORDER BY con_id;
EXIT
SQL
grep -viE "identified by" /tmp/autologin.$$.log
rm -f /tmp/autologin.$$.log
INNER

    local closed
    # PDB$SEED keeps a closed keystore in normal operation and holds no
    # encrypted data, so counting it made this check fail on a healthy target.
    closed=$(printf '%s\n' "SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT COUNT(*) FROM v\$encryption_wallet w
WHERE w.status NOT IN ('OPEN','OPEN_NO_MASTER_KEY')
AND NOT EXISTS (SELECT 1 FROM v\$pdbs p WHERE p.con_id = w.con_id AND p.name = 'PDB\$SEED');
EXIT" | docker exec -i "${TARGET}" sqlplus -S / as sysdba 2>/dev/null \
        | awk 'NF && $1 ~ /^[0-9]+$/ { print $1; exit }')
    if [[ -z "${closed}" || "${closed}" != "0" ]]; then
        log_error "target keystore is still not open after recreating the auto-login"
        log_error "every query on encrypted data would fail with ORA-28365"
        return 1
    fi
    log_info "target keystore open via local auto-login"
}

# ------------------------------------------------------------------------------
# Function: last_archived_sequence
# Purpose.: Highest archived log sequence known to the restored control file
# Args....: none
# Returns.: 0   success
# Output..: the sequence number on stdout, 0 if none
# Depends.: docker, sqlplus
# Example.: seq=$(last_archived_sequence)
# Notes...: Recovery must stop right after the last archived log contained in
#           the backup. Without an explicit SET UNTIL SEQUENCE, RMAN asks for
#           the log that was still current when the backup ran and fails with
#           RMAN-06054.
# ------------------------------------------------------------------------------
last_archived_sequence() {
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        echo "0"; return 0
    fi
    printf '%s\n' "
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 80 TRIMSPOOL ON
SELECT NVL(MAX(sequence#), 0) FROM v\$archived_log WHERE thread# = 1;
EXIT
" | docker exec -i "${TARGET}" sqlplus -S / as sysdba 2>/dev/null \
      | awk 'NF && $1 ~ /^[0-9]+$/ { print $1; exit }'
}

# ------------------------------------------------------------------------------
# Function: do_restore
# Purpose.: Restore the source database into the target using the variant clause
# Args....: $1  variant
# Returns.: 0   success
# Output..: RMAN and SQL*Plus output
# Depends.: docker, rman, sqlplus
# Example.: do_restore b1
# ------------------------------------------------------------------------------
do_restore() {
    local variant="$1" clause until_seq
    clause="$(restore_clause "${variant}")"

    log_info "shutting the target down and starting it NOMOUNT"
    run_sqlplus "
WHENEVER SQLERROR CONTINUE
SHUTDOWN IMMEDIATE;
STARTUP NOMOUNT;
EXIT
"
    quarantine_stale_redo

    log_info "restoring the source control file and mounting"
    # SET CONTROLFILE AUTOBACKUP FORMAT must match the format the source used,
    # otherwise RESTORE ... FROM AUTOBACKUP looks in the default FRA location and
    # reports that no AUTOBACKUP was found.
    # Restore a NAMED autobackup, never "FROM AUTOBACKUP". After the control
    # file restore the target carries the source DBID, so any autobackup it
    # triggers later - OPEN RESETLOGS does - is written as
    # cf_c-<source dbid>-<date>-NN into the same shared directory. FROM
    # AUTOBACKUP then picks the newest, which is the target's own control file
    # from a post-RESETLOGS incarnation, and recovery asks for sequence 1 of
    # that new incarnation instead of the source logs.
    local cf_clause
    if [[ -n "${CF_PIECE}" ]]; then
        cf_clause="RESTORE CONTROLFILE FROM '${XCHANGE}/backup/${CF_PIECE}';"
        log_info "control file autobackup: ${CF_PIECE}"
    else
        cf_clause="RESTORE CONTROLFILE FROM AUTOBACKUP;"
        log_warn "no --cf-piece given, falling back to FROM AUTOBACKUP"
        log_warn "this picks the newest autobackup, which may be the target's own"
    fi

    run_rman "
SET DBID ${SOURCE_DBID};
RUN {
  ALLOCATE CHANNEL c1 DEVICE TYPE DISK;
  SET CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '${XCHANGE}/backup/cf_%F';
  ${cf_clause}
  ALTER DATABASE MOUNT;
  RELEASE CHANNEL c1;
}
EXIT
"

    # Keep the target from writing its own autobackups next to the source's.
    # Without this the shared directory accumulates target control files and the
    # next clone restores the wrong one.
    run_rman "
CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '/opt/oracle/oradata/cf_target_%F';
EXIT
"
    open_keystore

    log_info "cataloging the backup pieces"
    run_rman "
RUN {
  ALLOCATE CHANNEL c1 DEVICE TYPE DISK;
  CATALOG START WITH '${XCHANGE}/backup/' NOPROMPT;
  RELEASE CHANNEL c1;
}
EXIT
"
    until_seq="$(last_archived_sequence)"
    until_seq=$(( until_seq + 1 ))
    log_info "restoring with: ${clause}"
    log_info "recovery will stop before archived log sequence ${until_seq}"
    run_rman "
RUN {
  ALLOCATE CHANNEL c1 DEVICE TYPE DISK;
  SET UNTIL SEQUENCE ${until_seq} THREAD 1;
  ${clause}
  RECOVER DATABASE;
  RELEASE CHANNEL c1;
}
EXIT
"
    log_info "opening the target with RESETLOGS"
    run_sqlplus "
WHENEVER SQLERROR CONTINUE
ALTER DATABASE OPEN RESETLOGS;
ALTER PLUGGABLE DATABASE ALL OPEN;
SELECT dbid, name, open_mode, log_mode FROM v\$database;
EXIT
"
    # OPEN RESETLOGS restarts the instance, which closes a password-opened
    # keystore. Without this the first query after the clone hits ORA-28365.
    ensure_autologin
}

# ------------------------------------------------------------------------------
# Function: do_duplicate
# Purpose.: Clone the source into the target with DUPLICATE ... AS ENCRYPTED
# Args....: none
# Returns.: exit code of the duplicate
# Output..: RMAN output
# Depends.: docker, rman
# Example.: do_duplicate
# Notes...: Uses BACKUP LOCATION rather than FROM ACTIVE DATABASE. Active
#           duplication needs the auxiliary to connect back to the target and
#           failed with ORA-17627/ORA-01017 in this lab; the backup based form
#           needs no connection at all and exercises the same AS ENCRYPTED
#           semantics. NOFILENAMECHECK is required because source and target use
#           identical paths in their own containers. DUPLICATE assigns a new
#           DBID, unlike RESTORE which keeps the source DBID.
# ------------------------------------------------------------------------------
do_duplicate() {
    log_info "shutting the auxiliary down and starting it NOMOUNT"
    run_sqlplus "
WHENEVER SQLERROR CONTINUE
SHUTDOWN IMMEDIATE;
STARTUP NOMOUNT;
SELECT status FROM v\$instance;
EXIT
"
    quarantine_stale_redo

    log_info "DUPLICATE DATABASE ... BACKUP LOCATION ... AS ENCRYPTED"
    run_rman "
connect auxiliary /
DUPLICATE DATABASE TO ${TARGET_DB_NAME}
  BACKUP LOCATION '${XCHANGE}/backup'
  NOFILENAMECHECK
  AS ENCRYPTED;
EXIT
"
    log_info "opening the pluggable databases"
    run_sqlplus "
WHENEVER SQLERROR CONTINUE
ALTER PLUGGABLE DATABASE ALL OPEN;
SELECT dbid, name, open_mode FROM v\$database;
SELECT name, open_mode FROM v\$pdbs;
EXIT
"
}

# ------------------------------------------------------------------------------
# Parse arguments
# ------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)     usage; exit 0 ;;
        -v|--verbose)  VERBOSE="TRUE"; shift ;;
        -d|--dry-run)  DRY_RUN="TRUE"; shift ;;
        -y|--yes)      FORCE_YES="TRUE"; shift ;;
           --delete)   ENABLE_DELETE="TRUE"; shift ;;
        -V|--variant)  VARIANT="${2:-}"; shift 2 ;;
        -D|--dbid)     SOURCE_DBID="${2:-}"; shift 2 ;;
        -C|--cf-piece) CF_PIECE="${2:-}"; shift 2 ;;
        -k|--key)      TARGET_KEY_ID="${2:-}"; shift 2 ;;
        -t|--target)   TARGET="${2:-}"; shift 2 ;;
        *)  log_error "Unknown option $1"; usage; exit 1 ;;
    esac
done

# ------------------------------------------------------------------------------
# main
# ------------------------------------------------------------------------------
main() {
    log_info "Starting ${SCRIPT_NAME} ${VERSION}"
    if [[ -z "${VARIANT}" ]]; then
        log_error "--variant is required"; usage; exit 1
    fi
    if [[ "${VARIANT}" =~ ^(a|b1|b2)$ && -z "${SOURCE_DBID}" ]]; then
        log_error "--dbid is required for variant ${VARIANT}"; exit 1
    fi
    if [[ "${VARIANT}" =~ ^(b1|b2)$ && -z "${TARGET_KEY_ID}" ]]; then
        log_error "--key is required for variant ${VARIANT}"; exit 1
    fi
    confirm "This overwrites the database in container '${TARGET}'. Continue?" || exit 1

    prepare_wallet "${VARIANT}"
    case "${VARIANT}" in
        a|b1|b2) do_restore "${VARIANT}" ;;
        c)       do_duplicate ;;
    esac
    log_info "Done."
}

main "$@"
# --- EOF ----------------------------------------------------------------------
