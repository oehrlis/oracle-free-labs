#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: lib.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026-09-04
# Version....: 0.1.0
# Purpose....: Shared library for TDE verification test scripts.
#              Source this file from each test script to get common logging,
#              container helpers, state management and docker wrappers.
# Notes......: This file is sourced, never executed directly. It does not
#              define set -euo pipefail; each caller does that.
# Reference..: https://github.com/oehrlis/oracle-free-labs
# License....: Apache License Version 2.0, January 2004 as shown
#              at http://www.apache.org/licenses/
# ------------------------------------------------------------------------------
# CHANGE LOG:
# 2026-09-04  oes  Initial release                                        0.1.0
# ------------------------------------------------------------------------------

# Guard against being sourced more than once
if [[ -n "${_ORADBA_TDE_LIB_LOADED:-}" ]]; then
    return 0
fi
_ORADBA_TDE_LIB_LOADED=1

# ------------------------------------------------------------------------------
# Paths - callers may override these before sourcing if needed
# These variables are referenced by the callers that source this library.
# ------------------------------------------------------------------------------
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034
TESTS_DIR="${LIB_DIR}"
VERIFY_DIR="$(cd "${LIB_DIR}/.." && pwd)"
REPO_DIR="$(cd "${VERIFY_DIR}/../.." && pwd)"

EVIDENCE_ROOT="${REPO_DIR}/data/xchange/evidence"
STATE_FILE="${EVIDENCE_ROOT}/lab_state.env"
# shellcheck disable=SC2034
FINGERPRINT_TOOL="${VERIFY_DIR}/block_fingerprint.py"
EVIDENCE_SCRIPT="${VERIFY_DIR}/tde_evidence.sh"
# shellcheck disable=SC2034
CLONE_SCRIPT="${VERIFY_DIR}/tde_clone.sh"

PROD_SERVICE="${PROD_SERVICE:-odbencprod}"
DEV_SERVICE="${DEV_SERVICE:-odbencdev}"
PROD_PDB="${PROD_PDB:-ODBENCPROD}"
# shellcheck disable=SC2034
XCHANGE_CONTAINER="/opt/oracle/xchange"
WALLET_DIR_CONTAINER="/opt/oracle/dbconfig/FREE/wallet"
CANARY_MARKER="${CANARY_MARKER:-OEHRLI-CANARY-01}"
CANARY_OWNER="${CANARY_OWNER:-SCOTT}"
CANARY_ROWS="${CANARY_ROWS:-5000}"

# ------------------------------------------------------------------------------
# Logging helpers
# ------------------------------------------------------------------------------
lib_log()  { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }
lib_info() { lib_log "INFO  $*"; }
lib_warn() { lib_log "WARN  $*" >&2; }
lib_err()  { lib_log "ERROR $*" >&2; }
lib_dbg()  {
    [[ "${VERBOSE:-FALSE}" == "TRUE" ]] || return 0
    lib_log "DEBUG $*"
}

# step_header  - print a visible section header
step_header() {
    echo ""
    echo "========================================================================"
    echo "== $*"
    echo "========================================================================"
}

# ------------------------------------------------------------------------------
# Function: lib_run
# Purpose.: Execute a command, or print it in dry-run mode.
#           Uses caller's DRY_RUN variable.
# Args....: $@  command
# Returns.: exit code of the command (0 in dry-run)
# ------------------------------------------------------------------------------
lib_run() {
    if [[ "${DRY_RUN:-FALSE}" == "TRUE" ]]; then
        lib_info "DRY-RUN: $*"
        return 0
    fi
    "$@"
}

# ------------------------------------------------------------------------------
# Function: require_command
# Purpose.: Abort if a required command is not on PATH
# Args....: $1  command name
# Returns.: 0   found, exits 1 if missing
# ------------------------------------------------------------------------------
require_command() {
    local cmd="$1"
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        lib_err "required command not found: ${cmd}"
        exit 1
    fi
}

# ------------------------------------------------------------------------------
# Function: require_container
# Purpose.: Abort if a compose service container is not running
# Args....: $1  container / service name
# Returns.: 0   running, exits 1 otherwise (skipped in dry-run)
# ------------------------------------------------------------------------------
require_container() {
    local name="$1"
    if [[ "${DRY_RUN:-FALSE}" == "TRUE" ]]; then
        lib_info "DRY-RUN: skipping container check for '${name}'"
        return 0
    fi
    local state
    state=$(docker inspect -f '{{.State.Running}}' "${name}" 2>/dev/null || echo "false")
    if [[ "${state}" != "true" ]]; then
        lib_err "container '${name}' is not running"
        lib_err "Start it with: docker compose --profile ${name} up -d"
        exit 1
    fi
    lib_dbg "container ${name} is running"
}

