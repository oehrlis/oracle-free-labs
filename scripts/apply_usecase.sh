#!/bin/bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: apply_usecase.sh
# Author.....: Stefan Oehrli (oes), stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026.10.20
# Revision...: v1.2.0
# Purpose....: Apply a lab use case to ANY running Oracle Database Free
#              container - also one started directly from the Oracle image,
#              without this repository's compose file or build.
# Notes......: - Copies config/common/scripts into the container
#                (/opt/oracle/common/scripts) unless it is already bind-mounted,
#                waits until the database is open, then runs the use case
#                entry script with docker exec.
#              - Secrets are taken from the environment or from .env and
#                handed over as environment variables, never as arguments.
#              - Runs on macOS (bash 3.2) and Linux.
#              - Use cases: seclab, dbsat, dbsat-discover, ciscat, ciscat-list.
#              - dbsat and dbsat-discover provide a JRE 21 first
#                (scripts/provide_jre.sh, image ASSESS_JRE_IMAGE): DBSAT 4.x
#                report and discover need Java 17+. Arguments after -- go
#                to run_dbsat.sh (e.g. -- -g -S SCOTT); -s -z -o -e -j are
#                set here and rejected after --. DISC_TIMEOUT is passed on.
#              - ciscat copies the zip to a root-owned dir, provides a
#                root-owned JRE 21 (provide_jre.sh --owner root) and runs
#                run_ciscat.sh as root (docker exec -u 0), see doc/ciscat-runbook.md.
# Usage......: scripts/apply_usecase.sh [options] USECASE CONTAINER [-- ARGS]
# Reference..: doc/seclab-runbook.md
# License....: Apache License Version 2.0, January 2004 as shown
#              at http://www.apache.org/licenses/
# ------------------------------------------------------------------------------
set -euo pipefail

readonly SCRIPT_NAME="${0##*/}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly SCRIPT_DIR
readonly REPO_ROOT="${SCRIPT_DIR%/*}"
# shellcheck source=scripts/lib_dotenv.sh
source "${SCRIPT_DIR}/lib_dotenv.sh"
readonly TARGET_DIR="/opt/oracle/common/scripts"
readonly DBSAT_HOST_DIR="${REPO_ROOT}/config/common/data/dbsat"
readonly DBSAT_URL="https://www.oracle.com/database/technologies/security/dbsat.html"
readonly CISCAT_HOST_DIR="${REPO_ROOT}/config/common/data/ciscat"
# keep in sync with ZIP_GLOB in config/common/scripts/run_ciscat.sh
readonly CISCAT_GLOB="*[Cc][Ii][Ss]*[Cc][Aa][Tt]*.zip"

PDB=""
ENV_FILE="${REPO_ROOT}/.env"
EXTRA_ARGS=()
DBSAT_ARGS=()
ALLOW_PUBLIC=false
DRY_RUN=false
WAIT_SECONDS=900

# ------------------------------------------------------------------------------
# Function...: usage
# Purpose....: Print usage and exit
# ------------------------------------------------------------------------------
usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [options] USECASE CONTAINER [-- RUN_DBSAT_ARGS]

Apply a lab use case to a running Oracle Database Free container.

