#!/bin/bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: run_dbsat.sh
# Author.....: Stefan Oehrli (oes), stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026.10.20
# Revision...: v1.2.0
# Purpose....: Run the Oracle Database Security Assessment Tool (DBSAT)
#              collector, reporter and sensitive data discovery inside a
#              lab container.
# Notes......: - DBSAT is NOT shipped with this repository (Oracle license).
#                Place the downloaded dbsat*.zip in config/common/data/dbsat/
#                on the host (= /opt/oracle/data/dbsat in the container).
#                Without it the script stops with exit 4 and says what to do.
#              - -m selects the steps: collect, report, discover or all,
#                comma separated. Default collect,report (as before v1.2.0).
#              - Collects as a dedicated account (create_dbsat_user.sql), not
#                as SYS. Password from an environment variable (-e). The
#                account is dropped and recreated unless --existing-user.
#              - The image has no zip binary: all steps run with -n (output
#                not encrypted), which DBSAT offers for this case.
#              - DBSAT 4.x report and discover need Java 17+. The image ships
#                JDK 11 in $ORACLE_HOME/jdk, which the launcher rejects.
#                JAVA_HOME is set to -j DIR, else to the first of $JAVA_HOME,
#                /opt/oracle/oradata/tools/jre21, /tmp/jre21 with Java 17+.
#                scripts/provide_jre.sh on the host copies a JRE 21 there
#                (the make dbsat* targets do this). Without Java 17+ the
#                collection still runs, then the script stops with exit 5
#                and names the command that provides Java.
#              - discover reads username and password from the console
#                (System.console()); without a terminal it fails with
#                "Unexpected error" only. The script runs it under script(1)
#                (pseudo terminal), waits for each prompt and answers it.
#                The password is masked in everything it prints. A second
#                prompt after the password means rejected credentials: the
#                run is stopped with exit 1. DISC_TIMEOUT (seconds, default
#                1800) limits the whole discover run.
#              - discover config is generated per run from the sample of the
#                archive (localhost:1521/SERVICE), the pattern files are
#                copied next to it (DBSAT resolves them relative to the
#                config). The category "IT Info - User Data" of the language
#                pattern files is added as High Risk.
#              - Refuses SYS, SYSTEM and PDBADMIN as DBSAT account (-u): the
#                account is dropped and recreated.
#              - Tables without optimizer statistics are skipped by discover
#                (MINROWS) without a message: the script names them before
#                the run (gather_missing_stats.sql), -g gathers them first.
#              - Output: <out-dir>/dbsat_<pdb>.json (collect), the reports
#                dbsat_<pdb>_report.{html,txt,xlsx,json} (report) and
#                dbsat_<pdb>_discover.{html,csv,json} plus
#                dbsat_<pdb>_discoverer.log (discover). Old files of the
#                same name are removed first and the removal is reported.
#              - Exit codes: 0 all selected steps done, 1 error, 4 no DBSAT
#                zip, 5 no Java 17+ for report/discover (a selected
#                collection is done).
# Usage......: run_dbsat.sh -s SERVICE [-m MODES] [options]
# Reference..: https://www.oracle.com/database/technologies/security/dbsat.html
# License....: Apache License Version 2.0, January 2004 as shown
#              at http://www.apache.org/licenses/
# ------------------------------------------------------------------------------
set -euo pipefail
# the password passes through variables: never trace this script
if [[ $- == *x* ]]; then
    echo "WARN: xtrace (set -x) is on - switched off, the script handles a password" >&2
    set +x
fi

readonly SCRIPT_NAME="${0##*/}"
readonly COMMON_DIR="${COMMON_SCRIPTS_DIR:-/opt/oracle/common/scripts}"
readonly DBSAT_URL="https://www.oracle.com/database/technologies/security/dbsat.html"
# keep in sync with MIN_JAVA in scripts/provide_jre.sh
readonly MIN_JAVA=17
# keep in sync with default_target in scripts/provide_jre.sh
readonly JRE_CANDIDATES="/opt/oracle/oradata/tools/jre21 /tmp/jre21"
# seconds to wait for each discover prompt (username, password)
readonly PROMPT_TIMEOUT=120
# seconds for the whole discover run (environment, default 30 minutes)
DISC_TIMEOUT="${DISC_TIMEOUT:-1800}"
# accounts never used as DBSAT account: they would be dropped and recreated
readonly PROTECTED_USERS="SYS SYSTEM PDBADMIN"
ZIP_DIR="/opt/oracle/data/dbsat"
OUT_DIR="/opt/oracle/oradata/dbsat"
WORK_DIR="/tmp/dbsat"
WORK_DISC=""
SERVICE=""
PDB=""
DBSAT_USER="DBSAT_USER"
PWD_VAR="DBSAT_PWD"
JAVA_DIR=""
JAVA_OK=false
JAVA_MAJOR=""
DRY_RUN=false
MODES="collect,report"
DO_COLLECT=false
DO_REPORT=false
DO_DISCOVER=false
EXISTING_USER=false
PATTERNS="sensitive.ini"
SCHEMA_SCOPE="ALL"
MINROWS=1
ORACLE_MAINT=false
EXCLUDE_FILE=""
GATHER_STATS=false
DISC_OUTPUT=""
DISC_CONF=""
DISC_REASON=""
DISC_RUNNING=""