# ------------------------------------------------------------------------------
# Function: require_healthy
# Purpose.: Abort if a container health check is not healthy
# Args....: $1  container / service name
# Returns.: 0   healthy, exits 1 otherwise (skipped in dry-run)
# ------------------------------------------------------------------------------
require_healthy() {
    local name="$1"
    if [[ "${DRY_RUN:-FALSE}" == "TRUE" ]]; then
        lib_info "DRY-RUN: skipping health check for '${name}'"
        return 0
    fi
    local health
    health=$(docker inspect -f '{{.State.Health.Status}}' "${name}" 2>/dev/null || echo "none")
    if [[ "${health}" != "healthy" ]]; then
        lib_err "container '${name}' health status: ${health} (expected: healthy)"
        lib_err "Check logs with: docker compose --profile ${name} logs -f"
        exit 1
    fi
    lib_dbg "container ${name} is healthy"
}

# ------------------------------------------------------------------------------
# Function: wait_for_ready
# Purpose.: Poll compose service logs until "DATABASE IS READY TO USE" appears
#           or a timeout is reached
# Args....: $1  service name
#           $2  timeout in seconds (default 600)
# Returns.: 0   ready, exits 1 on timeout (skipped in dry-run)
# ------------------------------------------------------------------------------
wait_for_ready() {
    local svc="$1" timeout="${2:-600}" elapsed=0 interval=10
    if [[ "${DRY_RUN:-FALSE}" == "TRUE" ]]; then
        lib_info "DRY-RUN: skipping wait_for_ready for '${svc}'"
        return 0
    fi
    lib_info "waiting for ${svc} to be ready (timeout ${timeout}s) ..."
    local state
    while (( elapsed < timeout )); do
        # Read the whole log, not a tail window. The ready marker is printed
        # early and the entrypoint then keeps appending the alert log, so a
        # "--tail 50" window scrolls past the marker within about a minute and
        # the wait never succeeds even though the database is up.
        if docker logs "${svc}" 2>&1 | grep -q "DATABASE IS READY TO USE"; then
            lib_info "${svc} is ready"
            return 0
        fi

        # Fail fast on a setup that already reported failure, instead of
        # burning the full timeout on a container that will never get there.
        if docker logs "${svc}" 2>&1 | grep -qE "DATABASE SETUP WAS NOT SUCCESSFUL|DBT-[0-9]+"; then
            lib_err "${svc} reported a setup failure"
            docker logs "${svc}" 2>&1 | grep -E "DBT-[0-9]+|SETUP WAS NOT SUCCESSFUL" \
                | sort -u | head -5 | sed 's/^/    /' >&2
            lib_err "Check: docker logs ${svc}"
            exit 1
        fi

        # A container that is restarting or gone is not going to become ready.
        state="$(docker inspect -f '{{.State.Status}}' "${svc}" 2>/dev/null | tr -d '[:space:]')"
        [[ -n "${state}" ]] || state="absent"
        case "${state}" in
            running|created) : ;;
            restarting)
                lib_err "${svc} is in a restart loop - it will not become ready"
                docker logs "${svc}" 2>&1 | grep -E "FATAL|DBT-[0-9]+|ORA-[0-9]{5}" \
                    | sort -u | head -5 | sed 's/^/    /' >&2
                exit 1
                ;;
            *)
                lib_err "${svc} is '${state}', expected running"
                exit 1
                ;;
        esac

        sleep "${interval}"
        elapsed=$(( elapsed + interval ))
        lib_dbg "${svc}: ${elapsed}s elapsed, state ${state}"
    done
    lib_err "${svc} did not become ready within ${timeout}s"
    lib_err "Check: docker logs ${svc}"
    exit 1
}

# ------------------------------------------------------------------------------
# Function: check_logs_for_errors
# Purpose.: Scan compose service logs for ORA-, SP2-, DBT- error lines
# Args....: $1  service name
# Returns.: 0   no errors found (or errors found but we continue)
# Output..: matching lines on stderr; prints count (skipped in dry-run)
# ------------------------------------------------------------------------------
check_logs_for_errors() {
    local svc="$1" tmpf
    if [[ "${DRY_RUN:-FALSE}" == "TRUE" ]]; then
        lib_info "DRY-RUN: skipping log error scan for '${svc}'"
        return 0
    fi
    tmpf=$(mktemp)
    docker compose --profile "${svc}" logs 2>/dev/null \
        | grep -E '(^|[[:space:]])(ORA-|SP2-|DBT-)' > "${tmpf}" || true
    local count
    count=$(wc -l < "${tmpf}" | tr -d ' ')
    if [[ "${count}" -gt 0 ]]; then
        lib_warn "found ${count} error line(s) in ${svc} logs:"
        cat "${tmpf}" >&2
        rm -f "${tmpf}"
        return 1
    fi
    lib_info "${svc} logs: no ORA-/SP2-/DBT- errors"
    rm -f "${tmpf}"
    return 0
}