Use cases:
  seclab   INTENTIONALLY INSECURE security baseline S01-S11 + verification
           needs SECLAB_USER_PWD, SECLAB_SCOTT_PWD; restarts the instance once
  dbsat    DBSAT collect + report against the PDB, reports copied to
           data/dbsat/<container>/ on the host. Needs the DBSAT zip in
           config/common/data/dbsat/ and DBSAT_PWD (falls back to SECLAB_DBSAT_PWD).
           Copies a JRE 21 from the image ASSESS_JRE_IMAGE (default
           eclipse-temurin:21-jre) into the container for the report
  dbsat-discover
           DBSAT sensitive data discovery (run_dbsat.sh -m discover), same
           prerequisites as dbsat, results copied to data/dbsat/<container>/.
           Discover options after --, e.g. -- -g -S SCOTT,TVD_HR
           (see run_dbsat.sh -h; -g gathers missing statistics, changes the DB).
           -s -z -o -e -j are set by this script and rejected after --.
           DISC_TIMEOUT (seconds, default 1800) is passed on if set
  ciscat   CIS-CAT Lite or Pro, local assessment as root in the container,
           reports copied to data/ciscat/<container>/. Needs the CIS-CAT zip
           in config/common/data/ciscat/ (copied to a root-owned dir) and a
           root-owned JRE 21 (provide_jre.sh --owner root). Selection
           via CISCAT_BENCHMARK (auto|name part|path), CISCAT_PROFILE,
           CISCAT_IGNORE_PLATFORM=1; DB mode (Pro only, not verified) needs
           CISCAT_PWD (falls back to DBSAT_PWD, SECLAB_DBSAT_PWD)
  ciscat-list
           Edition, benchmarks, profiles and the auto choice of CIS-CAT

Options:
  -p, --pdb PDB          Target PDB (default: ORACLE_PDB of the container, else FREEPDB1)
      --no-restart       Pass --no-restart to the use case (seclab: S10 skipped)
  -f, --env-file FILE    Read missing variables from FILE (default: .env in the repo)
      --allow-public-ports
                         seclab only: run even if the container publishes ports
                         beyond 127.0.0.1 (not recommended)
  -w, --wait SECONDS     Wait for the database to open (default: ${WAIT_SECONDS})
  -n, --dry-run          Show what would happen, change nothing
  -h, --help             Show this help

Example (plain Oracle image):
  docker run -d --name free26ai -p 127.0.0.1:1521:1521 \\
    -e ORACLE_PWD=<pwd> container-registry.oracle.com/database/free:latest
  SECLAB_USER_PWD=<pwd> SECLAB_SCOTT_PWD=tiger ${SCRIPT_NAME} seclab free26ai
  DBSAT_PWD=<pwd> ${SCRIPT_NAME} dbsat free26ai
  DBSAT_PWD=<pwd> ${SCRIPT_NAME} dbsat-discover free26ai -- -g
  CISCAT_BENCHMARK=ubuntu CISCAT_IGNORE_PLATFORM=1 ${SCRIPT_NAME} ciscat free26ai
  # or: make ciscat CONTAINER=free26ai CISCAT_BENCHMARK=ubuntu CISCAT_IGNORE_PLATFORM=1
EOF
    exit "${1:-0}"
}

# ------------------------------------------------------------------------------
# Function...: env_from_file
# Purpose....: Export variable $1 from ENV_FILE if it is not set already
# ------------------------------------------------------------------------------
env_from_file() {
    local name="$1" value
    if [[ -n "${!name:-}" ]]; then
        return 0
    fi
    value="$(dotenv_value "${name}" "${ENV_FILE}")"
    if [[ -n "${value}" ]]; then
        export "${name}=${value}"
    fi
}

# ------------------------------------------------------------------------------
# Function...: check_ports
# Purpose....: Refuse an insecure use case on a container reachable from the LAN
# ------------------------------------------------------------------------------
check_ports() {
    local container="$1" bindings
    bindings="$(docker inspect -f '{{range $p, $b := .NetworkSettings.Ports}}{{range $b}}{{.HostIp}}:{{.HostPort}} {{end}}{{end}}' "${container}")"
    local b public=""
    for b in ${bindings}; do
        case "${b}" in
            127.0.0.1:* | "[::1]":* | ::1:*) ;;
            *) public="${public} ${b}" ;;
        esac
    done
    if [[ -z "${public}" ]]; then
        echo "INFO: published ports of ${container}: ${bindings:-none} (localhost only)"
        return 0
    fi
    if [[ "${ALLOW_PUBLIC}" == true ]]; then
        echo "WARN: ${container} publishes ports beyond localhost:${public} - continuing (--allow-public-ports)"
        return 0
    fi
    echo "ERROR: ${container} publishes ports beyond localhost:${public}" >&2
    echo "ERROR: an intentionally insecure database must not be reachable from the network." >&2
    echo "ERROR: recreate the container with -p 127.0.0.1:<port>:1521, or pass --allow-public-ports." >&2
    return 1
}