# ------------------------------------------------------------------------------
# Function...: usage
# Purpose....: Print usage and exit
# ------------------------------------------------------------------------------
usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} -s SERVICE [options]

Run DBSAT collect, report and/or discover against a PDB of this container.

Options:
  -s, --service NAME  Listener service of the PDB (required)
  -p, --pdb PDB       PDB for the DBSAT account (default: SERVICE)
  -m, --mode LIST     Steps, comma separated: collect, report, discover, all
                      (default: ${MODES}; report alone reuses dbsat_<pdb>.json)
  -u, --user NAME     DBSAT account (default: ${DBSAT_USER})
  -e, --env VAR       Environment variable holding its password (default: ${PWD_VAR})
      --existing-user Use the account as it is - do not drop and recreate it
  -z, --zip-dir DIR   Directory with dbsat*.zip (default: ${ZIP_DIR})
  -o, --out-dir DIR   Output directory (default: ${OUT_DIR})
  -j, --java-home DIR Java ${MIN_JAVA}+ for dbsat report/discover (default: the first
                      of $(java_search_list) with Java ${MIN_JAVA}+)
  -n, --dry-run       Check prerequisites only, run nothing
  -h, --help          Show this help

Discover options (with -m discover or all):
  -P, --patterns LIST Pattern files, comma separated: names in Discover/conf of
                      the archive (sensitive_de.ini, ...) or absolute paths
                      (default: ${PATTERNS})
  -S, --schemas LIST  SCHEMA_SCOPE: ALL or e.g. SCOTT,TVD_HR (default: ${SCHEMA_SCOPE})
  -r, --minrows N     MINROWS: minimum NUM_ROWS of a table (default: ${MINROWS})
  -O, --oracle-maintained
                      Also scan Oracle-maintained and sample schemas (dbsat -o)
  -x, --exclude FILE  EXCLUSION_LIST_FILE: SCHEMA[.TABLE[.COLUMN]] per line
  -g, --gather-stats  Gather missing optimizer statistics in scope first (as
                      SYSDBA, GATHER EMPTY) - changes the database

Environment: DISC_TIMEOUT seconds for the whole discover run (default ${DISC_TIMEOUT})
SYS, SYSTEM and PDBADMIN are refused as DBSAT account (-u).

Exit codes: 0 done, 1 error, 4 no DBSAT zip, 5 no Java ${MIN_JAVA}+ for report/discover
EOF
    exit "${1:-0}"
}

# ------------------------------------------------------------------------------
# Function...: missing_dbsat
# Purpose....: Explain how to provide DBSAT, exit 4
# ------------------------------------------------------------------------------
missing_dbsat() {
    cat >&2 << EOF
ERROR: no dbsat*.zip found in ${ZIP_DIR}
       DBSAT is not part of this repository (Oracle license terms).
       1. Download DBSAT (Oracle account required): ${DBSAT_URL}
       2. Copy the zip on the host to: config/common/data/dbsat/
       3. Run again: make dbsat-seclab
EOF
    exit 4
}

# ------------------------------------------------------------------------------
# Function...: java_search_list
# Purpose....: Print the directories searched for Java, -j DIR if given
# ------------------------------------------------------------------------------
java_search_list() {
    if [[ -n "${JAVA_DIR}" ]]; then
        echo "${JAVA_DIR}"
    else
        echo "\$JAVA_HOME ${JRE_CANDIDATES}"
    fi
}

# ------------------------------------------------------------------------------
# Function...: java_steps
# Purpose....: Print the selected steps that need Java 17+ (report, discover)
# ------------------------------------------------------------------------------
java_steps() {
    local steps=""
    if [[ "${DO_REPORT}" == true ]]; then
        steps="report"
    fi
    if [[ "${DO_DISCOVER}" == true ]]; then
        steps="${steps:+${steps} and }discover"
    fi
    echo "${steps}"
}

# ------------------------------------------------------------------------------
# Function...: die_no_java
# Purpose....: Explain how to provide Java 17+, exit 5. $1 = collection file
#              written by this run, empty if none.
# ------------------------------------------------------------------------------
die_no_java() {
    local done_msg="nothing was run"
    if [[ -n "${1:-}" ]]; then
        done_msg="the collection is done: $1"
    fi
    cat >&2 << EOF
ERROR: Java ${MIN_JAVA}+ is needed for dbsat $(java_steps) - none found in: $(java_search_list)
       The image JDK (\$ORACLE_HOME/jdk, Java 11) is rejected by DBSAT 4.x,
       ${done_msg}.
       Provide a JRE 21 from the host, then run again:
         make dbsat-seclab | make dbsat-discover-seclab   # seclab service
         make dbsat CONTAINER=<name>                      # any container
         make dbsat-discover CONTAINER=<name>
         scripts/provide_jre.sh <container>               # JRE only, then rerun this script
EOF
    exit 5
}