# ------------------------------------------------------------------------------
# Function: reset_service
# Purpose.: Full reset of a compose service (down -v + remove data dir)
#           Requires --yes confirmation or FORCE_YES=TRUE
# Args....: $1  service name (e.g. odbencprod)
# Returns.: 0   success
# ------------------------------------------------------------------------------
reset_service() {
    local svc="$1"
    if [[ "${FORCE_YES:-FALSE}" != "TRUE" && "${DRY_RUN:-FALSE}" != "TRUE" ]]; then
        lib_warn "About to fully reset service '${svc}' - this destroys all data."
        read -rp "Confirm reset of '${svc}'? [y/N] " _reply
        [[ "${_reply}" == [yY] ]] || { lib_warn "reset of '${svc}' aborted by user"; return 1; }
    fi
    lib_info "resetting service '${svc}' ..."
    lib_run docker compose --profile "${svc}" down -v
    if [[ "${DRY_RUN:-FALSE}" != "TRUE" ]]; then
        local data_dir="${REPO_DIR}/data/${svc}"
        if [[ -d "${data_dir}" ]]; then
            lib_info "removing ${data_dir}"
            rm -rf "${data_dir}"
        fi

        # Restore the tracked skeleton. The image symlinks
        # /opt/oracle/network/admin (TNS_ADMIN) to /opt/oracle/dbconfig/FREE,
        # so that directory must exist before the container starts. Without it
        # the bind mount creates an empty dbconfig, the symlink dangles and DBCA
        # aborts with DBT-60127 in a restart loop. rm -rf above also removes the
        # tracked .gitkeep markers, so they have to come back.
        if git -C "${REPO_DIR}" rev-parse --git-dir >/dev/null 2>&1; then
            if git -C "${REPO_DIR}" restore "data/${svc}" 2>/dev/null; then
                lib_info "restored tracked files under data/${svc}"
            else
                lib_info "nothing tracked under data/${svc} to restore"
            fi
        fi
        mkdir -p "${data_dir}/dbconfig/FREE" "${data_dir}/logs"

        if [[ ! -d "${data_dir}/dbconfig/FREE" ]]; then
            lib_err "data/${svc}/dbconfig/FREE missing - the container would fail with DBT-60127"
            return 1
        fi
    else
        lib_info "DRY-RUN: would remove ${REPO_DIR}/data/${svc} and restore its tracked skeleton"
    fi
    lib_info "service '${svc}' reset complete"
}

# ------------------------------------------------------------------------------
# Function: start_service
# Purpose.: Start a compose service in the background
# Args....: $1  service name
# Returns.: 0   success
# ------------------------------------------------------------------------------
start_service() {
    local svc="$1"
    lib_info "starting service '${svc}' ..."
    lib_run docker compose --profile "${svc}" up -d
}

# ------------------------------------------------------------------------------
# Function: in_prod / in_dev
# Purpose.: Run a command in the prod or dev container
# Args....: $@  command
# Returns.: exit code of the command (0 in dry-run)
# ------------------------------------------------------------------------------
in_prod() {
    if [[ "${DRY_RUN:-FALSE}" == "TRUE" ]]; then
        lib_info "DRY-RUN [${PROD_SERVICE}]: $*"; return 0
    fi
    docker exec "${PROD_SERVICE}" bash -c "$*"
}

in_dev() {
    if [[ "${DRY_RUN:-FALSE}" == "TRUE" ]]; then
        lib_info "DRY-RUN [${DEV_SERVICE}]: $*"; return 0
    fi
    docker exec "${DEV_SERVICE}" bash -c "$*"
}