# ------------------------------------------------------------------------------
# Function...: wait_for_db
# Purpose....: Wait until checkDBStatus.sh of the image reports an open database
# ------------------------------------------------------------------------------
wait_for_db() {
    local container="$1" waited=0
    while ! docker exec "${container}" bash -c '"${ORACLE_BASE:-/opt/oracle}"/checkDBStatus.sh' > /dev/null 2>&1; do
        if [[ ${waited} -ge ${WAIT_SECONDS} ]]; then
            echo "ERROR: database in ${container} not open after ${WAIT_SECONDS}s (docker logs ${container})" >&2
            return 1
        fi
        if [[ $((waited % 60)) -eq 0 ]]; then
            echo "INFO: waiting for the database in ${container} to open (${waited}s)"
        fi
        sleep 10
        waited=$((waited + 10))
    done
    echo "INFO: database in ${container} is open"
}

# ------------------------------------------------------------------------------
# Function...: detect_pdb
# Purpose....: Set PDB to the only open user PDB, else to ORACLE_PDB if open
# ------------------------------------------------------------------------------
detect_pdb() {
    local container="$1" pdbs default
    pdbs="$(docker exec -i "${container}" bash -c '"${ORACLE_HOME}"/bin/sqlplus -s -L "/ as sysdba"' << 'SQL'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT name FROM v$pdbs WHERE name <> 'PDB$SEED' AND open_mode = 'READ WRITE' ORDER BY con_id;
EXIT
SQL
)"
    local list
    read -r -d '' -a list <<< "${pdbs}" || true
    pdbs="${list[*]+"${list[*]}"}"
    default="$(docker exec "${container}" bash -c 'echo "${ORACLE_PDB:-FREEPDB1}"')"
    default="$(echo "${default}" | tr '[:lower:]' '[:upper:]')"
    case "${pdbs}" in
        "")
            echo "ERROR: no open PDB found in ${container} - pass -p PDB" >&2
            return 1
            ;;
        *" "*)
            case " ${pdbs} " in
                *" ${default} "*) PDB="${default}" ;;
                *)
                    echo "ERROR: several open PDBs in ${container} (${pdbs}) - pass -p PDB" >&2
                    return 1
                    ;;
            esac
            ;;
        *) PDB="${pdbs}" ;;
    esac
    echo "INFO: open PDB(s) in ${container}: ${pdbs} - using ${PDB}"
}

# ------------------------------------------------------------------------------
# Function...: provide_scripts
# Purpose....: Make config/common/scripts available in the container
# ------------------------------------------------------------------------------
provide_scripts() {
    local container="$1" mounts
    mounts="$(docker inspect -f '{{range .Mounts}}{{.Destination}} {{end}}' "${container}")"
    case " ${mounts} " in
        *" ${TARGET_DIR} "*)
            echo "INFO: ${TARGET_DIR} is bind-mounted in ${container} - using it as is"
            return 0
            ;;
    esac
    if [[ "${DRY_RUN}" == true ]]; then
        echo "DRY-RUN: docker cp config/common/scripts -> ${container}:${TARGET_DIR}"
        return 0
    fi
    if docker exec "${container}" test -d "${TARGET_DIR}"; then
        docker exec -u root "${container}" rm -rf "${TARGET_DIR}"
        echo "INFO: removed previous copy ${container}:${TARGET_DIR}"
    fi
    docker exec -u root "${container}" mkdir -p "${TARGET_DIR%/*}"
    docker cp "${REPO_ROOT}/config/common/scripts" "${container}:${TARGET_DIR}"
    docker exec -u root "${container}" chown -R oracle:oinstall "${TARGET_DIR}"
    echo "INFO: copied config/common/scripts to ${container}:${TARGET_DIR}"
}

