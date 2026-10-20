#!/bin/bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: check_requirements.sh
# Author.....: Stefan Oehrli (oes), stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026.10.19
# Revision...: v1.2.0
# Purpose....: Pre-flight check before starting a lab service: container
#              runtime, compose, VM resources, image, .env, ports, the
#              JRE image for the assessment tools and the CIS-CAT archive.
# Notes......: - Read-only. Prints PASS / WARN / FAIL / SKIP per check, exit 1 on FAIL.
#              - Knows Docker Desktop, Colima and Podman (docker CLI).
#              - Never prints secret values, only whether they are set.
#              - Runs on macOS (bash 3.2) and Linux.
# Usage......: scripts/check_requirements.sh [-s SERVICE] [-h]
# Reference..: doc/container-runtime-runbook.md
# License....: Apache License Version 2.0, January 2004 as shown
#              at http://www.apache.org/licenses/
# ------------------------------------------------------------------------------
set -euo pipefail

readonly SCRIPT_NAME="${0##*/}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly SCRIPT_DIR
readonly REPO_ROOT="${SCRIPT_DIR%/*}"
readonly ENV_FILE="${REPO_ROOT}/.env"
# shellcheck source=scripts/lib_dotenv.sh
source "${SCRIPT_DIR}/lib_dotenv.sh"
# Measured on 23.26.3 arm64: seclab peaks at about 2.8 GiB during setup
readonly MIN_MEM_GIB=4
readonly REC_MEM_GIB=6
readonly MIN_CPU=2
readonly MIN_DISK_GIB=20

SERVICE=""
FAILS=0
WARNS=0

# ------------------------------------------------------------------------------
# Function...: usage
# Purpose....: Print usage and exit
# ------------------------------------------------------------------------------
usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [-s SERVICE] [-h]

Read-only pre-flight check for the lab. Exit 1 if any check FAILs.

  -s, --service NAME  Also check image, ports and variables of this service
                      (e.g. seclab, labdb)
  -h, --help          Show this help
EOF
    exit "${1:-0}"
}

pass() { echo "PASS  $*"; }
warn() { echo "WARN  $*"; WARNS=$((WARNS + 1)); }
fail() { echo "FAIL  $*"; FAILS=$((FAILS + 1)); }
skip() { echo "SKIP  $*"; }

# ------------------------------------------------------------------------------
# Function...: env_value
# Purpose....: Print the value of $1 from the environment, else from .env
# ------------------------------------------------------------------------------
env_value() {
    if [[ -n "${!1:-}" ]]; then
        echo "${!1}"
    else
        dotenv_value "$1" "${ENV_FILE}"
    fi
}