# ------------------------------------------------------------------------------
# Function...: java_major
# Purpose....: Print the Java major version of $1/bin/java, empty if it fails
# Notes......: keep in sync with java_major in scripts/provide_jre.sh
# ------------------------------------------------------------------------------
java_major() {
    local out line ver
    out="$("$1/bin/java" -version 2>&1)" || true
    line="${out%%$'\n'*}"
    case "${line}" in
        *version*\"*\"*) ;;
        *) return 0 ;;
    esac
    ver="${line#*\"}"
    ver="${ver%%\"*}"
    ver="${ver#1.}"
    ver="${ver%%[.+-]*}"
    case "${ver}" in
        '' | *[!0-9]*) return 0 ;;
    esac
    echo "${ver}"
}

# ------------------------------------------------------------------------------
# Function...: resolve_java
# Purpose....: Export JAVA_HOME as the first candidate with Java 17+ and set
#              JAVA_OK; every rejected candidate is reported
# ------------------------------------------------------------------------------
resolve_java() {
    local candidates=() dir major
    if [[ -n "${JAVA_DIR}" ]]; then
        candidates=("${JAVA_DIR}")
    else
        # shellcheck disable=SC2206 # fixed list without whitespace in paths
        candidates=(${JAVA_HOME:-} ${JRE_CANDIDATES})
    fi
    for dir in "${candidates[@]}"; do
        if [[ ! -x "${dir}/bin/java" ]]; then
            echo "INFO: no java in ${dir} - skipped"
            continue
        fi
        major="$(java_major "${dir}")"
        if [[ -n "${major}" && ${major} -ge ${MIN_JAVA} ]]; then
            export JAVA_HOME="${dir}"
            JAVA_OK=true
            JAVA_MAJOR="${major}"
            echo "INFO: Java ${major} in ${dir} - JAVA_HOME for dbsat report/discover"
            return 0
        fi
        echo "INFO: Java ${major:-unknown} in ${dir} is older than ${MIN_JAVA} - skipped"
    done
    if [[ -n "$(java_steps)" ]]; then
        echo "WARN: no Java ${MIN_JAVA}+ found in $(java_search_list) - dbsat $(java_steps) cannot run (exit 5)"
    fi
}

# ------------------------------------------------------------------------------
# Function...: scrub_env
# Purpose....: Fill SCRUB_ENV with env -u options for every secret-like
#              variable. dbsat collect writes its process environment into
#              the collection JSON - ORACLE_PWD and the SECLAB_*_PWD values
#              would land there in clear text. The collector password goes
#              in on stdin, so DBSAT needs none of them.
# ------------------------------------------------------------------------------
scrub_env() {
    local v names=""
    SCRUB_ENV=()
    for v in $(compgen -e); do
        case "${v}" in
            PWD | OLDPWD) ;;
            *PWD* | *PASSW* | *SECRET* | *TOKEN*)
                SCRUB_ENV+=(-u "${v}")
                names+=" ${v}"
                ;;
        esac
    done
    echo "INFO: DBSAT runs without the secret-like variable(s):${names:- none}"
}

# ------------------------------------------------------------------------------
# Function...: check_prereqs
# Purpose....: Report the runtime prerequisites of DBSAT in this image
# ------------------------------------------------------------------------------
check_prereqs() {
    echo "INFO: python3: $(command -v python3 || echo none) - only DBSAT releases before 4.x report with it"
    resolve_java
    if command -v zip > /dev/null 2>&1; then
        echo "INFO: zip present - still using -n for a scriptable, unencrypted run"
    else
        echo "INFO: no zip binary in the image - all steps use -n (unencrypted output)"
    fi
    if ! command -v unzip > /dev/null 2>&1; then
        echo "ERROR: unzip not found - cannot extract DBSAT" >&2
        return 1
    fi
    if [[ "${DO_DISCOVER}" == true ]] && ! command -v script > /dev/null 2>&1; then
        echo "ERROR: script (util-linux) not found - dbsat discover needs a pseudo terminal for its prompts" >&2
        return 1
    fi
}

# ------------------------------------------------------------------------------
# Function...: parse_modes
# Purpose....: Turn the -m list into DO_COLLECT, DO_REPORT, DO_DISCOVER
# ------------------------------------------------------------------------------
parse_modes() {
    local list=() m
    IFS=',' read -r -a list <<< "${MODES}"
    for m in "${list[@]+"${list[@]}"}"; do
        case "${m}" in
            collect) DO_COLLECT=true ;;
            report) DO_REPORT=true ;;
            discover) DO_DISCOVER=true ;;
            all) DO_COLLECT=true; DO_REPORT=true; DO_DISCOVER=true ;;
            *)
                echo "ERROR: unknown mode '${m}' in -m ${MODES} (collect, report, discover, all)" >&2
                return 1
                ;;
        esac
    done
    if [[ "${DO_COLLECT}${DO_REPORT}${DO_DISCOVER}" == falsefalsefalse ]]; then
        echo "ERROR: -m '${MODES}' selects no step" >&2
        return 1
    fi
}

