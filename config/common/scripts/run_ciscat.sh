#!/bin/bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: run_ciscat.sh
# Author.....: Stefan Oehrli (oes), stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026.10.23
# Revision...: v1.1.0
# Purpose....: Run a CIS-CAT Assessor (Lite or Pro, one code path) locally
#              inside an Oracle Database Free container.
# Notes......: - CIS-CAT is NOT shipped with this repository (CIS license).
#                Place the downloaded zip in config/common/data/ciscat/ on the
#                host (= /opt/oracle/data/ciscat in the container). Without it
#                the script stops with exit 4 and names both download pages.
#              - Lite and Pro are expected to be the same binary (Pro
#                unverified); the edition follows from the license directory
#                (empty = Lite). Lite 4.67.0 has no Oracle Database and no
#                Oracle Linux benchmark and writes HTML only - measured
#                2026-10-19.
#              - Must run as root inside the target (docker exec -u 0): the
#                local session of the assessor fails otherwise.
#              - Needs Java 21 in a root-owned JRE (root must not run code
#                that oracle can change). The image ships JDK 11;
#                scripts/provide_jre.sh --owner root on the host copies a
#                root-owned JRE 21 to /root/.cache/jre21. The JRE must stay
#                OUTSIDE the assessor directory (integrity check), the bundled
#                Windows JRE is not extracted.
#              - The extraction cache WORK_DIR (default /root/.cache/ciscat,
#                parent root-owned, mode 700) is reused while the zip is
#                unchanged and every file in it is owned by root; otherwise it
#                is removed and extracted again - both reported.
#              - Every assessment runs from a generated -cfg XML (mktemp, 0600,
#                removed on exit, INT and TERM). DB mode (Pro, Oracle Database
#                benchmark) adds the JDBC URL and listener.ora as interactive
#                values - NOT VERIFIED, no Pro license available. The password
#                must not contain @ / " or whitespace (thin URL) and is masked
#                in the .log and every report file afterwards.
#              - Output: OUT_DIR/ciscat_<target>_<benchmark>.<fmt> plus a .log
#                with the full assessor output. Old files of the same name are
#                removed first and reported.
#              - Java, zip and environment helpers are shared with
#                run_dbsat.sh: lib_java.sh and lib_assess.sh, sourced from
#                the directory of this script.
#              - Exit codes: 0 done, 1 error, 2 no applicable or selected
#                benchmark, 3 assessed but platform mismatch (no valid result),
#                4 no CIS-CAT zip, 5 no Java 21, 111 invalid profile,
#                114 benchmark file not found, 116 not root.
# Usage......: run_ciscat.sh [options]
# Reference..: doc/ciscat-runbook.md
# License....: Apache License Version 2.0, January 2004 as shown
#              at http://www.apache.org/licenses/
# ------------------------------------------------------------------------------
set -euo pipefail

readonly SCRIPT_NAME="${0##*/}"
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LIB_DIR
# shellcheck source=config/common/scripts/lib_java.sh
source "${LIB_DIR}/lib_java.sh"
# shellcheck source=config/common/scripts/lib_assess.sh
source "${LIB_DIR}/lib_assess.sh"
readonly COMMON_DIR="${COMMON_SCRIPTS_DIR:-/opt/oracle/common/scripts}"
readonly PRO_URL="https://www.cisecurity.org/cybersecurity-tools/cis-cat-pro"
readonly LITE_URL="https://learn.cisecurity.org/cis-cat-lite"
readonly MIN_JAVA="${CISCAT_MIN_JAVA}"
# root-owned JRE only - keep in sync with default_target (--owner root) in
# scripts/provide_jre.sh
readonly JRE_CANDIDATES="/root/.cache/jre21"
# keep in sync with CISCAT_GLOB in scripts/lib_usecase.sh
readonly ZIP_GLOB="*[Cc][Ii][Ss]*[Cc][Aa][Tt]*.zip"
readonly FORMATS="html json csv txt"
ZIP_DIR="/opt/oracle/data/ciscat"
WORK_DIR="/root/.cache/ciscat"
OUT_DIR="/opt/oracle/oradata/ciscat"
JAVA_DIR=""
JAVA_BIN=""
TARGET_NAME=""
BENCHMARK="${CISCAT_BENCHMARK:-auto}"
PROFILE="${CISCAT_PROFILE:-}"
IGNORE_PLATFORM="${CISCAT_IGNORE_PLATFORM:-}"
XMX="${CISCAT_XMX:-1024M}"
SERVICE=""
DB_USER="CISCAT_USER"
PWD_VAR="CISCAT_PWD"
LIST_ONLY=false
DRY_RUN=false
ASSESSOR=""
EDITION=""
VERSION=""
BENCH_FILES=()
SELECTED=()
TMP_FILES=()
STAGING=""

# ------------------------------------------------------------------------------
# Function...: usage
# Purpose....: Print usage (to stderr on a non-zero exit code) and exit
# ------------------------------------------------------------------------------
usage() {
    local rc="${1:-0}"
    if [[ ${rc} -ne 0 ]]; then
        exec >&2
    fi
    cat << EOF
Usage: ${SCRIPT_NAME} [options]

Run CIS-CAT Lite or Pro locally in this container (as root).

Options:
  -b, --benchmark SEL   auto | part of a benchmark file name | path to an
                        *-xccdf.xml (env CISCAT_BENCHMARK, default auto:
                        Oracle Database 26ai > 23ai > 19c and Oracle Linux of
                        /etc/os-release - Pro only)
  -P, --profile NAME    Profile title or id (env CISCAT_PROFILE, default: the
                        first profile of the benchmark)
  -i, --ignore-platform Assess even if the benchmark does not fit this OS
                        (env CISCAT_IGNORE_PLATFORM=1) - result not meaningful
  -t, --target NAME     Name in the report prefix (default: hostname)
  -s, --service NAME    DB mode only: PDB service (default: \$ORACLE_PDB, else FREEPDB1)
  -u, --user NAME       DB mode only: assessment account (default: ${DB_USER})
  -e, --env VAR         DB mode only: variable with its password (default: ${PWD_VAR})
  -z, --zip-dir DIR     Directory with the CIS-CAT zip (default: ${ZIP_DIR})
  -w, --work-dir DIR    Extraction cache, name ciscat*, root-owned parent, apart
                        from the zip and out dirs (default: ${WORK_DIR})
  -o, --out-dir DIR     Report directory (default: ${OUT_DIR})
  -j, --java-home DIR   Root-owned Java ${MIN_JAVA}+ (default: first of \$JAVA_HOME ${JRE_CANDIDATES})
  -l, --list            Show edition, benchmarks, profiles and the auto choice
  -n, --dry-run         Check and select only, assess nothing
  -h, --help            Show this help

Exit codes: 0 done, 1 error, 2 no applicable/selected benchmark, 3 platform
mismatch (no valid result), 4 no zip, 5 no Java ${MIN_JAVA}, 111 invalid profile,
114 benchmark file not found, 116 not root
EOF
    exit "${rc}"
}