# ------------------------------------------------------------------------------
# Function...: check_dbsat_args
# Purpose....: Reject run_dbsat.sh arguments after -- that would override the
#              options this script sets itself (service, zip, output, password
#              variable, Java)
# ------------------------------------------------------------------------------
check_dbsat_args() {
    local arg
    for arg in "${DBSAT_ARGS[@]+"${DBSAT_ARGS[@]}"}"; do
        case "${arg}" in
            -s | --service | -z | --zip-dir | -o | --out-dir | -e | --env | -j | --java-home)
                echo "ERROR: ${arg} after -- is fixed by ${SCRIPT_NAME} (service, zip, output, password variable, Java)" \
                    "- use -p PDB for the target; output goes to data/dbsat/<container>/" >&2
                return 1
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# Function...: run_dbsat_usecase
# Purpose....: Provide the DBSAT zip, run run_dbsat.sh, copy the reports back.
#              $2 = use case: dbsat (collect + report) or dbsat-discover
# ------------------------------------------------------------------------------
run_dbsat_usecase() {
    local container="$1" usecase="$2" zip="" f zip_dir mounts mode_args=()
    if [[ "${usecase}" == dbsat-discover ]]; then
        mode_args=(-m discover)
    fi
    for f in "${DBSAT_HOST_DIR}"/dbsat*.zip; do
        if [[ -f "${f}" && "${f}" -nt "${zip:-/nonexistent}" ]]; then
            zip="${f}"
        fi
    done
    if [[ -z "${zip}" ]]; then
        echo "ERROR: no dbsat*.zip in ${DBSAT_HOST_DIR}" >&2
        echo "ERROR: DBSAT is not part of this repository (Oracle license terms)." >&2
        echo "ERROR: download it from ${DBSAT_URL}, copy the zip there and run again." >&2
        return 4
    fi
    echo "INFO: DBSAT archive ${zip}"

    mounts="$(docker inspect -f '{{range .Mounts}}{{.Destination}} {{end}}' "${container}")"
    case " ${mounts} " in
        *" /opt/oracle/data "*)
            zip_dir="/opt/oracle/data/dbsat"
            echo "INFO: using the bind-mounted ${zip_dir} of ${container}"
            ;;
        *)
            zip_dir="/tmp/dbsat-zip"
            if [[ "${DRY_RUN}" == true ]]; then
                echo "DRY-RUN: docker cp ${zip} -> ${container}:${zip_dir}/"
            else
                docker exec "${container}" bash -c 'rm -rf "$1" && mkdir -p "$1"' _ "${zip_dir}"
                docker cp -L "${zip}" "${container}:${zip_dir}/"
                echo "INFO: copied ${zip##*/} to ${container}:${zip_dir}/ (previous copy removed)"
            fi
            ;;
    esac

    # provide_jre.sh picks the target (persistent tools path on a bind-mounted
    # oradata, else /tmp), run_dbsat.sh finds it there without -j
    local jre_args=() rc=0
    if [[ "${DRY_RUN}" == true ]]; then
        jre_args=(--dry-run)
    fi
    "${SCRIPT_DIR}/provide_jre.sh" "${jre_args[@]+"${jre_args[@]}"}" "${container}" \
        || echo "WARN: no JRE 21 in ${container} (provide_jre.sh exit $?) - report/discover will stop with exit 5"

    local out_dir="/opt/oracle/oradata/dbsat" host_out="${REPO_ROOT}/data/dbsat/${container}"
    local run_args=(-s "${PDB}" -z "${zip_dir}" -o "${out_dir}" -e DBSAT_PWD
        "${mode_args[@]+"${mode_args[@]}"}" "${DBSAT_ARGS[@]+"${DBSAT_ARGS[@]}"}")
    # DISC_TIMEOUT (seconds for the whole discover run) is passed on if set
    local env_args=(-e DBSAT_PWD)
    if [[ -n "${DISC_TIMEOUT:-}" ]]; then
        env_args+=(-e DISC_TIMEOUT)
    fi
    if [[ "${DRY_RUN}" == true ]]; then
        echo "DRY-RUN: docker exec ${env_args[*]} ${container} ${TARGET_DIR}/run_dbsat.sh ${run_args[*]}"
        echo "DRY-RUN: docker cp ${container}:${out_dir}/. ${host_out}/"
        return 0
    fi
    docker exec "${env_args[@]}" "${container}" "${TARGET_DIR}/run_dbsat.sh" "${run_args[@]}" || rc=$?
    if [[ ${rc} -ne 0 && ${rc} -ne 5 ]]; then
        echo "ERROR: DBSAT run in ${container} failed (exit ${rc})" >&2
        return "${rc}"
    fi
    mkdir -p "${host_out}"
    docker cp "${container}:${out_dir}/." "${host_out}/"
    if [[ ${rc} -eq 5 ]]; then
        echo "ERROR: no Java 17+ in ${container} for report/discover (exit 5) - copied what exists to ${host_out}/" >&2
        ls -l "${host_out}"
        return 5
    fi
    echo "INFO: DBSAT results copied to ${host_out}/"
    ls -l "${host_out}"
}