# ------------------------------------------------------------------------------
# Function...: check_discover_args
# Purpose....: Validate the discover options before anything runs
# ------------------------------------------------------------------------------
check_discover_args() {
    SCHEMA_SCOPE="${SCHEMA_SCOPE^^}"
    SCHEMA_SCOPE="${SCHEMA_SCOPE// /}"
    if [[ ! "${SCHEMA_SCOPE}" =~ ^[A-Z0-9_\$#]+(,[A-Z0-9_\$#]+)*$ ]]; then
        echo "ERROR: -S ${SCHEMA_SCOPE}: ALL or a comma separated list of schema names" >&2
        return 1
    fi
    if [[ ! "${MINROWS}" =~ ^[0-9]+$ ]]; then
        echo "ERROR: -r ${MINROWS}: MINROWS must be a number >= 0" >&2
        return 1
    fi
    if [[ ! "${DISC_TIMEOUT}" =~ ^[1-9][0-9]*$ ]]; then
        echo "ERROR: DISC_TIMEOUT=${DISC_TIMEOUT}: seconds, a number > 0" >&2
        return 1
    fi
    local list=() f seen=" "
    IFS=',' read -r -a list <<< "${PATTERNS}"
    if [[ ${#list[@]} -eq 0 ]]; then
        echo "ERROR: -P selects no pattern file" >&2
        return 1
    fi
    for f in "${list[@]}"; do
        if [[ ! "${f##*/}" =~ ^[A-Za-z0-9_.-]+\.ini$ ]]; then
            echo "ERROR: -P ${f}: pattern file name must end in .ini (letters, digits, _ . - only)" >&2
            return 1
        fi
        # all files are copied into one directory: a second one would overwrite the first
        if [[ "${seen}" == *" ${f##*/} "* ]]; then
            echo "ERROR: -P ${PATTERNS}: file name ${f##*/} given twice" >&2
            return 1
        fi
        seen+="${f##*/} "
        if [[ "${f}" == */* && ("${f}" != /* || ! -r "${f}") ]]; then
            echo "ERROR: -P ${f}: not an absolute path to a readable file" >&2
            return 1
        fi
    done
    if [[ -n "${EXCLUDE_FILE}" && ! -r "${EXCLUDE_FILE}" ]]; then
        echo "ERROR: -x ${EXCLUDE_FILE}: exclusion list not readable" >&2
        return 1
    fi
}

# ------------------------------------------------------------------------------
# Function...: remove_old
# Purpose....: Remove the existing output files given as arguments, report each
# ------------------------------------------------------------------------------
remove_old() {
    local old
    for old in "$@"; do
        if [[ -e "${old}" ]]; then
            rm -f "${old}"
            echo "INFO: removed previous output ${old}"
        fi
    done
}

# ------------------------------------------------------------------------------
# Function...: write_discover_config
# Purpose....: Generate the discover config DISC_CONF in directory $2 from the
#              sample of the archive ($1 = Discover directory)
# Notes......: SENSITIVE_PATTERN_FILES and EXCLUSION_LIST_FILE are resolved by
#              DBSAT relative to the config file: the files are copied there.
#              The sed values are checked in parse_args and check_discover_args
#              (no / or & possible). Every substituted key must exist in the
#              sample, else the sed would be a silent no-op.
# ------------------------------------------------------------------------------
write_discover_config() {
    local disc="$1" conf_dir="$2" list=() f names="" excl="" key
    local sample="${disc}/conf/sample_dbsat.config"
    local cat_it="IT Info - User Data"
    DISC_CONF="${conf_dir}/dbsat_discover.config"
    if [[ ! -r "${sample}" ]]; then
        echo "ERROR: ${sample} not found - archive layout not recognised" >&2
        return 1
    fi
    mkdir -p "${conf_dir}"
    IFS=',' read -r -a list <<< "${PATTERNS}"
    for f in "${list[@]}"; do
        if [[ "${f}" != */* ]]; then
            f="${disc}/conf/${f}"
        fi
        if [[ ! -r "${f}" ]]; then
            echo "ERROR: pattern file ${f} not found (available: $(cd "${disc}/conf" && echo sensitive*.ini))" >&2
            return 1
        fi
        cp "${f}" "${conf_dir}/"
        names="${names:+${names},}${f##*/}"
    done
    if [[ -n "${EXCLUDE_FILE}" ]]; then
        excl="dbsat_discover_exclude.txt"
        cp "${EXCLUDE_FILE}" "${conf_dir}/${excl}"
    fi
    sed -E \
        -e "s/^([[:space:]]*DB_HOSTNAME[[:space:]]*=).*/\1 localhost/" \
        -e "s/^([[:space:]]*DB_PORT[[:space:]]*=).*/\1 1521/" \
        -e "s/^([[:space:]]*DB_SERVICE_NAME[[:space:]]*=).*/\1 ${SERVICE}/" \
        -e "s/^([[:space:]]*SENSITIVE_PATTERN_FILES[[:space:]]*=).*/\1 ${names}/" \
        -e "s/^([[:space:]]*SCHEMA_SCOPE[[:space:]]*=).*/\1 ${SCHEMA_SCOPE}/" \
        -e "s/^([[:space:]]*MINROWS[[:space:]]*=).*/\1 ${MINROWS}/" \
        -e "s/^([[:space:]]*EXCLUSION_LIST_FILE[[:space:]]*=).*/\1 ${excl}/" \
        "${sample}" > "${DISC_CONF}"
    for key in DB_HOSTNAME DB_PORT DB_SERVICE_NAME SENSITIVE_PATTERN_FILES SCHEMA_SCOPE MINROWS EXCLUSION_LIST_FILE; do
        if ! grep -qE "^[[:space:]]*${key}[[:space:]]*=" "${DISC_CONF}"; then
            echo "ERROR: key ${key} not found in ${sample} - cannot set it, archive layout not recognised" >&2
            return 1
        fi
    done
    # the sample rates "IT Info - User IT Data" (sensitive.ini), the language
    # files use "IT Info - User Data"; DBSAT rejects a category without a level
    if ! grep -qE "^[[:space:]]*${cat_it}[[:space:]]*=" "${DISC_CONF}"; then
        printf '    %s = High Risk\n' "${cat_it}" >> "${DISC_CONF}"
        echo "INFO: category '${cat_it}' (language pattern files) added as High Risk, like 'IT Info - User IT Data'"
    fi
    echo "INFO: discover config ${DISC_CONF}: service ${SERVICE}, patterns ${names}," \
        "SCHEMA_SCOPE ${SCHEMA_SCOPE}, MINROWS ${MINROWS}, exclusion list ${EXCLUDE_FILE:-none}," \
        "Oracle-maintained schemas $([[ "${ORACLE_MAINT}" == true ]] && echo included || echo excluded)"
}

# ------------------------------------------------------------------------------
# Function...: stop_discover
# Purpose....: Terminate the running discover (DISC_RUNNING = pid of script):
#              the session under the pseudo terminal (timeout, launcher, java)
#              and the process group of script itself
# ------------------------------------------------------------------------------
stop_discover() {
    local pid="${DISC_RUNNING}" kid
    if [[ -z "${pid}" ]]; then
        return 0
    fi
    DISC_RUNNING=""
    # script forks one child that becomes session leader on the pty
    for kid in $(pgrep -P "${pid}" 2> /dev/null || true); do
        pkill -TERM -s "${kid}" 2> /dev/null || true
    done
    kill -TERM -- "-${pid}" 2> /dev/null || kill -TERM "${pid}" 2> /dev/null || true
}

# ------------------------------------------------------------------------------
# Function...: run_with_pty
# Purpose....: Run the command $@ under script(1) in WORK_DISC, answer the
#              username and password prompts of dbsat discover, print the
#              output with the password masked. Return the exit code.
# Notes......: Waits for each prompt (PROMPT_TIMEOUT) instead of a fixed
#              sleep. Reads one character at a time: a prompt ends without a
#              newline. Answers go out only after their prompt, when the
#              console has switched echo off for the password; the mask is a
#              second line of defence. A prompt after the password means
#              rejected credentials: stopped, rc 1. timeout(1) limits the run
#              to DISC_TIMEOUT. script runs in its own session (setsid), the
#              EXIT/INT/TERM trap stops it if this script ends first. Sets
#              DISC_OUTPUT (masked) and DISC_REASON (credentials, prompt,
#              timeout or empty).
# ------------------------------------------------------------------------------
run_with_pty() {
    local pw="${!PWD_VAR:-}" cmd c line="" state=user rc pid out_fd in_fd
    printf -v cmd '%q ' timeout -k 30 "${DISC_TIMEOUT}" "$@"
    DISC_OUTPUT=""
    DISC_REASON=""
    coproc DISC { cd "${WORK_DISC}" && exec env "${SCRUB_ENV[@]}" SHELL=/bin/bash setsid script -qec "${cmd% }" /dev/null 2>&1; }
    pid="${DISC_PID}"
    DISC_RUNNING="${pid}"
    trap 'stop_discover' EXIT
    trap 'stop_discover; exit 130' INT
    trap 'stop_discover; exit 143' TERM
    # duplicate the coproc pipes: bash closes DISC[] when the process ends
    exec {out_fd}<&"${DISC[0]}" {in_fd}>&"${DISC[1]}"
    while :; do
        rc=0
        if [[ "${state}" == answered ]]; then
            IFS= read -r -N 1 c <&"${out_fd}" || rc=$?
        else
            IFS= read -r -N 1 -t "${PROMPT_TIMEOUT}" c <&"${out_fd}" || rc=$?
        fi
        if [[ ${rc} -gt 128 ]]; then
            echo "ERROR: no '${state/pw/password}' prompt from dbsat discover within ${PROMPT_TIMEOUT}s - stopped" >&2
            DISC_REASON=prompt
            stop_discover
            break
        elif [[ ${rc} -ne 0 ]]; then
            break
        fi
        case "${c}" in
            $'\r') ;;
            $'\n')
                line="${line//"${pw}"/********}"
                echo "${line}"
                DISC_OUTPUT+="${line}"$'\n'
                line=""
                ;;
            *)
                line+="${c}"
                if [[ "${state}" == user && "${line}" == *"Enter username: " ]]; then
                    printf '%s\n' "${DBSAT_USER}" >&"${in_fd}"
                    state=pw
                elif [[ "${state}" == pw && "${line}" == *"Enter password: " ]]; then
                    printf '%s\n' "${pw}" >&"${in_fd}"
                    state=answered
                elif [[ "${state}" == answered && ("${line}" == *"Enter username: " || "${line}" == *"Enter password: ") ]]; then
                    DISC_REASON=credentials
                    stop_discover
                    break
                fi
                ;;
        esac
    done
    if [[ -n "${line}" ]]; then
        line="${line//"${pw}"/********}"
        echo "${line}"
        DISC_OUTPUT+="${line}"$'\n'
    fi
    exec {out_fd}<&- {in_fd}>&-
    rc=0
    wait "${pid}" || rc=$?
    DISC_RUNNING=""
    trap - EXIT INT TERM
    if [[ ${rc} -eq 124 ]]; then
        DISC_REASON=timeout
    fi
    if [[ -n "${DISC_REASON}" || ("${state}" != answered && ${rc} -eq 0) ]]; then
        rc=1
    fi
    return "${rc}"
}

# ------------------------------------------------------------------------------
# Function...: discover_failed
# Purpose....: Explain a failed discover run beyond "Unexpected error"
# ------------------------------------------------------------------------------
discover_failed() {
    local rc="$1" log="$2"
    echo "ERROR: dbsat discover failed (rc=${rc}) - DBSAT itself mostly says only 'Unexpected error'" >&2
    case "${DISC_REASON}" in
        credentials)
            echo "ERROR: ORA-01017-like: DBSAT prompted again after the password - wrong username or password" \
                "for ${DBSAT_USER} (password from ${PWD_VAR}), run stopped" >&2
            ;;
        timeout)
            echo "ERROR: dbsat discover did not finish within DISC_TIMEOUT=${DISC_TIMEOUT}s - stopped" >&2
            ;;
        prompt) ;;
        *)
            case "${DISC_OUTPUT}" in
                *ORA-01017*)
                    echo "ERROR: ORA-01017: wrong username or password for ${DBSAT_USER} (password from ${PWD_VAR})" >&2
                    ;;
                *ORA-28000*)
                    echo "ERROR: ORA-28000: account ${DBSAT_USER} is locked" >&2
                    ;;
                *ORA-12514* | *ORA-12541* | *ORA-12505*)
                    echo "ERROR: service ${SERVICE} not reachable on localhost:1521 - check -s and lsnrctl status" >&2
                    ;;
                *"Invalid schemas"*)
                    echo "ERROR: -S ${SCHEMA_SCOPE} names a schema that does not exist (see the WARN lines above)" >&2
                    ;;
                *"INI Error"* | *"not recognized"*)
                    echo "ERROR: DBSAT rejected the pattern files or the config - see the message above" >&2
                    ;;
                *)
                    echo "ERROR: check the credentials of ${DBSAT_USER} (${PWD_VAR}) and the service ${SERVICE};" >&2
                    echo "ERROR: discover reads its prompts from a terminal (System.console()) - without one it fails like this" >&2
                    ;;
            esac
            ;;
    esac
    echo "ERROR: discoverer log: ${log}" >&2
}