# ------------------------------------------------------------------------------
# Function...: cleanup
# Purpose....: Remove temporary files (generated -cfg XML, raw log) and an
#              unfinished staging directory (EXIT, INT, TERM)
# ------------------------------------------------------------------------------
cleanup() {
    local f
    for f in "${TMP_FILES[@]+"${TMP_FILES[@]}"}"; do
        rm -f -- "${f}"
    done
    if [[ -n "${STAGING}" ]]; then
        rm -rf -- "${STAGING}"
    fi
}

# ------------------------------------------------------------------------------
# Function...: missing_ciscat
# Purpose....: Explain how to provide CIS-CAT, exit 4
# ------------------------------------------------------------------------------
missing_ciscat() {
    local dangling="" name
    while IFS= read -r name; do
        dangling="${dangling} ${name}"
    done < <(dangling_links "${ZIP_DIR}" "${ZIP_GLOB}")
    cat >&2 << EOF
ERROR: no readable CIS-CAT zip (${ZIP_GLOB}) in ${ZIP_DIR}
       CIS-CAT is not part of this repository (CIS license terms).
       1. Download it:
          Lite (free, registration): ${LITE_URL}
          Pro  (CIS SecureSuite membership, CIS WorkBench): ${PRO_URL}
       2. Copy the zip on the host to: config/common/data/ciscat/
       3. Run again: make ciscat CONTAINER=<name>   (or make ciscat-seclab)
EOF
    if [[ -n "${dangling}" ]]; then
        echo "       Dangling symlink(s) in ${ZIP_DIR}:${dangling} - a host symlink is not visible" >&2
        echo "       through a bind mount; make ciscat copies the zip with docker cp -L." >&2
    fi
    exit 4
}

# ------------------------------------------------------------------------------
# Function...: find_java
# Purpose....: Set JAVA_BIN to the first root-owned candidate with Java 21+
#              (resolve_java -r of lib_java.sh reports every rejected one),
#              else exit 5
# ------------------------------------------------------------------------------
find_java() {
    if resolve_java -r "${MIN_JAVA}" "${JAVA_DIR}" "${JRE_CANDIDATES}"; then
        JAVA_BIN="${JAVA_FOUND_DIR}/bin/java"
        echo "INFO: Java ${JAVA_FOUND_MAJOR} in ${JAVA_FOUND_DIR}"
        return 0
    fi
    cat >&2 << EOF
ERROR: CIS-CAT needs a root-owned Java ${MIN_JAVA}+ - none usable in: ${JAVA_CANDIDATES}
       The image JDK (\$ORACLE_HOME/jdk, Java 11) is too old, the bundled JRE of
       the zip is for Windows, a JRE owned by oracle is refused (run as root).
       Provide a root-owned JRE 21 from the host, then run again:
         make ciscat CONTAINER=<name>
         scripts/provide_jre.sh --owner root --min-java ${MIN_JAVA} <container>
EOF
    exit 5
}

# ------------------------------------------------------------------------------
# Function...: validate_work_dir
# Purpose....: Refuse a WORK_DIR that is unsafe for rm -rf as root or that
#              overlaps ZIP_DIR or OUT_DIR
# ------------------------------------------------------------------------------
validate_work_dir() {
    local reason="" name dir
    case "${WORK_DIR}" in
        *..*) reason="must not contain '..'" ;;
        *[[:space:]]* | *\'* | *\"*) reason="must not contain whitespace or quotes" ;;
        /*/*) ;;
        *) reason="must be an absolute path below a directory" ;;
    esac
    if [[ -z "${reason}" && "${WORK_DIR##*/}" != ciscat* ]]; then
        reason="last path component must start with 'ciscat' (it is removed as root)"
    fi
    for name in ZIP_DIR OUT_DIR; do
        dir="${!name%/}"
        if [[ -z "${reason}" && ( "${dir}" == "${WORK_DIR}" || "${dir}/" == "${WORK_DIR}/"* \
            || "${WORK_DIR}/" == "${dir}/"* ) ]]; then
            reason="must not be, contain or lie inside ${name} (${dir}) - it is removed as root"
        fi
    done
    if [[ -n "${reason}" ]]; then
        echo "ERROR: work dir ${reason}, got '${WORK_DIR}' - refused" >&2
        exit 1
    fi
}

# ------------------------------------------------------------------------------
# Function...: find_zip
# Purpose....: Print the newest readable CIS-CAT zip in ZIP_DIR, exit 4 if none
# ------------------------------------------------------------------------------
find_zip() {
    local zip
    zip="$(newest_zip "${ZIP_DIR}" "${ZIP_GLOB}")"
    if [[ -z "${zip}" ]]; then
        missing_ciscat
    fi
    echo "${zip}"
}