# ------------------------------------------------------------------------------
# Function...: run_ciscat_usecase
# Purpose....: Provide scripts, the CIS-CAT zip and a JRE 21, run
#              run_ciscat.sh as root, copy the reports back (ciscat) or only
#              list edition and benchmarks (ciscat-list)
# ------------------------------------------------------------------------------
run_ciscat_usecase() {
    local mode="$1" container="$2" zip="" f zip_dir rc=0
    for f in "${CISCAT_HOST_DIR}"/${CISCAT_GLOB}; do
        if [[ -f "${f}" && "${f}" -nt "${zip:-/nonexistent}" ]]; then
            zip="${f}"
        fi
    done
    if [[ -z "${zip}" ]]; then
        echo "ERROR: no CIS-CAT zip (${CISCAT_GLOB}) in ${CISCAT_HOST_DIR}" >&2
        echo "ERROR: CIS-CAT is not part of this repository (CIS license terms). Download it:" >&2
        echo "ERROR:   Lite: https://learn.cisecurity.org/cis-cat-lite" >&2
        echo "ERROR:   Pro:  https://www.cisecurity.org/cybersecurity-tools/cis-cat-pro (CIS WorkBench)" >&2
        echo "ERROR: copy the zip there and run again." >&2
        return 4
    fi
    echo "INFO: CIS-CAT archive ${zip}"
    provide_scripts "${container}"
    if [[ "${DRY_RUN}" != true ]] && ! docker exec "${container}" test -x "${TARGET_DIR}/run_ciscat.sh"; then
        echo "ERROR: ${container}:${TARGET_DIR} has no run_ciscat.sh - the bind mount points to a checkout" >&2
        echo "ERROR: without it (other branch or worktree); recreate the container from this checkout" >&2
        return 1
    fi

    # run_ciscat.sh runs the zip content as root: always a fresh copy in a
    # root-owned 700 dir, never a bind-mounted file the container side may
    # change (docker cp -L also resolves a host symlink, keeps the mtime)
    zip_dir="/root/.cache/ciscat-zip"
    if [[ "${DRY_RUN}" == true ]]; then
        echo "DRY-RUN: docker cp -L ${zip} -> ${container}:${zip_dir}/ (root, mode 700)"
    else
        docker exec -u root "${container}" bash -c 'umask 077 && rm -rf -- "$1" && mkdir -p -- "$1"' _ "${zip_dir}"
        docker cp -L "${zip}" "${container}:${zip_dir}/"
        docker exec -u root "${container}" bash -c 'chown -R root:root -- "$1" && chmod 600 -- "$1"/*' _ "${zip_dir}"
        echo "INFO: copied ${zip##*/} to ${container}:${zip_dir}/ (root, mode 700, previous copy removed)"
    fi

    local jre_args=(--owner root --min-java 21)
    if [[ "${DRY_RUN}" == true ]]; then
        jre_args+=(--dry-run)
    fi
    "${SCRIPT_DIR}/provide_jre.sh" "${jre_args[@]}" "${container}" || rc=$?
    if [[ ${rc} -ne 0 ]]; then
        echo "ERROR: no root-owned JRE 21 in ${container} (provide_jre.sh exit ${rc}) - CIS-CAT cannot run (exit 5)" >&2
        return 5
    fi

    local var env_args=() run_args=(-z "${zip_dir}" -t "${container}")
    for var in CISCAT_BENCHMARK CISCAT_PROFILE CISCAT_IGNORE_PLATFORM CISCAT_XMX; do
        env_from_file "${var}"
        if [[ -n "${!var:-}" ]]; then
            env_args+=(-e "${var}")
        fi
    done
    # the DB password only for an assessment, never for the listing
    if [[ "${mode}" == ciscat ]]; then
        env_from_file CISCAT_PWD
        for var in DBSAT_PWD SECLAB_DBSAT_PWD; do
            if [[ -z "${CISCAT_PWD:-}" ]]; then
                env_from_file "${var}"
                if [[ -n "${!var:-}" ]]; then
                    export CISCAT_PWD="${!var}"
                    echo "INFO: CISCAT_PWD not set - using ${var} (DB mode only)"
                fi
            fi
        done
        if [[ -n "${CISCAT_PWD:-}" ]]; then
            env_args+=(-e CISCAT_PWD)
        fi
    fi
    if [[ -n "${PDB}" ]]; then
        run_args+=(-s "${PDB}")
    fi
    if [[ "${mode}" == ciscat-list ]]; then
        run_args+=(--list)
    fi
    local out_dir="/opt/oracle/oradata/ciscat" host_out="${REPO_ROOT}/data/ciscat/${container}"
    if [[ "${DRY_RUN}" == true ]]; then
        echo "DRY-RUN: docker exec -u 0 ${env_args[*]+"${env_args[*]}"} ${container} ${TARGET_DIR}/run_ciscat.sh ${run_args[*]} -o ${out_dir}"
        echo "DRY-RUN: docker cp ${container}:${out_dir}/. ${host_out}/"
        return 0
    fi
    rc=0
    docker exec -u 0 "${env_args[@]+"${env_args[@]}"}" "${container}" "${TARGET_DIR}/run_ciscat.sh" \
        "${run_args[@]}" -o "${out_dir}" || rc=$?
    if [[ "${mode}" == ciscat-list ]]; then
        return "${rc}"
    fi
    if [[ ${rc} -ne 0 && ${rc} -ne 3 ]]; then
        echo "ERROR: CIS-CAT run in ${container} failed (exit ${rc})" >&2
        return "${rc}"
    fi
    mkdir -p "${host_out}"
    docker cp "${container}:${out_dir}/." "${host_out}/"
    for f in "${host_out}"/*; do
        if [[ -f "${f}" && ! -r "${f}" ]]; then
            echo "WARN: ${f} is not readable on the host" >&2
        fi
    done
    echo "INFO: CIS-CAT reports copied to ${host_out}/"
    ls -l "${host_out}"
    if [[ ${rc} -eq 3 ]]; then
        echo "WARN: platform mismatch - the report holds no valid compliance result (exit 3)" >&2
    fi
    return "${rc}"
}

# ------------------------------------------------------------------------------
# Function...: main
# Purpose....: Validate, prepare and run the use case
# ------------------------------------------------------------------------------
main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p | --pdb) PDB="${2:?missing value for $1}"; shift 2 ;;
            --no-restart) EXTRA_ARGS+=(--no-restart); shift ;;
            -f | --env-file) ENV_FILE="${2:?missing value for $1}"; shift 2 ;;
            --allow-public-ports) ALLOW_PUBLIC=true; shift ;;
            -w | --wait) WAIT_SECONDS="${2:?missing value for $1}"; shift 2 ;;
            -n | --dry-run) DRY_RUN=true; shift ;;
            -h | --help) usage 0 ;;
            -*) echo "ERROR: unknown option $1" >&2; usage 1 ;;
            *) break ;;
        esac
    done
    if [[ $# -lt 2 || ($# -gt 2 && "${3:-}" != "--") ]]; then
        echo "ERROR: USECASE and CONTAINER are required (further arguments only after --)" >&2
        usage 1
    fi
    local usecase="$1" container="$2" entry vars var
    shift 2
    if [[ $# -gt 0 ]]; then
        shift
        DBSAT_ARGS=("$@")
        case "${usecase}" in
            dbsat | dbsat-discover) ;;
            *) echo "ERROR: arguments after -- are only for dbsat and dbsat-discover" >&2; return 1 ;;
        esac
        check_dbsat_args
    fi

    case "${usecase}" in
        seclab)
            entry="${TARGET_DIR}/seclab_apply.sh"
            vars="SECLAB_USER_PWD SECLAB_SCOTT_PWD"
            ;;
        dbsat | dbsat-discover)
            entry="${TARGET_DIR}/run_dbsat.sh"
            vars="DBSAT_PWD"
            env_from_file DBSAT_PWD
            if [[ -z "${DBSAT_PWD:-}" ]]; then
                env_from_file SECLAB_DBSAT_PWD
                if [[ -n "${SECLAB_DBSAT_PWD:-}" ]]; then
                    export DBSAT_PWD="${SECLAB_DBSAT_PWD}"
                    echo "INFO: DBSAT_PWD not set - using SECLAB_DBSAT_PWD"
                fi
            fi
            ;;
        ciscat | ciscat-list)
            entry="${TARGET_DIR}/run_ciscat.sh"
            vars=""
            ;;
        *)
            echo "ERROR: unknown use case '${usecase}' (available: seclab, dbsat, dbsat-discover, ciscat, ciscat-list)" >&2
            return 1
            ;;
    esac

    if ! docker inspect -f '{{.State.Running}}' "${container}" 2> /dev/null | grep -qx true; then
        echo "ERROR: container '${container}' does not exist or is not running" >&2
        return 1
    fi
    if ! docker exec "${container}" bash -c 'test -x "${ORACLE_HOME}/bin/sqlplus"'; then
        echo "ERROR: ${container} does not look like an Oracle Database container (no sqlplus)" >&2
        return 1
    fi
    # CIS-CAT assesses the OS without the database; DB mode (Pro) checks it itself
    if [[ "${usecase}" == ciscat* ]]; then
        echo "INFO: use case ${usecase} -> container ${container}"
        run_ciscat_usecase "${usecase}" "${container}"
        return $?
    fi

    local env_args=() missing=0
    for var in ${vars}; do
        env_from_file "${var}"
        if [[ -z "${!var:-}" ]]; then
            echo "ERROR: ${var} is not set (export it or add it to ${ENV_FILE})" >&2
            missing=1
        fi
        env_args+=(-e "${var}")
    done
    if [[ ${missing} -ne 0 ]]; then
        return 1
    fi

    if [[ "${usecase}" == seclab ]]; then
        check_ports "${container}"
    fi

    wait_for_db "${container}"
    if [[ -z "${PDB}" ]]; then
        detect_pdb "${container}"
    fi
    echo "INFO: use case ${usecase} -> container ${container}, PDB ${PDB}"

    provide_scripts "${container}"

    if [[ "${usecase}" == dbsat || "${usecase}" == dbsat-discover ]]; then
        run_dbsat_usecase "${container}" "${usecase}"
        return $?
    fi
    if [[ "${DRY_RUN}" == true ]]; then
        echo "DRY-RUN: docker exec ${env_args[*]} ${container} ${entry} -p ${PDB} ${EXTRA_ARGS[*]+"${EXTRA_ARGS[*]}"}"
        return 0
    fi
    local rc=0
    docker exec "${env_args[@]}" "${container}" "${entry}" -p "${PDB}" "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}" || rc=$?
    echo ""
    echo "INFO: ${usecase} finished with exit code ${rc} (0 = all scenarios present)"
    echo "INFO: verify again: docker exec ${container} ${TARGET_DIR}/seclab_verify.sh -p ${PDB}"
    return "${rc}"
}

main "$@"
# - EOF ------------------------------------------------------------------------