# ------------------------------------------------------------------------------
# Function...: check_runtime
# Purpose....: Docker CLI, engine, runtime flavour, compose, resources
# ------------------------------------------------------------------------------
check_runtime() {
    if ! command -v docker > /dev/null 2>&1; then
        fail "docker CLI not found (Docker Desktop, Colima + docker CLI, or Podman with docker alias)"
        return 0
    fi
    pass "docker CLI: $(command -v docker)"

    local info
    if ! info="$(docker info --format '{{.OperatingSystem}}|{{.Architecture}}|{{.NCPU}}|{{.MemTotal}}' 2> /dev/null)"; then
        fail "container engine not reachable - start Docker Desktop, 'colima start ...' or 'podman machine start'"
        return 0
    fi
    local os arch ncpu mem
    IFS='|' read -r os arch ncpu mem <<< "${info}"
    local context
    context="$(docker context show 2> /dev/null || echo unknown)"
    pass "engine: ${os}, context ${context}, architecture ${arch}"

    case "${arch}" in
        aarch64 | arm64 | x86_64 | amd64) pass "architecture ${arch} is supported by the Oracle Free image" ;;
        *) fail "architecture ${arch} - the Oracle Free image exists for amd64 and arm64 only" ;;
    esac

    if [[ "${context}" == colima* ]] && command -v colima > /dev/null 2>&1; then
        local profile="${context#colima}"
        profile="${profile#-}"
        profile="${profile:-default}"
        # Colima mounts only \$HOME by default. A bind mount from elsewhere ends
        # up as an empty directory inside the VM and DBCA fails (DBT-60127).
        # Test a file: Docker auto-creates missing bind sources as directories.
        if colima ssh -p "${profile}" -- test -f "${REPO_ROOT}/docker-compose.yml" > /dev/null 2>&1; then
            pass "repository is visible inside the Colima VM (bind mounts will work)"
        else
            fail "repository ${REPO_ROOT} is not mounted into the Colima VM - clone it below \$HOME or add it to mounts in ~/.colima/${profile}/colima.yaml"
        fi
        local status
        status="$(colima status -p "${profile}" 2>&1 || true)"
        case "${status}" in
            *"mountType: sshfs"* | *"mount type: sshfs"*)
                warn "Colima uses sshfs mounts - prefer 'colima start --vm-type vz --mount-type virtiofs'" ;;
            *virtiofs*) pass "Colima mount type virtiofs" ;;
            *) warn "Colima mount type not detected (colima status) - virtiofs recommended" ;;
        esac
    fi

    # MemTotal is what the VM kernel reports - a few hundred MiB below the
    # configured VM size. Thresholds therefore allow 10 percent.
    local mem_mib=$((mem / 1024 / 1024)) mem_txt
    mem_txt="$(awk -v m="${mem_mib}" 'BEGIN { printf "%.1f", m / 1024 }')"
    if [[ ${mem_mib} -lt $((MIN_MEM_GIB * 1024 * 9 / 10)) ]]; then
        fail "engine memory ${mem_txt} GiB < ${MIN_MEM_GIB} GiB (Colima: colima start --memory ${REC_MEM_GIB})"
    elif [[ ${mem_mib} -lt $((REC_MEM_GIB * 1024 * 9 / 10)) ]]; then
        warn "engine memory ${mem_txt} GiB - ${REC_MEM_GIB} GiB recommended for one DB plus headroom"
    else
        pass "engine memory ${mem_txt} GiB"
    fi
    if [[ ${ncpu} -lt ${MIN_CPU} ]]; then
        fail "engine CPUs ${ncpu} < ${MIN_CPU}"
    else
        pass "engine CPUs ${ncpu}"
    fi

    local compose
    if compose="$(docker compose version --short 2> /dev/null)"; then
        pass "docker compose plugin ${compose}"
    else
        fail "docker compose plugin missing (brew install docker-compose, then link it as CLI plugin)"
    fi

    local free_kib
    free_kib="$(df -Pk "${REPO_ROOT}" | awk 'NR==2 {print $4}')"
    if [[ $((free_kib / 1024 / 1024)) -lt ${MIN_DISK_GIB} ]]; then
        warn "free disk at ${REPO_ROOT}: $((free_kib / 1024 / 1024)) GiB < ${MIN_DISK_GIB} GiB (images ~13 GiB, data ~3 GiB per service)"
    else
        pass "free disk at ${REPO_ROOT}: $((free_kib / 1024 / 1024)) GiB"
    fi
}

# ------------------------------------------------------------------------------
# Function...: check_port
# Purpose....: Check that host port $1 is free (or used by service $2)
# ------------------------------------------------------------------------------
check_port() {
    local port="$1" svc="$2" owner
    owner="$(docker ps --filter "publish=${port}" --format '{{.Names}}' 2> /dev/null | head -1)"
    if [[ "${owner}" == "${svc}" ]]; then
        pass "port ${port} in use by the running ${svc} container"
    elif [[ -n "${owner}" ]]; then
        fail "port ${port} is published by container ${owner}"
    elif command -v nc > /dev/null 2>&1 && nc -z 127.0.0.1 "${port}" > /dev/null 2>&1; then
        fail "port ${port} on 127.0.0.1 is in use by another process"
    else
        pass "port ${port} is free"
    fi
}