# ------------------------------------------------------------------------------
# Function...: prepare_parent
# Purpose....: Create the parent of WORK_DIR (mode 700) if missing; refuse a
#              parent that is a symlink, not root-owned or group/world-writable
# ------------------------------------------------------------------------------
prepare_parent() {
    local parent="${WORK_DIR%/*}" mode
    if [[ ! -e "${parent}" ]]; then
        if [[ "${DRY_RUN}" == true ]]; then
            echo "DRY-RUN: would create ${parent} (root, mode 700)"
            return 0
        fi
        (umask 077 && mkdir -p -- "${parent}") || {
            echo "ERROR: cannot create ${parent}" >&2
            exit 1
        }
        echo "INFO: created ${parent} (root, mode 700)"
    fi
    mode="$(stat -c %a -- "${parent}")"
    if [[ -L "${parent}" || ! -d "${parent}" || "$(stat -c %U -- "${parent}")" != root \
        || $((8#${mode} & 8#022)) -ne 0 ]]; then
        echo "ERROR: parent of the work dir ${parent} must be a root-owned directory, no symlink," \
            "not group/world-writable (mode ${mode}) - refused; default: /root/.cache/ciscat" >&2
        exit 1
    fi
}

# ------------------------------------------------------------------------------
# Function...: cache_untrusted
# Purpose....: Print why an existing WORK_DIR must not be reused, empty if ok
# ------------------------------------------------------------------------------
cache_untrusted() {
    local bad
    if [[ -L "${WORK_DIR}" ]]; then
        echo "it is a symlink"
    elif [[ ! -d "${WORK_DIR}" ]]; then
        echo "it is not a directory"
    else
        bad="$(untrusted_file "${WORK_DIR}")"
        if [[ -n "${bad}" ]]; then
            echo "${bad} has owner $(stat -c %U -- "${bad}"), mode $(stat -c %a -- "${bad}")"
        fi
    fi
}

# ------------------------------------------------------------------------------
# Function...: extract_assessor
# Purpose....: Extract the zip without */jre/* into WORK_DIR or reuse a trusted
#              extraction of the same zip; set ASSESSOR
# ------------------------------------------------------------------------------
extract_assessor() {
    local zip="$1" marker="${WORK_DIR}/.ofl-source" stamp jar="" why=""
    stamp="$(stat -L -c '%n|%s|%Y' -- "${zip}")"
    prepare_parent
    if [[ -e "${WORK_DIR}" || -L "${WORK_DIR}" ]]; then
        why="$(cache_untrusted)"
        if [[ -n "${why}" ]]; then
            if [[ "${DRY_RUN}" == true ]]; then
                echo "DRY-RUN: would remove the untrusted cache ${WORK_DIR} (${why})"
            else
                rm -rf -- "${WORK_DIR}"
                echo "WARN: cache ${WORK_DIR} not trusted (${why}) - removed, extracting again"
            fi
        else
            jar="$(find "${WORK_DIR}" -maxdepth 2 -name Assessor-CLI.jar -type f | head -1)"
        fi
    fi
    if [[ -n "${jar}" && -f "${marker}" && "$(cat "${marker}")" == "${stamp}" ]]; then
        ASSESSOR="${jar%/*}"
        echo "INFO: reusing extraction ${ASSESSOR} (same zip: name, size, mtime; all files owned by root)"
        clean_stale_tmp
        return 0
    fi
    if [[ "${DRY_RUN}" == true ]]; then
        echo "DRY-RUN: would extract ${zip##*/} to ${WORK_DIR} (without */jre/*), about 180 MB"
        return 0
    fi
    if [[ -e "${WORK_DIR}" ]]; then
        rm -rf -- "${WORK_DIR}"
        echo "INFO: removed previous extraction ${WORK_DIR} (zip changed or extraction incomplete)"
    fi
    STAGING="${WORK_DIR}.staging"
    if [[ -e "${STAGING}" || -L "${STAGING}" ]]; then
        rm -rf -- "${STAGING}"
        echo "INFO: removed leftover ${STAGING} (interrupted extraction)"
    fi
    echo "INFO: extracting ${zip##*/} to ${WORK_DIR} (without the bundled Windows JRE)"
    mkdir -m 700 -- "${STAGING}"
    if ! unzip -q "${zip}" -d "${STAGING}" -x '*/jre/*'; then
        echo "ERROR: unzip of ${zip} failed (disk space? about 200 MB needed)" >&2
        exit 1
    fi
    mv -- "${STAGING}" "${WORK_DIR}"
    STAGING=""
    jar="$(find "${WORK_DIR}" -maxdepth 2 -name Assessor-CLI.jar -type f | head -1)"
    if [[ -z "${jar}" ]]; then
        echo "ERROR: no Assessor-CLI.jar in ${zip} - not a CIS-CAT Assessor v4 archive?" >&2
        exit 1
    fi
    ASSESSOR="${jar%/*}"
    echo "${stamp}" > "${marker}"
    echo "INFO: extracted to ${ASSESSOR}"
}

# ------------------------------------------------------------------------------
# Function...: clean_stale_tmp
# Purpose....: Remove cfg.* / raw.* left in WORK_DIR/tmp by a killed run
# ------------------------------------------------------------------------------
clean_stale_tmp() {
    local f n=0
    for f in "${WORK_DIR}"/tmp/cfg.* "${WORK_DIR}"/tmp/raw.*; do
        if [[ -f "${f}" ]]; then
            rm -f -- "${f}"
            n=$((n + 1))
        fi
    done
    if [[ ${n} -gt 0 ]]; then
        echo "INFO: removed ${n} stale cfg/raw file(s) of an earlier run from ${WORK_DIR}/tmp"
    fi
}

# ------------------------------------------------------------------------------
# Function...: detect_edition
# Purpose....: Set EDITION (license directory) and VERSION (jar manifest)
# ------------------------------------------------------------------------------
detect_edition() {
    local manifest licenses
    manifest="$(unzip -p "${ASSESSOR}/Assessor-CLI.jar" META-INF/MANIFEST.MF 2> /dev/null | tr -d '\r')" || true
    VERSION="$(sed -n 's/^Implementation-Version: *//p' <<< "${manifest}")"
    VERSION="${VERSION:-unknown}"
    licenses="$(find "${ASSESSOR}/license" -type f 2> /dev/null | wc -l)"
    if [[ ${licenses} -eq 0 ]]; then
        EDITION="Lite"
        echo "INFO: CIS-CAT ${EDITION} ${VERSION} (license directory empty - restricted to the Lite benchmarks)"
    else
        EDITION="Pro"
        echo "INFO: CIS-CAT ${EDITION} ${VERSION} (${licenses} file(s) in license/ - Pro assumed, not verified)"
    fi
}

# ------------------------------------------------------------------------------
# Function...: load_benchmarks
# Purpose....: Fill BENCH_FILES with the *-xccdf.xml files of the assessor
# ------------------------------------------------------------------------------
load_benchmarks() {
    local f
    BENCH_FILES=()
    for f in "${ASSESSOR}"/benchmarks/*-xccdf.xml; do
        if [[ -f "${f}" ]]; then
            BENCH_FILES+=("${f}")
        fi
    done
    if [[ ${#BENCH_FILES[@]} -eq 0 ]]; then
        echo "ERROR: no *-xccdf.xml in ${ASSESSOR}/benchmarks" >&2
        exit 1
    fi
}

# ------------------------------------------------------------------------------
# Function...: bench_name
# Purpose....: Print the benchmark file name without path and -xccdf.xml
# ------------------------------------------------------------------------------
bench_name() {
    local b="${1##*/}"
    echo "${b%-xccdf.xml}"
}

# ------------------------------------------------------------------------------
# Function...: bench_short
# Purpose....: Print a short lower-case name for the report prefix
#              (CIS_Ubuntu_Linux_24.04_LTS_Benchmark_v2.0.0 -> ubuntu_linux_24.04_lts)
# ------------------------------------------------------------------------------
bench_short() {
    local s
    s="$(bench_name "$1")"
    s="${s#CIS_}"
    s="${s%%_Benchmark*}"
    s="${s//[^A-Za-z0-9_.-]/_}"
    echo "${s,,}"
}

# ------------------------------------------------------------------------------
# Function...: profiles_of
# Purpose....: Print "title|id" per profile of XCCDF file $1 - the single
#              source for listing and checking profiles
# Notes......: RS=">" makes every start tag one record, so a <Profile> tag
#              spread over several lines still yields its id; entities
#              &lt; &gt; &quot; &apos; &amp; are decoded (&amp; last)
# ------------------------------------------------------------------------------
profiles_of() {
    awk '
        function dec(v) {
            gsub(/&lt;/, "<", v); gsub(/&gt;/, ">", v); gsub(/&quot;/, "\"", v)
            gsub(/&apos;/, "\047", v); gsub(/&amp;/, "\\&", v)
            return v
        }
        BEGIN { RS = ">" }
        p == 2 {
            t = $0; sub(/<.*/, "", t); gsub(/[ \t\r\n]+/, " ", t); sub(/^ /, "", t); sub(/ $/, "", t)
            print dec(t) "|" dec(id); p = 0; next
        }
        /<([A-Za-z0-9_-]+:)?Profile([ \t\r\n]|$)/ {
            id = ""
            if (match($0, /[ \t\r\n]id="[^"]*"/)) { id = substr($0, RSTART + 5, RLENGTH - 6) }
            p = 1; next
        }
        p == 1 && /<([A-Za-z0-9_-]+:)?title([ \t\r\n]|$)/ { p = 2 }' "$1"
}

# ------------------------------------------------------------------------------
# Function...: print_profiles
# Purpose....: Print the profiles of XCCDF file $1 as "title   (id)" lines
# ------------------------------------------------------------------------------
print_profiles() {
    local title id
    while IFS='|' read -r title id; do
        echo "         - ${title}   (${id})"
    done < <(profiles_of "$1")
}

# ------------------------------------------------------------------------------
# Function...: is_db_benchmark
# Purpose....: Succeed if $1 is an Oracle Database benchmark (DB mode)
# ------------------------------------------------------------------------------
is_db_benchmark() {
    case "$(bench_name "$1")" in
        *Oracle_Database*) return 0 ;;
        *) return 1 ;;
    esac
}

# ------------------------------------------------------------------------------
# Function...: os_pattern
# Purpose....: Print the benchmark name fragment matching /etc/os-release
#              (ol 8.10 -> Oracle_Linux_8_), empty if unknown
# ------------------------------------------------------------------------------
os_pattern() {
    local id="" ver="" major
    if [[ -r /etc/os-release ]]; then
        id="$(sed -n 's/^ID="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' /etc/os-release)"
        ver="$(sed -n 's/^VERSION_ID="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' /etc/os-release)"
    fi
    major="${ver%%.*}"
    case "${id}" in
        ol) echo "Oracle_Linux_${major}_" ;;
        rhel) echo "Red_Hat_Enterprise_Linux_${major}_" ;;
        ubuntu) echo "Ubuntu_Linux_${ver}_" ;;
        *) echo "" ;;
    esac
}