# ------------------------------------------------------------------------------
# Function: in_dev_stdin / in_prod_stdin
# Purpose.: Run a script inside a container without putting it on the command
#           line
# Args....: $*  the shell script to execute
# Returns.: the exit code of the script
# Output..: whatever the script writes
# Depends.: docker
# Example.: in_dev_stdin "sqlplus -S / as sysdba <<SQL ... SQL"
# Notes...: in_dev/in_prod pass the script to "docker exec bash -c" as an
#           argument, so it shows up in the host process list. Anything
#           carrying a password has to go through stdin instead - "ps" is
#           readable by every local user.
# ------------------------------------------------------------------------------
in_dev_stdin() {
    if [[ "${DRY_RUN:-FALSE}" == "TRUE" ]]; then
        lib_info "DRY-RUN [${DEV_SERVICE}]: (script via stdin)"; return 0
    fi
    printf '%s\n' "$*" | docker exec -i "${DEV_SERVICE}" bash -s
}

in_prod_stdin() {
    if [[ "${DRY_RUN:-FALSE}" == "TRUE" ]]; then
        lib_info "DRY-RUN [${PROD_SERVICE}]: (script via stdin)"; return 0
    fi
    printf '%s\n' "$*" | docker exec -i "${PROD_SERVICE}" bash -s
}

# ------------------------------------------------------------------------------
# Function: sqlplus_prod / sqlplus_dev
# Purpose.: Feed SQL to SQL*Plus as SYSDBA in the respective container
# Args....: $1  SQL text
# Returns.: exit code of SQL*Plus
# Output..: SQL*Plus output with password lines filtered out
# Notes...: The output is captured first and filtered afterwards. Piping
#           SQL*Plus straight into grep returns grep's exit status, so a
#           statement that failed under WHENEVER SQLERROR EXIT SQL.SQLCODE
#           looked like success, set -e never fired, and the step went on -
#           an ORA-28374 passed through unnoticed exactly this way.
# ------------------------------------------------------------------------------
sqlplus_prod() {
    local sql="$1"
    if [[ "${DRY_RUN:-FALSE}" == "TRUE" ]]; then
        echo "--- DRY-RUN [sqlplus prod] ---"
        printf '%s\n' "${sql}"
        echo "--- end ---"
        return 0
    fi
    local out rc=0
    # "|| rc=$?" is required: under set -e the shell exits at the assignment
    # itself when the command fails, so a plain "rc=$?" on the next line is
    # never reached and the output is lost. The "|| true" on grep is required
    # for the same reason - grep returns 1 when the filter matches nothing.
    out=$(printf '%s\n' "${sql}" | docker exec -i "${PROD_SERVICE}" sqlplus -S / as sysdba) || rc=$?
    printf '%s\n' "${out}" | grep -viE "identified by" || true
    return ${rc}
}

sqlplus_dev() {
    local sql="$1"
    if [[ "${DRY_RUN:-FALSE}" == "TRUE" ]]; then
        echo "--- DRY-RUN [sqlplus dev] ---"
        printf '%s\n' "${sql}"
        echo "--- end ---"
        return 0
    fi
    local out rc=0
    # "|| rc=$?" is required: under set -e the shell exits at the assignment
    # itself when the command fails, so a plain "rc=$?" on the next line is
    # never reached and the output is lost. The "|| true" on grep is required
    # for the same reason - grep returns 1 when the filter matches nothing.
    out=$(printf '%s\n' "${sql}" | docker exec -i "${DEV_SERVICE}" sqlplus -S / as sysdba) || rc=$?
    printf '%s\n' "${out}" | grep -viE "identified by" || true
    return ${rc}
}

# ------------------------------------------------------------------------------
# Function: rman_dev
# Purpose.: Feed RMAN commands to the dev container
# Args....: $1  RMAN script text
# Returns.: exit code of RMAN
# Output..: RMAN output
# ------------------------------------------------------------------------------
rman_dev() {
    local cmds="$1"
    if [[ "${DRY_RUN:-FALSE}" == "TRUE" ]]; then
        echo "--- DRY-RUN [rman dev] ---"
        printf '%s\n' "${cmds}"
        echo "--- end ---"
        return 0
    fi
    printf '%s\n' "${cmds}" | docker exec -i "${DEV_SERVICE}" rman target /
}

# ------------------------------------------------------------------------------
# Function: read_wallet_pwd
# Purpose.: Read the wallet password from inside the container without echoing
# Args....: $1  container name (prod or dev)
# Returns.: prints the password on stdout
# Output..: password value (caller must capture to a local variable)
# Note....: Never log the return value of this function
# ------------------------------------------------------------------------------
read_wallet_pwd() {
    local svc="$1"
    docker exec "${svc}" cat "${WALLET_DIR_CONTAINER}/wallet_pwd.txt" 2>/dev/null || true
}