# ------------------------------------------------------------------------------
# Function...: check_service
# Purpose....: .env, image, service variables and ports
# ------------------------------------------------------------------------------
check_service() {
    local svc="$1" upper
    upper="$(echo "${svc}" | tr '[:lower:]' '[:upper:]')"

    if [[ -f "${ENV_FILE}" ]]; then
        pass ".env present"
    else
        fail ".env missing - run: cp .env.example .env"
    fi

    local base tag image
    base="$(env_value DB_BASE_IMAGE)"
    base="${base:-container-registry.oracle.com/database/free:23.9.0.0}"
    tag="${base##*:}"
    image="$(env_value DB_IMAGE)"
    image="${image:-oracle-free-labs:${tag}}"
    if docker image inspect "${image}" > /dev/null 2>&1; then
        pass "image ${image} present ($(docker image inspect -f '{{.Architecture}}' "${image}"))"
    elif [[ "${svc}" == cdbfree ]]; then
        warn "image ${image} not present - pull or build it before 'make up-${svc}'"
    else
        fail "image ${image} not present - ${svc} needs the extended image: make build"
    fi
    if docker image inspect "${base}" > /dev/null 2>&1; then
        pass "base image ${base} present (offline build possible)"
    else
        warn "base image ${base} not pulled yet - 'docker pull ${base}' needs registry access"
    fi

    if [[ "${svc}" == seclab ]]; then
        local var
        for var in SECLAB_USER_PWD SECLAB_SCOTT_PWD SECLAB_DBSAT_PWD; do
            if [[ -n "$(env_value "${var}")" ]]; then
                pass "${var} is set"
            elif [[ "${var}" == SECLAB_DBSAT_PWD ]]; then
                warn "${var} not set - only needed for make dbsat-seclab"
            else
                fail "${var} not set - add it to .env (see .env.example)"
            fi
        done
        if [[ -n "$(ls "${REPO_ROOT}"/config/common/data/dbsat/dbsat*.zip 2> /dev/null)" ]]; then
            pass "DBSAT archive found in config/common/data/dbsat/"
        else
            warn "no DBSAT zip in config/common/data/dbsat/ - make dbsat-seclab will stop and explain"
        fi
    fi

    local lport oport
    lport="$(env_value "${upper}_LISTENER_PORT")"
    oport="$(env_value "${upper}_OEM_EXPRESS_PORT")"
    if [[ "${svc}" == seclab ]]; then
        lport="${lport:-1534}"
        oport="${oport:-5512}"
    fi
    if [[ -n "${lport}" ]]; then
        check_port "${lport}" "${svc}"
    fi
    if [[ -n "${oport}" ]]; then
        check_port "${oport}" "${svc}"
    fi
}

# ------------------------------------------------------------------------------
# Function...: check_assess_jre
# Purpose....: JRE image for DBSAT report (Java 17+) present and matching the
#              engine architecture - only for seclab or with a DBSAT zip, and
#              only with a reachable engine
# ------------------------------------------------------------------------------
check_assess_jre() {
    local image arch engine
    if [[ "${SERVICE}" != seclab ]] && ! compgen -G "${REPO_ROOT}/config/common/data/dbsat/dbsat*.zip" > /dev/null \
        && ! compgen -G "${REPO_ROOT}/config/common/data/ciscat/*[Cc][Ii][Ss]*[Cc][Aa][Tt]*.zip" > /dev/null; then
        skip "JRE image check - no DBSAT or CIS-CAT zip in config/common/data/ and SERVICE is not seclab"
        return 0
    fi
    if ! command -v docker > /dev/null 2>&1 || ! docker info > /dev/null 2>&1; then
        skip "JRE image check - container engine not reachable"
        return 0
    fi
    image="$(env_value ASSESS_JRE_IMAGE)"
    # keep in sync with Makefile ASSESS_JRE_IMAGE and scripts/provide_jre.sh
    image="${image:-eclipse-temurin:21-jre}"
    if ! arch="$(docker image inspect -f '{{.Architecture}}' "${image}" 2> /dev/null)"; then
        warn "JRE image ${image} not present - DBSAT report needs it (Java 17+); run: docker pull ${image}"
        return 0
    fi
    engine="$(docker info --format '{{.Architecture}}' 2> /dev/null || true)"
    case "${engine}" in
        aarch64) engine=arm64 ;;
        x86_64) engine=amd64 ;;
    esac
    if [[ -n "${engine}" && "${arch}" != "${engine}" ]]; then
        warn "JRE image ${image} is ${arch}, engine is ${engine} - run: docker pull --platform linux/${engine} ${image}"
    else
        pass "JRE image ${image} present (${arch}) - copied into the container for DBSAT report and CIS-CAT"
    fi
}