# ------------------------------------------------------------------------------
# Function...: os_label
# Purpose....: Print a readable OS name for messages (Oracle Linux 8)
# ------------------------------------------------------------------------------
os_label() {
    local os
    os="$(os_pattern)"
    os="${os%_}"
    os="${os//_/ }"
    echo "${os:-this OS}"
}

# ------------------------------------------------------------------------------
# Function...: newest_match
# Purpose....: Print the BENCH_FILES entry with the highest version whose name
#              matches glob $1, empty if none
# ------------------------------------------------------------------------------
newest_match() {
    local pattern="$1" f matches=()
    for f in "${BENCH_FILES[@]}"; do
        # shellcheck disable=SC2053 # glob match intended
        if [[ "$(bench_name "${f}")" == ${pattern} ]]; then
            matches+=("${f}")
        fi
    done
    if [[ ${#matches[@]} -gt 0 ]]; then
        printf '%s\n' "${matches[@]}" | sort -V | tail -1
    fi
}

# ------------------------------------------------------------------------------
# Function...: auto_choice
# Purpose....: Print the benchmarks auto selects, one per line: Oracle Linux
#              of this OS and Oracle Database 26ai > 23ai > 19c > any
# ------------------------------------------------------------------------------
auto_choice() {
    local os pattern f
    os="$(os_pattern)"
    case "${os}" in
        Oracle_Linux_*) newest_match "CIS_${os}*" ;;
    esac
    for pattern in "*Oracle_Database_26ai*" "*Oracle_Database_23ai*" "*Oracle_Database_19c*" "*Oracle_Database*"; do
        f="$(newest_match "${pattern}")"
        if [[ -n "${f}" ]]; then
            echo "${f}"
            return 0
        fi
    done
}

# ------------------------------------------------------------------------------
# Function...: print_benchmarks
# Purpose....: Print every benchmark with its profiles (to stdout or stderr)
# ------------------------------------------------------------------------------
print_benchmarks() {
    local f p
    echo "       Benchmarks in this ${EDITION} ${VERSION} archive (${#BENCH_FILES[@]}):"
    for f in "${BENCH_FILES[@]}"; do
        echo "         - $(bench_name "${f}")"
        while IFS='|' read -r p _; do
            echo "             profile: ${p}"
        done < <(profiles_of "${f}")
    done
}

# ------------------------------------------------------------------------------
# Function...: die_no_benchmark
# Purpose....: Explain why nothing can be assessed and how to go on, exit 2
# ------------------------------------------------------------------------------
die_no_benchmark() {
    local why="$1"
    {
        echo "ERROR: ${why}"
        print_benchmarks
        if [[ "${EDITION}" == Lite ]]; then
            echo "       CIS-CAT Lite has no Oracle Database and no Oracle Linux benchmark."
        fi
        echo "       The database (and Oracle Linux) needs CIS-CAT Pro - CIS SecureSuite"
        echo "       membership, download from CIS WorkBench: ${PRO_URL}"
        echo "       Choose another benchmark: CISCAT_BENCHMARK=<part of a name above>"
        echo "       Mechanics demo with Lite (score NOT meaningful on $(os_label)):"
        echo "         make ciscat CONTAINER=<name> CISCAT_BENCHMARK=ubuntu CISCAT_IGNORE_PLATFORM=1"
    } >&2
    exit 2
}

# ------------------------------------------------------------------------------
# Function...: select_benchmarks
# Purpose....: Fill SELECTED from BENCHMARK (auto, path or name part)
# ------------------------------------------------------------------------------
select_benchmarks() {
    local f name sel_lc matches=()
    SELECTED=()
    if [[ "${BENCHMARK}" == auto ]]; then
        while IFS= read -r f; do
            if [[ -n "${f}" ]]; then
                SELECTED+=("${f}")
            fi
        done < <(auto_choice)
        if [[ ${#SELECTED[@]} -eq 0 ]]; then
            die_no_benchmark "no applicable benchmark for this target in CIS-CAT ${EDITION} ${VERSION} (auto looks for Oracle Database 26ai/23ai/19c and $(os_label))"
        fi
        echo "INFO: auto selected: $(for f in "${SELECTED[@]}"; do printf '%s ' "$(bench_name "${f}")"; done)"
        return 0
    fi
    if [[ "${BENCHMARK}" == */* ]]; then
        if [[ ! -f "${BENCHMARK}" ]]; then
            echo "ERROR: benchmark file ${BENCHMARK} not found (exit 114)" >&2
            print_benchmarks >&2
            exit 114
        fi
        SELECTED=("${BENCHMARK}")
        echo "INFO: benchmark file ${BENCHMARK}"
        if [[ "${BENCHMARK}" != "${ASSESSOR}/benchmarks/"* ]]; then
            echo "WARN: ${BENCHMARK} is outside ${ASSESSOR}/benchmarks - Lite 4.67.0 then fails with a" \
                "NullPointerException in validateSignatureParametersSchema (measured 2026-10-20)"
        fi
        return 0
    fi
    sel_lc="${BENCHMARK,,}"
    for f in "${BENCH_FILES[@]}"; do
        name="$(bench_name "${f}")"
        if [[ "${name,,}" == *"${sel_lc}"* ]]; then
            matches+=("${f}")
        fi
    done
    case ${#matches[@]} in
        0) die_no_benchmark "CISCAT_BENCHMARK='${BENCHMARK}' matches no benchmark in CIS-CAT ${EDITION} ${VERSION}" ;;
        1) SELECTED=("${matches[0]}") ;;
        *)
            {
                echo "ERROR: CISCAT_BENCHMARK='${BENCHMARK}' matches ${#matches[@]} benchmarks - be more specific:"
                for f in "${matches[@]}"; do echo "         - $(bench_name "${f}")"; done
            } >&2
            exit 2
            ;;
    esac
    echo "INFO: selected benchmark $(bench_name "${SELECTED[0]}")"
}

# ------------------------------------------------------------------------------
# Function...: check_profile
# Purpose....: Fail fast (exit 111) if PROFILE is not a title or id of $1
# ------------------------------------------------------------------------------
check_profile() {
    local bench="$1" title id
    if [[ -z "${PROFILE}" ]]; then
        echo "INFO: no profile given - the assessor uses the first profile of $(bench_name "${bench}")"
        return 0
    fi
    while IFS='|' read -r title id; do
        if [[ "${PROFILE}" == "${title}" || "${PROFILE}" == "${id}" ]]; then
            echo "INFO: profile '${title}'"
            return 0
        fi
    done < <(profiles_of "${bench}")
    {
        echo "ERROR: profile '${PROFILE}' does not exist in $(bench_name "${bench}") (exit 111)"
        echo "       Valid profiles (CISCAT_PROFILE=<title>):"
        print_profiles "${bench}"
    } >&2
    exit 111
}

# ------------------------------------------------------------------------------
# Function...: xml_escape
# Purpose....: Print $1 with the XML special characters escaped
# ------------------------------------------------------------------------------
xml_escape() {
    local s="$1"
    s="${s//&/&amp;}"
    s="${s//</&lt;}"
    s="${s//>/&gt;}"
    s="${s//\"/&quot;}"
    echo "${s}"
}

# ------------------------------------------------------------------------------
# Function...: check_db_password
# Purpose....: DB mode: exit 1 unless PWD_VAR holds a password usable in the
#              thin URL user/password@//host (no @ / " or whitespace)
# ------------------------------------------------------------------------------
check_db_password() {
    local pwd="${!PWD_VAR:-}"
    if [[ -z "${pwd}" ]]; then
        echo "ERROR: ${PWD_VAR} is not set or empty (password of ${DB_USER}, DB mode)" >&2
        exit 1
    fi
    case "${pwd}" in
        *[@/\"[:space:]]*)
            echo "ERROR: the password in ${PWD_VAR} contains @, /, \" or whitespace - it would break the" \
                "JDBC thin URL ${DB_USER}/<pwd>@//host; choose another password for ${DB_USER}" >&2
            exit 1
            ;;
    esac
}

# ------------------------------------------------------------------------------
# Function...: prepare_db_account
# Purpose....: DB mode (Pro, NOT VERIFIED): create the least-privilege
#              assessment account with create_dbsat_user.sql as oracle
# ------------------------------------------------------------------------------
prepare_db_account() {
    echo "WARN: DB mode is NOT VERIFIED (no CIS-CAT Pro license available) - see doc/ciscat-runbook.md"
    echo "INFO: creating ${DB_USER} in ${SERVICE} with create_dbsat_user.sql (catalog read access, not SYS)"
    export SQL_LOG_DIR="${SQL_LOG_DIR:-/opt/oracle/scripts/logs}"
    if ! mkdir -p "${SQL_LOG_DIR}"; then
        echo "ERROR: cannot create the SQL log directory ${SQL_LOG_DIR}" >&2
        return 1
    fi
    chown oracle:oinstall "${SQL_LOG_DIR}" 2> /dev/null || true
    if ! runuser -u oracle -- "${COMMON_DIR}/run_sql_script.sh" -p "${SERVICE}" -e "${PWD_VAR}" \
        -l create_ciscat_user create_dbsat_user.sql "${DB_USER}"; then
        echo "ERROR: creating ${DB_USER} in ${SERVICE} failed (run_sql_script.sh as oracle," \
            "log create_ciscat_user in ${SQL_LOG_DIR})" >&2
        return 1
    fi
}

# ------------------------------------------------------------------------------
# Function...: write_cfg
# Purpose....: Write the -cfg XML for benchmark $1 to file $2 (created 0600
#              by mktemp, so no umask or chmod is needed)
# ------------------------------------------------------------------------------
write_cfg() {
    local bench="$1" cfg="$2" prefix="$3" profile_attr="" props="" values="" listener
    if [[ -n "${PROFILE}" ]]; then
        profile_attr=" profile=\"$(xml_escape "${PROFILE}")\""
    fi
    if [[ -n "${IGNORE_PLATFORM}" ]]; then
        props='
      <properties>
        <property name="ignore.platform.mismatch">true</property>
      </properties>'
    fi
    if is_db_benchmark "${bench}"; then
        listener="${TNS_ADMIN:-${ORACLE_HOME:-/opt/oracle/product}/network/admin}/listener.ora"
        if [[ ! -r "${listener}" ]]; then
            echo "WARN: ${listener} not readable - listener rules will not evaluate"
        fi
        values="
      <interactive_values>
        <value id=\"xccdf_org.cisecurity_value_jdbc.url\">$(xml_escape "jdbc:oracle:thin:${DB_USER}/${!PWD_VAR}@//localhost:1521/${SERVICE}")</value>
        <value id=\"xccdf_org.cisecurity_value_listener.ora\">$(xml_escape "${listener}")</value>
      </interactive_values>"
    fi
    cat > "${cfg}" << EOF || return 1
<?xml version="1.0" encoding="UTF-8"?>
<configuration xmlns="http://cisecurity.org/ccpa/config">
  <sessions test="false">
    <session id="local">
      <type>local</type>
      <tmp_path>${WORK_DIR}/tmp</tmp_path>
    </session>
  </sessions>
  <assessments quiet="false">
    <benchmark xccdf="$(xml_escape "${bench}")"${profile_attr} session-ref="local">${values}${props}
    </benchmark>
  </assessments>
  <reports html="true" json="true" csv="true" txt="true" no-timestamp="true">
    <reports_dir>$(xml_escape "${OUT_DIR}")</reports_dir>
    <reports_prefix>${prefix}</reports_prefix>
  </reports>
</configuration>
EOF
}

# ------------------------------------------------------------------------------
# Function...: mask_file
# Purpose....: Copy file $1 to $2 with the DB password (raw and XML-escaped)
#              replaced by ********; $1 may equal $2 (in-place via a temp file)
# Notes......: the password reaches awk through the environment, not argv
# ------------------------------------------------------------------------------
mask_file() {
    local src="$1" dst="$2" pwd="${!PWD_VAR:-}" tmp
    if [[ -z "${pwd}" ]]; then
        if [[ "${src}" != "${dst}" ]]; then
            cp -- "${src}" "${dst}" || return 1
        fi
        return 0
    fi
    tmp="$(mktemp "${dst}.mask.XXXXXX")" || return 1
    if ! OFL_MASK1="${pwd}" OFL_MASK2="$(xml_escape "${pwd}")" LC_ALL=C awk '
        function mask(s, p,    out, i) {
            out = ""
            while (p != "" && (i = index(s, p)) > 0) {
                out = out substr(s, 1, i - 1) "********"; s = substr(s, i + length(p))
            }
            return out s
        }
        { print mask(mask($0, ENVIRON["OFL_MASK1"]), ENVIRON["OFL_MASK2"]) }' "${src}" > "${tmp}"; then
        rm -f -- "${tmp}"
        return 1
    fi
    mv -- "${tmp}" "${dst}"
}

# ------------------------------------------------------------------------------
# Function...: mask_outputs
# Purpose....: Mask the DB password in the report files of prefix $1, then
#              WARN for every file that still contains it
# ------------------------------------------------------------------------------
mask_outputs() {
    local prefix="$1" pwd="${!PWD_VAR:-}" fmt f hit
    if [[ -z "${pwd}" ]]; then
        return 0
    fi
    for fmt in ${FORMATS}; do
        f="${OUT_DIR}/${prefix}.${fmt}"
        if [[ -f "${f}" ]]; then
            mask_file "${f}" "${f}" || return 1
        fi
    done
    # the patterns reach grep through a file descriptor, never as an argument
    while IFS= read -r hit; do
        echo "WARN: ${hit} still contains the password of ${DB_USER} - do not share it"
    done < <(printf '%s\n%s\n' "${pwd}" "$(xml_escape "${pwd}")" \
        | grep -lF -f /dev/stdin -- "${OUT_DIR}/${prefix}".* 2> /dev/null || true)
}

# ------------------------------------------------------------------------------
# Function...: log_value
# Purpose....: Print the value after "<label>:" from the assessor log $1
# ------------------------------------------------------------------------------
log_value() {
    sed -n "s/^ *$2: *//p" "$1" | tail -1
}

# ------------------------------------------------------------------------------
# Function...: report_outputs
# Purpose....: Name the report files that were written, chown them to oracle
#              and explain missing formats
# ------------------------------------------------------------------------------
report_outputs() {
    local prefix="$1" fmt f missing="" owner
    for fmt in ${FORMATS}; do
        f="${OUT_DIR}/${prefix}.${fmt}"
        if [[ -s "${f}" ]]; then
            chown oracle:oinstall "${f}" 2> /dev/null || true
            chmod 644 "${f}" || return 1
            echo "INFO: written ${f} ($(stat -c %s "${f}") bytes)"
        else
            missing="${missing} ${fmt}"
        fi
    done
    chown oracle:oinstall "${OUT_DIR}/${prefix}.log" 2> /dev/null || true
    chmod 644 "${OUT_DIR}/${prefix}.log" || return 1
    if [[ -n "${missing}" ]]; then
        if [[ "${EDITION}" == Lite ]]; then
            echo "INFO: not written:${missing} - requested, but CIS-CAT Lite writes HTML only (measured 4.67.0)"
        else
            echo "WARN: not written:${missing} - requested with html/json/csv/txt; check ${OUT_DIR}/${prefix}.log"
        fi
    fi
    owner="$(stat -c %U "${OUT_DIR}/${prefix}.log")"
    if [[ "${owner}" != oracle ]]; then
        echo "INFO: files stay owned by ${owner} (chown does not stick on Docker Desktop bind mounts) - mode 644, readable"
    fi
}

# ------------------------------------------------------------------------------
# Function...: run_assessment
# Purpose....: Assess benchmark $1, report the result; returns the exit code
# Notes......: called as "run_assessment ... || rc=$?", so set -e is off in
#              here - every step that can fail is checked explicitly
# ------------------------------------------------------------------------------
run_assessment() {
    local bench="$1" prefix cfg raw rc=0 old os
    prefix="ciscat_${TARGET_NAME}_$(bench_short "${bench}")"
    prefix="${prefix//[^A-Za-z0-9_.-]/_}"
    check_profile "${bench}"
    if is_db_benchmark "${bench}"; then
        SERVICE="${SERVICE:-${ORACLE_PDB:-FREEPDB1}}"
        echo "INFO: DB mode: $(bench_name "${bench}") against ${DB_USER}@//localhost:1521/${SERVICE}"
        check_db_password
    fi
    os="$(os_pattern)"
    if ! is_db_benchmark "${bench}" && [[ -n "${os}" && "$(bench_name "${bench}")" != *"${os}"* ]]; then
        echo "WARN: $(bench_name "${bench}") is not the benchmark for this OS ($(os_label), /etc/os-release)"
        if [[ -n "${IGNORE_PLATFORM}" ]]; then
            echo "WARN: CISCAT_IGNORE_PLATFORM is set: the platform check is OFF - the score is NOT a meaningful"
            echo "WARN: compliance result for this container, it only shows that the assessor works"
        fi
    fi
    if [[ "${DRY_RUN}" == true ]]; then
        echo "DRY-RUN: would assess $(bench_name "${bench}") -> ${OUT_DIR}/${prefix}.{${FORMATS// /,}}"
        return 0
    fi
    if is_db_benchmark "${bench}"; then
        prepare_db_account || return 1
    fi

    if ! mkdir -p "${OUT_DIR}" || ! (umask 077 && mkdir -p "${WORK_DIR}/tmp"); then
        echo "ERROR: cannot create ${OUT_DIR} or ${WORK_DIR}/tmp" >&2
        return 1
    fi
    for old in "${OUT_DIR}/${prefix}".* "${OUT_DIR}/${prefix}"-*; do
        if [[ -e "${old}" ]]; then
            if ! rm -f -- "${old}"; then
                echo "ERROR: cannot remove previous output ${old}" >&2
                return 1
            fi
            echo "INFO: removed previous output ${old}"
        fi
    done
    # mktemp creates the files with mode 0600 - the cfg may hold the DB password
    cfg="$(mktemp "${WORK_DIR}/tmp/cfg.XXXXXX")" || { echo "ERROR: mktemp in ${WORK_DIR}/tmp failed" >&2; return 1; }
    TMP_FILES+=("${cfg}")
    raw="$(mktemp "${WORK_DIR}/tmp/raw.XXXXXX")" || { echo "ERROR: mktemp in ${WORK_DIR}/tmp failed" >&2; return 1; }
    TMP_FILES+=("${raw}")
    if ! write_cfg "${bench}" "${cfg}" "${prefix}"; then
        echo "ERROR: cannot write the assessor configuration ${cfg}" >&2
        return 1
    fi

    # The assessor needs no secret from the environment (the DB password is in
    # the cfg file); drop secret-like variables so no OS check or log records
    # them - scrub_env of lib_assess.sh, same rule as run_dbsat.sh
    scrub_env
    echo "INFO: assessing $(bench_name "${bench}") (full output: ${OUT_DIR}/${prefix}.log, $((${#SCRUB_ENV[@]} / 2)) secret-like variable(s) removed from its environment)"
    (cd "${ASSESSOR}" && env "${SCRUB_ENV[@]}" "${JAVA_BIN}" "-Xmx${XMX}" -jar "${ASSESSOR}/Assessor-CLI.jar" -cfg "${cfg}") \
        > "${raw}" 2>&1 || rc=$?
    rm -f -- "${cfg}"
    local log="${OUT_DIR}/${prefix}.log"
    if ! mask_file "${raw}" "${log}"; then
        echo "ERROR: cannot write ${log}" >&2
        return 1
    fi
    rm -f -- "${raw}"
    if ! mask_outputs "${prefix}"; then
        echo "ERROR: masking the password in ${OUT_DIR}/${prefix}.* failed - do not share these files" >&2
        return 1
    fi

    grep -E "Selected (Checklist|Profile)" "${log}" | sed 's/^/INFO: /' || true
    if [[ ${rc} -eq 111 ]] || grep -q "invalid profile" "${log}"; then
        {
            echo "ERROR: the assessor rejected profile '${PROFILE}' (exit ${rc}, mapped to 111). Profiles:"
            print_profiles "${bench}"
        } >&2
        return 111
    fi
    if grep -q "restricted to Lite" "${log}"; then
        echo "ERROR: $(bench_name "${bench}") is not available in CIS-CAT Lite - it needs Pro: ${PRO_URL}" >&2
        return 2
    fi
    case "${rc}" in
        0) ;;
        114)
            echo "ERROR: the assessor cannot find ${bench} (exit 114)" >&2
            return 114
            ;;
        116)
            echo "ERROR: the assessor needs root (exit 116) - run with docker exec -u 0" >&2
            return 116
            ;;
        *)
            echo "ERROR: assessment failed (assessor exit ${rc}) - last lines of ${log}:" >&2
            grep -vE '^[[:space:]]+at ' "${log}" | tail -8 | sed 's/^/       /' >&2
            return 1
            ;;
    esac

    echo "INFO: result: pass $(log_value "${log}" "Total Pass"), fail $(log_value "${log}" "Total Fail")," \
        "error $(log_value "${log}" "Total Error"), unknown $(log_value "${log}" "Total Unknown")," \
        "not applicable $(log_value "${log}" "Total Not Applicable"), score $(log_value "${log}" "Total")"
    report_outputs "${prefix}" || return 1
    if grep -q "does not match the target platform" "${log}"; then
        echo "WARN: PLATFORM MISMATCH - the assessor says the benchmark does not match this target:" >&2
        echo "WARN: every rule is Not Applicable, the score of 0 is NOT a compliance result (exit 3)." >&2
        echo "WARN: Force it for a mechanics demo only: CISCAT_IGNORE_PLATFORM=1" >&2
        return 3
    fi
    if [[ -n "${IGNORE_PLATFORM}" ]] && ! is_db_benchmark "${bench}" \
        && [[ -n "${os}" && "$(bench_name "${bench}")" != *"${os}"* ]]; then
        echo "WARN: platform check was OFF - the score above is not meaningful for $(os_label)"
    fi
    return 0
}

# ------------------------------------------------------------------------------
# Function...: list_mode
# Purpose....: Print edition, benchmarks, profiles and what auto would pick
# ------------------------------------------------------------------------------
list_mode() {
    local f picked=""
    print_benchmarks
    while IFS= read -r f; do
        if [[ -n "${f}" ]]; then
            picked="${picked} $(bench_name "${f}")"
        fi
    done < <(auto_choice)
    echo "       auto (CISCAT_BENCHMARK=auto) would assess:${picked:- nothing - no Oracle Database or $(os_label) benchmark}"
    echo "INFO: titles as the assessor reports them (-l):"
    (cd "${ASSESSOR}" && "${JAVA_BIN}" -jar "${ASSESSOR}/Assessor-CLI.jar" -l 2>&1) \
        | sed -n 's/^ *\([0-9][0-9]*\. .*\)$/         \1/p' || true
}

# ------------------------------------------------------------------------------
# Function...: main
# Purpose....: Check, extract, detect, select, assess
# ------------------------------------------------------------------------------
main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -b | --benchmark) BENCHMARK="${2:?missing value for $1}"; shift 2 ;;
            -P | --profile) PROFILE="${2:?missing value for $1}"; shift 2 ;;
            -i | --ignore-platform) IGNORE_PLATFORM=1; shift ;;
            -t | --target) TARGET_NAME="${2:?missing value for $1}"; shift 2 ;;
            -s | --service) SERVICE="${2:?missing value for $1}"; shift 2 ;;
            -u | --user) DB_USER="${2:?missing value for $1}"; shift 2 ;;
            -e | --env) PWD_VAR="${2:?missing value for $1}"; shift 2 ;;
            -z | --zip-dir) ZIP_DIR="${2:?missing value for $1}"; shift 2 ;;
            -w | --work-dir) WORK_DIR="${2:?missing value for $1}"; shift 2 ;;
            -o | --out-dir) OUT_DIR="${2:?missing value for $1}"; shift 2 ;;
            -j | --java-home) JAVA_DIR="${2:?missing value for $1}"; shift 2 ;;
            -l | --list) LIST_ONLY=true; shift ;;
            -n | --dry-run) DRY_RUN=true; shift ;;
            -h | --help) usage 0 ;;
            *) echo "ERROR: unknown option $1" >&2; usage 1 ;;
        esac
    done
    case "${IGNORE_PLATFORM}" in
        '' | 0 | false | no) IGNORE_PLATFORM="" ;;
        *) IGNORE_PLATFORM=1 ;;
    esac
    BENCHMARK="${BENCHMARK:-auto}"
    WORK_DIR="${WORK_DIR%/}"
    TARGET_NAME="${TARGET_NAME:-$(hostname)}"

    if [[ "$(id -u)" -ne 0 ]]; then
        echo "ERROR: ${SCRIPT_NAME} must run as root in the container (docker exec -u 0 ...) - exit 116" >&2
        echo "       The local session of the assessor fails for other users." >&2
        exit 116
    fi
    validate_work_dir
    local zip
    zip="$(find_zip)"
    echo "INFO: CIS-CAT archive ${zip}"
    find_java
    if ! command -v unzip > /dev/null 2>&1; then
        echo "ERROR: unzip not found - cannot extract CIS-CAT" >&2
        exit 1
    fi
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    extract_assessor "${zip}"
    if [[ -z "${ASSESSOR}" ]]; then
        echo "INFO: dry run - stopped before extraction, benchmarks not listed"
        return 0
    fi
    detect_edition
    load_benchmarks
    if [[ "${LIST_ONLY}" == true ]]; then
        list_mode
        return 0
    fi
    select_benchmarks

    local bench rc=0 worst=0
    for bench in "${SELECTED[@]}"; do
        rc=0
        run_assessment "${bench}" || rc=$?
        if [[ ${rc} -ne 0 && ( ${worst} -eq 0 || ${worst} -eq 3 ) ]]; then
            worst=${rc}
        fi
    done
    if [[ "${DRY_RUN}" == true ]]; then
        echo "INFO: dry run - checked and selected, nothing assessed"
    elif [[ ${worst} -eq 0 || ${worst} -eq 3 ]]; then
        echo "INFO: CIS-CAT reports in ${OUT_DIR}:"
        ls -l "${OUT_DIR}"/ciscat_"${TARGET_NAME//[^A-Za-z0-9_.-]/_}"_* 2> /dev/null || true
    fi
    return "${worst}"
}

main "$@"
# - EOF ------------------------------------------------------------------------