# ------------------------------------------------------------------------------
# Function: get_dbid
# Purpose.: Query the DBID from a running container
# Args....: $1  container name
# Returns.: prints DBID on stdout
# ------------------------------------------------------------------------------
get_dbid() {
    local svc="$1"
    printf '%s\n' "SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 80 TRIMSPOOL ON
SELECT dbid FROM v\$database;
EXIT" \
    | docker exec -i "${svc}" sqlplus -S / as sysdba 2>/dev/null \
    | awk 'NF && $1 ~ /^[0-9]+$/ { print $1; exit }'
}

# ------------------------------------------------------------------------------
# Function: get_masterkeyid
# Purpose.: Query MASTERKEYID for a tablespace from a running container
# Args....: $1  container name
#           $2  PDB name
#           $3  tablespace name (default USERS)
# Returns.: prints MASTERKEYID hex on stdout
# ------------------------------------------------------------------------------
get_masterkeyid() {
    local svc="$1" pdb="$2" ts="${3:-USERS}"
    local _tmp
    _tmp="$(mktemp)"
    printf '%s\n' "SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 80 TRIMSPOOL ON
ALTER SESSION SET CONTAINER=${pdb};
SELECT RAWTOHEX(masterkeyid) FROM v\$encrypted_tablespaces WHERE ts# = (SELECT ts# FROM v\$tablespace WHERE name='${ts}' AND con_id=sys_context('userenv','con_id'));
EXIT" \
    | docker exec -i "${svc}" sqlplus -S / as sysdba 2>/dev/null \
    | awk 'NF && /^[0-9A-Fa-f]+$/ { print $1; exit }' > "${_tmp}"
    if [[ ! -s "${_tmp}" ]]; then
        # An empty result here is almost always a broken query, not an absent
        # key - v$encrypted_tablespaces has no NAME column, so a filter on it
        # fails with ORA-00904 and yields nothing. Silence would carry the
        # empty value into every later comparison.
        lib_err "MASTERKEYID query for ${ts} in ${pdb} returned nothing"
        lib_err "check the query in ${FUNCNAME[0]} - an empty value breaks every comparison"
        rm -f "${_tmp}"
        return 1
    fi
    cat "${_tmp}"
    rm -f "${_tmp}"
}

# ------------------------------------------------------------------------------
# Function: get_encryptedkey
# Purpose.: Query the wrapped TEK for a tablespace
# Args....: $1  container name
#           $2  PDB name
#           $3  tablespace name (default USERS)
# Returns.: prints wrapped TEK hex on stdout
# ------------------------------------------------------------------------------
get_encryptedkey() {
    local svc="$1" pdb="$2" ts="${3:-USERS}"
    local _tmp
    _tmp="$(mktemp)"
    printf '%s\n' "SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 200 TRIMSPOOL ON
ALTER SESSION SET CONTAINER=${pdb};
SELECT RAWTOHEX(encryptedkey) FROM v\$encrypted_tablespaces WHERE ts# = (SELECT ts# FROM v\$tablespace WHERE name='${ts}' AND con_id=sys_context('userenv','con_id'));
EXIT" \
    | docker exec -i "${svc}" sqlplus -S / as sysdba 2>/dev/null \
    | awk 'NF && /^[0-9A-Fa-f]+$/ { print $1; exit }' > "${_tmp}"
    if [[ ! -s "${_tmp}" ]]; then
        # An empty result here is almost always a broken query, not an absent
        # key - v$encrypted_tablespaces has no NAME column, so a filter on it
        # fails with ORA-00904 and yields nothing. Silence would carry the
        # empty value into every later comparison.
        lib_err "wrapped TEK query for ${ts} in ${pdb} returned nothing"
        lib_err "check the query in ${FUNCNAME[0]} - an empty value breaks every comparison"
        rm -f "${_tmp}"
        return 1
    fi
    cat "${_tmp}"
    rm -f "${_tmp}"
}

# ------------------------------------------------------------------------------
# State management
# ------------------------------------------------------------------------------

# write_state  key value
# Append or replace a KEY=VALUE line in the state file.
write_state() {
    local key="$1" value="$2"
    # A dry-run must not touch the state file the gates read. Otherwise a
    # dry-run leaves placeholder values behind, the gates look satisfied and a
    # later single step runs against an invented DBID.
    if [[ "${DRY_RUN:-FALSE}" == "TRUE" ]]; then
        lib_dbg "state (dry-run, not persisted): ${key}=${value}"
        return 0
    fi
    mkdir -p "$(dirname "${STATE_FILE}")"
    if [[ -f "${STATE_FILE}" ]]; then
        # Remove existing line for this key, then append
        local tmp
        tmp=$(mktemp)
        grep -v "^${key}=" "${STATE_FILE}" > "${tmp}" || true
        mv "${tmp}" "${STATE_FILE}"
    fi
    printf '%s=%s\n' "${key}" "${value}" >> "${STATE_FILE}"
    lib_dbg "state: ${key}=${value}"
}