# ------------------------------------------------------------------------------
# Function...: check_ciscat
# Purpose....: CIS-CAT zip present? Edition guess and Oracle benchmarks inside
#              (unzip -l only, nothing is extracted)
# ------------------------------------------------------------------------------
check_ciscat() {
    local dir="${REPO_ROOT}/config/common/data/ciscat" zip="" f list licenses db os
    # keep in sync with ZIP_GLOB in config/common/scripts/run_ciscat.sh
    for f in "${dir}"/*[Cc][Ii][Ss]*[Cc][Aa][Tt]*.zip; do
        if [[ -L "${f}" && ! -e "${f}" ]]; then
            warn "CIS-CAT zip ${f##*/} is a dangling symlink"
        elif [[ -f "${f}" && "${f}" -nt "${zip:-/nonexistent}" ]]; then
            zip="${f}"
        fi
    done
    if [[ -z "${zip}" ]]; then
        if [[ "${SERVICE}" == seclab ]]; then
            warn "no CIS-CAT zip in config/common/data/ciscat/ - make ciscat-seclab will stop and explain"
        else
            skip "CIS-CAT check - no zip in config/common/data/ciscat/ (optional, see doc/ciscat-runbook.md)"
        fi
        return 0
    fi
    if ! command -v unzip > /dev/null 2>&1; then
        skip "CIS-CAT content check - unzip not found (archive ${zip##*/} present)"
        return 0
    fi
    if ! list="$(unzip -Z1 "${zip}" 2> /dev/null)"; then
        warn "CIS-CAT zip ${zip##*/} cannot be read by unzip - damaged download?"
        return 0
    fi
    licenses="$(grep -cE '/license/[^/]+$' <<< "${list}" || true)"
    db="$(grep -cE 'benchmarks/CIS_Oracle_Database_[^/]*-xccdf\.xml$' <<< "${list}" || true)"
    os="$(grep -cE 'benchmarks/CIS_Oracle_Linux_[^/]*-xccdf\.xml$' <<< "${list}" || true)"
    if [[ ${licenses} -eq 0 ]]; then
        pass "CIS-CAT archive ${zip##*/}: edition guess Lite (empty license directory)"
    else
        pass "CIS-CAT archive ${zip##*/}: edition guess Pro (${licenses} license file(s), not verified)"
    fi
    # Lite without Oracle benchmarks is the expected case - a WARN only matters for seclab
    if [[ ${licenses} -eq 0 && ${db} -eq 0 && ${os} -eq 0 && "${SERVICE}" != seclab ]]; then
        skip "CIS-CAT Oracle benchmarks - Lite: no Oracle benchmarks, Pro needed for DB (mechanics demo only)"
        return 0
    fi
    if [[ ${db} -gt 0 ]]; then
        pass "CIS-CAT: ${db} Oracle Database benchmark(s) inside"
    else
        warn "CIS-CAT: no Oracle Database benchmark inside - the database needs CIS-CAT Pro (make ciscat stops with exit 2)"
    fi
    if [[ ${os} -gt 0 ]]; then
        pass "CIS-CAT: ${os} Oracle Linux benchmark(s) inside"
    else
        warn "CIS-CAT: no Oracle Linux benchmark inside - only a mechanics demo is possible (see doc/ciscat-runbook.md)"
    fi
}

# ------------------------------------------------------------------------------
# Function...: main
# Purpose....: Run all checks and summarise
# ------------------------------------------------------------------------------
main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -s | --service) SERVICE="${2:?missing value for $1}"; shift 2 ;;
            -h | --help) usage 0 ;;
            *) echo "ERROR: unknown option $1" >&2; usage 1 ;;
        esac
    done

    echo "oracle-free-labs pre-flight check${SERVICE:+ for ${SERVICE}}"
    check_runtime
    if [[ -n "${SERVICE}" ]]; then
        check_service "${SERVICE}"
    fi
    check_assess_jre
    check_ciscat
    echo "Summary: ${FAILS} FAIL, ${WARNS} WARN"
    if [[ ${FAILS} -gt 0 ]]; then
        return 1
    fi
}

main "$@"
# - EOF ------------------------------------------------------------------------