# ------------------------------------------------------------------------------
# Function...: discover_summary
# Purpose....: Count sensitive columns per object type, objects and schemas in
#              the discover JSON (one object per line, DBSAT 4.3)
# ------------------------------------------------------------------------------
discover_summary() {
    local json="$1" schemas="" n_schemas=0 tab_cols=0 n_tables=0 view_cols=0 n_views=0
    if [[ -f "${json}" ]]; then
        schemas="$(grep -o '"SCHEMA_NAME":"[^"]*"' "${json}" | cut -d'"' -f4 | sort -u | tr "\n" " " || true)"
        schemas="${schemas% }"
        n_schemas="$(wc -w <<< "${schemas}")"
        read -r tab_cols n_tables view_cols n_views < <(awk '
            match($0, /"SCHEMA_NAME":"[^"]*"/) {
                obj = substr($0, RSTART + 15, RLENGTH - 16)
                match($0, /"OBJECT_NAME":"[^"]*"/)
                obj = obj "." substr($0, RSTART + 15, RLENGTH - 16)
                if ($0 ~ /"OBJECT_TYPE":"View"/) { vc++; if (!(obj in v)) { v[obj]; nv++ } }
                else { tc++; if (!(obj in t)) { t[obj]; nt++ } }
            }
            END { print tc + 0, nt + 0, vc + 0, nv + 0 }' "${json}")
    fi
    echo "INFO: discover summary: ${tab_cols} sensitive column(s) in ${n_tables} table(s)," \
        "${view_cols} in ${n_views} view(s), ${n_schemas} schema(s): ${schemas:-none} - details in the HTML"
    if [[ $((tab_cols + view_cols)) -eq 0 ]]; then
        echo "INFO: no findings - check the statistics WARN lines above, -S, -r and -O"
    fi
}

# ------------------------------------------------------------------------------
# Function...: run_discover
# Purpose....: Statistics check, config, discover via pseudo terminal, summary
# ------------------------------------------------------------------------------
run_discover() {
    local dbsat="$1" name="$2" disc prefix log maint_flag=N rc=0
    disc="${dbsat%/*}/Discover"
    prefix="${OUT_DIR}/${name}"
    log="${OUT_DIR}/${name}_discoverer.log"
    WORK_DISC="${WORK_DIR}/discover"
    if [[ "${ORACLE_MAINT}" == true ]]; then
        maint_flag=Y
    fi

    # discover skips tables without statistics silently - name them first
    if [[ "${GATHER_STATS}" == true ]]; then
        echo "INFO: -g: gathering missing optimizer statistics in ${PDB} (scope ${SCHEMA_SCOPE})"
        "${COMMON_DIR}/run_sql_script.sh" -p "${PDB}" gather_missing_stats.sql "${SCHEMA_SCOPE}" GATHER "${maint_flag}"
    else
        echo "INFO: checking for tables without optimizer statistics in ${PDB} (scope ${SCHEMA_SCOPE})"
        "${COMMON_DIR}/run_sql_script.sh" -p "${PDB}" gather_missing_stats.sql "${SCHEMA_SCOPE}" REPORT "${maint_flag}"
    fi

    write_discover_config "${disc}" "${WORK_DIR}/discover-conf"
    remove_old "${prefix}_discover.html" "${prefix}_discover.csv" "${prefix}_discover.json" "${log}"
    mkdir -p "${WORK_DISC}"

    local args=(discover -n)
    if [[ "${ORACLE_MAINT}" == true ]]; then
        args+=(-o)
    fi
    args+=(-c "${DISC_CONF}" "${prefix}")
    echo "INFO: dbsat discover ${DBSAT_USER}@//localhost:1521/${SERVICE} (JAVA_HOME=${JAVA_HOME}, Java ${JAVA_MAJOR})"
    echo "INFO: prompts answered through a pseudo terminal (script), password masked, limit ${DISC_TIMEOUT}s"
    run_with_pty "${dbsat}" "${args[@]}" || rc=$?
    if [[ -f "${WORK_DISC}/discoverer.log" ]]; then
        mv -f "${WORK_DISC}/discoverer.log" "${log}"
    fi
    if [[ -f "${log}" ]] && grep -qF -- "${!PWD_VAR}" "${log}"; then
        echo "ERROR: the password of ${DBSAT_USER} appears in ${log} - remove the file, do not share it" >&2
        return 1
    fi
    if [[ ${rc} -ne 0 || ! -s "${prefix}_discover.html" ]]; then
        discover_failed "${rc}" "${log}"
        return 1
    fi
    discover_summary "${prefix}_discover.json"
}

# ------------------------------------------------------------------------------
# Function...: parse_args
# Purpose....: Parse command line arguments into globals and validate those
#              that end up in SQL, sed or the DBSAT config
# ------------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -s | --service) SERVICE="${2:?missing value for $1}"; shift 2 ;;
            -p | --pdb) PDB="${2:?missing value for $1}"; shift 2 ;;
            -m | --mode) MODES="${2:?missing value for $1}"; shift 2 ;;
            -u | --user) DBSAT_USER="${2:?missing value for $1}"; shift 2 ;;
            -e | --env) PWD_VAR="${2:?missing value for $1}"; shift 2 ;;
            --existing-user) EXISTING_USER=true; shift ;;
            -z | --zip-dir) ZIP_DIR="${2:?missing value for $1}"; shift 2 ;;
            -o | --out-dir) OUT_DIR="${2:?missing value for $1}"; shift 2 ;;
            -j | --java-home) JAVA_DIR="${2:?missing value for $1}"; shift 2 ;;
            -P | --patterns) PATTERNS="${2:?missing value for $1}"; shift 2 ;;
            -S | --schemas) SCHEMA_SCOPE="${2:?missing value for $1}"; shift 2 ;;
            -r | --minrows) MINROWS="${2:?missing value for $1}"; shift 2 ;;
            -O | --oracle-maintained) ORACLE_MAINT=true; shift ;;
            -x | --exclude) EXCLUDE_FILE="${2:?missing value for $1}"; shift 2 ;;
            -g | --gather-stats) GATHER_STATS=true; shift ;;
            -n | --dry-run) DRY_RUN=true; shift ;;
            -h | --help) usage 0 ;;
            *) echo "ERROR: unknown option $1" >&2; usage 1 ;;
        esac
    done
    if [[ -z "${SERVICE}" ]]; then
        echo "ERROR: -s SERVICE is required" >&2
        usage 1
    fi
    # SERVICE goes into the connect string and the sed of the discover config
    if [[ ! "${SERVICE}" =~ ^[A-Za-z0-9_.\$#-]+$ ]]; then
        echo "ERROR: -s ${SERVICE}: service name may contain letters, digits and _ . \$ # - only" >&2
        return 1
    fi
    # the account is dropped and recreated: never one of the built-in admins
    case " ${PROTECTED_USERS} " in
        *" ${DBSAT_USER^^} "*)
            echo "ERROR: -u ${DBSAT_USER}: refused - ${PROTECTED_USERS} are never used as DBSAT account" \
                "(it is dropped and recreated); use a dedicated account" >&2
            return 1
            ;;
    esac
    PDB="${PDB:-${SERVICE}}"
    parse_modes
    if [[ "${DO_DISCOVER}" == true ]]; then
        check_discover_args
    fi
}

# ------------------------------------------------------------------------------
# Function...: main
# Purpose....: Locate, extract, prepare the account, run the selected steps
# ------------------------------------------------------------------------------
main() {
    parse_args "$@"

    local zip="" f steps=""
    for f in "${ZIP_DIR}"/dbsat*.zip; do
        if [[ -f "${f}" && "${f}" -nt "${zip:-/nonexistent}" ]]; then
            zip="${f}"
        fi
    done
    if [[ -z "${zip}" ]]; then
        missing_dbsat
    fi
    [[ "${DO_COLLECT}" == true ]] && steps+=" collect"
    [[ "${DO_REPORT}" == true ]] && steps+=" report"
    [[ "${DO_DISCOVER}" == true ]] && steps+=" discover"
    echo "INFO: DBSAT archive ${zip}, steps:${steps}"
    check_prereqs

    local needs_db=false
    if [[ "${DO_COLLECT}" == true || "${DO_DISCOVER}" == true ]]; then
        needs_db=true
    fi
    if [[ "${needs_db}" == true && -z "${!PWD_VAR:-}" ]]; then
        echo "ERROR: ${PWD_VAR} is not set or empty (password of ${DBSAT_USER})" >&2
        return 1
    fi
    if [[ "${DRY_RUN}" == true ]]; then
        echo "INFO: dry run - prerequisites checked, nothing executed"
        return 0
    fi
    # without a collection there is nothing useful to do before Java is needed
    if [[ "${DO_COLLECT}" != true && "${JAVA_OK}" != true ]]; then
        die_no_java ""
    fi

    local name="dbsat_${PDB,,}"
    if [[ "${DO_REPORT}" == true && "${DO_COLLECT}" != true && ! -s "${OUT_DIR}/${name}.json" ]]; then
        echo "ERROR: -m report needs ${OUT_DIR}/${name}.json - run -m collect first" >&2
        return 1
    fi

    if [[ -e "${WORK_DIR}" ]]; then
        rm -rf "${WORK_DIR}"
        echo "INFO: removed previous extraction ${WORK_DIR}"
    fi
    # Plain Oracle image: no logs bind mount, run_sql_script.sh spools there
    export SQL_LOG_DIR="${SQL_LOG_DIR:-/opt/oracle/scripts/logs}"
    mkdir -p "${WORK_DIR}" "${OUT_DIR}" "${SQL_LOG_DIR}"
    unzip -q "${zip}" -d "${WORK_DIR}"
    # DBSAT 4.x extracts into a dbsat/ subdirectory, older releases flat
    local dbsat
    dbsat="$(find "${WORK_DIR}" -maxdepth 2 -name dbsat -type f | head -1)"
    if [[ -z "${dbsat}" ]]; then
        echo "ERROR: no dbsat launcher found in ${zip}" >&2
        return 1
    fi
    chmod +x "${dbsat}"
    echo "INFO: DBSAT extracted to ${WORK_DIR}, launcher ${dbsat}"

    if [[ "${needs_db}" == true ]]; then
        if [[ "${EXISTING_USER}" == true ]]; then
            echo "INFO: --existing-user: using ${DBSAT_USER} as it is (not recreated)"
        else
            "${COMMON_DIR}/run_sql_script.sh" -p "${PDB}" -e "${PWD_VAR}" create_dbsat_user.sql "${DBSAT_USER}"
        fi
    fi

    local rc=0
    scrub_env
    if [[ "${DO_COLLECT}" == true ]]; then
        remove_old "${OUT_DIR}/${name}.json"
        echo "INFO: dbsat collect ${DBSAT_USER}@//localhost:1521/${SERVICE}"
        (cd "${OUT_DIR}" && printf '%s\n' "${!PWD_VAR}" \
            | env "${SCRUB_ENV[@]}" "${dbsat}" collect -n "${DBSAT_USER}@//localhost:1521/${SERVICE}" "${OUT_DIR}/${name}") || rc=$?
        if [[ ${rc} -ne 0 || ! -s "${OUT_DIR}/${name}.json" ]]; then
            echo "ERROR: dbsat collect failed (rc=${rc}) or wrote no ${OUT_DIR}/${name}.json" >&2
            return 1
        fi
        if [[ "${JAVA_OK}" != true && -n "$(java_steps)" ]]; then
            die_no_java "${OUT_DIR}/${name}.json"
        fi
    fi

    if [[ "${DO_REPORT}" == true ]]; then
        remove_old "${OUT_DIR}/${name}"_report.*
        echo "INFO: dbsat report ${OUT_DIR}/${name} (JAVA_HOME=${JAVA_HOME}, Java ${JAVA_MAJOR})"
        (cd "${OUT_DIR}" && env "${SCRUB_ENV[@]}" "${dbsat}" report -n "${OUT_DIR}/${name}") || rc=$?
        if [[ ${rc} -ne 0 ]]; then
            echo "ERROR: dbsat report failed (rc=${rc})" >&2
            return 1
        fi
    fi

    if [[ "${DO_DISCOVER}" == true ]]; then
        run_discover "${dbsat}" "${name}"
    fi
    echo "INFO: DBSAT output in ${OUT_DIR}:"
    ls -l "${OUT_DIR}/${name}"*
}

main "$@"
# - EOF ------------------------------------------------------------------------