# read_state  key  [default]
# Print the value for KEY from the state file.
read_state() {
    local key="$1" default="${2:-}"
    if [[ ! -f "${STATE_FILE}" ]]; then
        printf '%s\n' "${default}"
        return 0
    fi
    local val
    val=$(grep "^${key}=" "${STATE_FILE}" | tail -1 | cut -d= -f2-)
    printf '%s\n' "${val:-${default}}"
}

# require_state  key  description
# Abort if a required state key is missing or empty.
require_state() {
    local key="$1"
    local desc="${2:-${key}}"
    local val
    val=$(read_state "${key}")
    if [[ -z "${val}" ]]; then
        lib_err "required state value missing: ${key} (${desc})"
        lib_err "Run the prerequisite step first."
        exit 1
    fi
}

# ------------------------------------------------------------------------------
# Function: collect_evidence
# Purpose.: Collect a labelled evidence set via tde_evidence.sh
# Args....: $1  service name
#           $2  PDB name
#           $3  label
#           $4  tablespace (optional, default USERS)
# Returns.: 0   success (dry-run: prints command only)
# ------------------------------------------------------------------------------
collect_evidence() {
    local svc="$1" pdb="$2" label="$3" ts="${4:-USERS}"
    local extra_args=()
    [[ "${VERBOSE:-FALSE}" == "TRUE" ]] && extra_args+=("--verbose")

    if [[ "${DRY_RUN:-FALSE}" == "TRUE" ]]; then
        lib_info "DRY-RUN: would run: ${EVIDENCE_SCRIPT} --service ${svc} --pdb ${pdb} --label ${label} --tablespace ${ts} --marker ${CANARY_MARKER}"
        return 0
    fi

    lib_info "collecting evidence set '${label}' from ${svc}"
    "${EVIDENCE_SCRIPT}" \
        --service "${svc}" \
        --pdb "${pdb}" \
        --label "${label}" \
        --tablespace "${ts}" \
        --marker "${CANARY_MARKER}" \
        "${extra_args[@]}"
}

# ------------------------------------------------------------------------------
# Function: compare_evidence
# Purpose.: Compare two evidence sets via tde_evidence.sh
# Args....: $1  label_a
#           $2  label_b
# Returns.: 0   success (dry-run: prints command only)
# ------------------------------------------------------------------------------
compare_evidence() {
    local a="$1" b="$2"
    local extra_args=()
    [[ "${VERBOSE:-FALSE}" == "TRUE" ]] && extra_args+=("--verbose")

    if [[ "${DRY_RUN:-FALSE}" == "TRUE" ]]; then
        lib_info "DRY-RUN: would run: ${EVIDENCE_SCRIPT} --compare ${a} ${b}"
        return 0
    fi

    lib_info "comparing evidence sets '${a}' vs '${b}'"
    "${EVIDENCE_SCRIPT}" --compare "${a}" "${b}" "${extra_args[@]}"
}

# ------------------------------------------------------------------------------
# Function: print_verdict
# Purpose.: Print a final PASS/FAIL verdict with a message
# Args....: $1  PASS or FAIL
#           $2  message
# Returns.: 0   on PASS, 1 on FAIL
# ------------------------------------------------------------------------------
print_verdict() {
    local result="$1" msg="$2"
    echo ""
    echo "------------------------------------------------------------------------"
    echo "VERDICT: ${result} - ${msg}"
    echo "------------------------------------------------------------------------"
    [[ "${result}" == "PASS" ]]
}

# ------------------------------------------------------------------------------
# Function: print_key_summary
# Purpose.: Print a summary of key values for the current state
# Args....: $1  label
#           $2  MASTERKEYID
#           $3  wrapped TEK
#           $4  additional notes (optional)
# Returns.: 0
# ------------------------------------------------------------------------------
print_key_summary() {
    local label="$1" mkid="$2" tek="$3" notes="${4:-}"
    echo ""
    echo "Key summary for ${label}:"
    printf '  MASTERKEYID : %s\n' "${mkid}"
    printf '  Wrapped TEK : %s\n' "${tek}"
    if [[ -n "${notes}" ]]; then printf '  Notes       : %s\n' "${notes}"; fi
}

# --- EOF lib.sh ---------------------------------------------------------------

# ------------------------------------------------------------------------------
# Function: ensure_autologin_for
# Purpose.: Give a service its own auto-login keystore and verify it is open
# Args....: $1  container name
# Returns.: 0 keystore open, 1 otherwise
# Output..: the resulting v$encryption_wallet rows
# Depends.: docker, sqlplus
# Example.: ensure_autologin_for odbencdev
# Notes...: Any step that restarts the instance - OPEN RESETLOGS does, and so
#           does DUPLICATE - loses a keystore that was opened with a password.
#           A transported keystore also carries the source cwallet.sso, a LOCAL
#           auto-login file bound to its creating host, which does not open here
#           and blocks creating a new one with ORA-46630. Move the foreign one
#           aside, keep ewallet.p12, create the auto-login locally. PDB$SEED is
#           excluded from the check: its keystore is closed in normal operation.
# ------------------------------------------------------------------------------
ensure_autologin_for() {
    local svc="$1"
    if [[ "${DRY_RUN:-FALSE}" == "TRUE" ]]; then
        lib_info "DRY-RUN: would recreate the auto-login keystore in ${svc}"
        return 0
    fi
    if ! docker exec "${svc}" test -s /opt/oracle/dbconfig/FREE/wallet/wallet_pwd.txt; then
        lib_warn "no wallet_pwd.txt in ${svc} - cannot recreate the auto-login"
        return 0
    fi

    lib_info "recreating the auto-login keystore in ${svc}"
    docker exec -i "${svc}" bash -s <<'INNER' | grep -viE "identified by"
set -u
W="/opt/oracle/dbconfig/FREE/wallet"
XCH="/opt/oracle/xchange"
mkdir -p "${XCH}/sso_foreign"
mv "${W}"/tde/cwallet*.sso "${XCH}/sso_foreign/" 2>/dev/null || true
PW="$(cat "${W}/wallet_pwd.txt")"
sqlplus -S / as sysdba >/tmp/al.$$.log 2>&1 <<SQL
WHENEVER SQLERROR CONTINUE
SET LINESIZE 200 PAGESIZE 100 FEEDBACK OFF
ADMINISTER KEY MANAGEMENT SET KEYSTORE OPEN FORCE KEYSTORE IDENTIFIED BY "${PW}" CONTAINER=ALL;
ADMINISTER KEY MANAGEMENT CREATE LOCAL AUTO_LOGIN KEYSTORE FROM KEYSTORE '${W}/tde' IDENTIFIED BY "${PW}";
COLUMN status FORMAT A20
COLUMN wallet_type FORMAT A16
SELECT con_id, status, wallet_type FROM v\$encryption_wallet ORDER BY con_id;
EXIT
SQL
grep -viE "identified by" /tmp/al.$$.log
rm -f /tmp/al.$$.log
INNER

    local closed
    closed=$(printf '%s\n' "SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT COUNT(*) FROM v\$encryption_wallet w
WHERE w.status NOT IN ('OPEN','OPEN_NO_MASTER_KEY')
AND NOT EXISTS (SELECT 1 FROM v\$pdbs p WHERE p.con_id = w.con_id AND p.name = 'PDB\$SEED');
EXIT" | docker exec -i "${svc}" sqlplus -S / as sysdba 2>/dev/null \
        | awk 'NF && $1 ~ /^[0-9]+$/ { print $1; exit }')
    if [[ -z "${closed}" || "${closed}" != "0" ]]; then
        lib_err "keystore in ${svc} is not open after recreating the auto-login"
        return 1
    fi
    lib_info "keystore in ${svc} open via local auto-login"
}

# ------------------------------------------------------------------------------
# Function: compare_canary_blocks
# Purpose.: Compare only the blocks that actually carry canary rows
# Args....: $1  evidence label A
#           $2  evidence label B
#           $3  container holding the canary table
#           $4  PDB name
#           $5  table name, default CANARY_TDE
# Returns.: 0 canary blocks identical, 1 they differ, 2 could not determine
# Output..: "identical <n> differing <n> total <n>"
# Depends.: docker, sqlplus, python3
# Example.: compare_canary_blocks baseline variant_d odbencdev ODBENCPROD
# Notes...: The overall block counts are dominated by never used blocks, which
#           RMAN does not back up and writes fresh on restore - they differ in
#           every variant and say nothing about the key. The rows that matter
#           are the ones holding data. Identical ciphertext on identical data at
#           identical block addresses means the same tablespace key; the wrapped
#           key in v$encrypted_tablespaces cannot answer that, because it also
#           changes on a pure re-wrap after a master key rotation.
# ------------------------------------------------------------------------------
compare_canary_blocks() {
    local a="$1" b="$2" svc="$3" pdb="$4" tab="${5:-CANARY_TDE}"
    local blocks fp_a fp_b
    blocks=$(printf '%s\n' "
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 100 TRIMSPOOL ON
ALTER SESSION SET CONTAINER=${pdb};
SELECT DISTINCT dbms_rowid.rowid_block_number(rowid) FROM ${CANARY_OWNER:-SCOTT}.${tab} ORDER BY 1;
EXIT" | docker exec -i "${svc}" sqlplus -S / as sysdba 2>/dev/null \
        | awk 'NF && $1 ~ /^[0-9]+$/ { print $1 }')
    if [[ -z "${blocks}" ]]; then
        lib_err "could not determine the canary block numbers in ${svc}"
        return 2
    fi
    fp_a=$(find "${EVIDENCE_ROOT}/${a}" -maxdepth 1 -name '*.fp' 2>/dev/null | head -1)
    fp_b=$(find "${EVIDENCE_ROOT}/${b}" -maxdepth 1 -name '*.fp' 2>/dev/null | head -1)
    if [[ -z "${fp_a}" || -z "${fp_b}" ]]; then
        lib_err "missing fingerprint in evidence set ${a} or ${b}"
        return 2
    fi
    local blockfile
    blockfile=$(mktemp)
    printf '%s\n' "${blocks}" >"${blockfile}"
    python3 -c '
import sys, pathlib
def load(p):
    d = {}
    for line in pathlib.Path(p).read_text().splitlines():
        if line.startswith("#"):
            continue
        n, _, h = line.partition("\t")
        d[int(n)] = h
    return d
a, b = load(sys.argv[1]), load(sys.argv[2])
want = {int(x) for x in pathlib.Path(sys.argv[3]).read_text().split()}
common = want & set(a) & set(b)
diff = {n for n in common if a[n] != b[n]}
print("identical %d differing %d total %d" % (len(common) - len(diff), len(diff), len(common)))
sys.exit(1 if diff else 0)
' "${fp_a}" "${fp_b}" "${blockfile}"
    local rc=$?
    rm -f "${blockfile}"
    return ${rc}
}

# ------------------------------------------------------------------------------
# Function: ensure_omf
# Purpose.: Make sure db_create_file_dest is set so PDB creation works
# Args....: $1  container name
#           $2  OMF base directory, default /opt/oracle/oradata
# Returns.: 0 OMF available, 1 could not set it
# Output..: one line stating the value in effect
# Depends.: docker, sqlplus
# Example.: ensure_omf odbencprod
# Notes...: Neither db_create_file_dest nor pdb_file_name_convert is set in
#           this lab, so every CREATE PLUGGABLE DATABASE - from PDB$SEED,
#           FROM another PDB, or USING an archive - fails with ORA-65016,
#           "FILE_NAME_CONVERT must be specified". Setting OMF once covers all
#           of them and reproduces the path layout the lab already uses
#           (/opt/oracle/oradata/FREE/<GUID>/datafile/o1_mf_*). The repo's own
#           config/common/scripts/create_pdb.sql solves it per statement with
#           CREATE_FILE_DEST; one parameter is the smaller change here.
# ------------------------------------------------------------------------------
ensure_omf() {
    local svc="$1" base="${2:-/opt/oracle/oradata}"
    if [[ "${DRY_RUN:-FALSE}" == "TRUE" ]]; then
        lib_info "DRY-RUN: would ensure db_create_file_dest=${base} in ${svc}"
        return 0
    fi
    local current
    current=$(printf '%s\n' "
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 200 TRIMSPOOL ON
SELECT value FROM v\$parameter WHERE name = 'db_create_file_dest';
EXIT" | docker exec -i "${svc}" sqlplus -S / as sysdba 2>/dev/null | tr -d ' \t\r')
    if [[ "${current}" == "${base}" ]]; then
        lib_info "db_create_file_dest already ${base} in ${svc}"
        return 0
    fi
    printf '%s\n' "
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SYSTEM SET db_create_file_dest='${base}' SCOPE=BOTH;
EXIT" | docker exec -i "${svc}" sqlplus -S / as sysdba >/dev/null 2>&1 || {
        lib_err "could not set db_create_file_dest in ${svc}"
        return 1
    }
    lib_info "db_create_file_dest set to ${base} in ${svc}"
}
