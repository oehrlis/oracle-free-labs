#!/bin/bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: provide_jre.sh
# Author.....: Stefan Oehrli (oes), stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026.10.19
# Revision...: v1.1.0
# Purpose....: Provide a Java 17+ runtime (default image: Java 21) inside a
#              running Oracle Database Free container for the assessment tools
#              (DBSAT report/discover need Java 17+, CIS-CAT needs Java 21,
#              the image ships JDK 11).
# Notes......: - Copies /opt/java/openjdk from a local JRE image (default
#                eclipse-temurin:21-jre, override with ASSESS_JRE_IMAGE or -i)
#                into the container. No helper container keeps running.
#              - Default target: /opt/oracle/oradata/tools/jre21 if
#                /opt/oracle/oradata is a bind mount (lab services, persistent
#                under data/<service>/tools/jre21), else /tmp/jre21.
#              - TARGET_DIR must be absolute, without whitespace, quotes or
#                '..', and its last component must start with "jre" - the
#                script removes it as root before copying.
#              - An existing JRE with Java 17+ (--min-java N: N+) is reused and
#                reported. A broken or too old one is replaced and reported.
#              - The JRE is streamed (docker cp ... -) into tar running as
#                oracle in the container: files belong to oracle without a
#                chown, which does not stick on Docker Desktop bind mounts.
#              - --owner root (CIS-CAT, which runs java as root): tar runs as
#                root, every file belongs to root, default target
#                /root/.cache/jre21 (parent mode 700) inside the container
#                filesystem - a target below a bind mount is refused, and an
#                existing JRE with a non-root file is replaced. Lost when the
#                container is recreated.
#              - Exit codes: 0 JRE ready, 1 usage or container problem,
#                2 JRE image not available, 3 copied JRE does not run Java 17+
#                (or the --min-java version).
#              - Runs on macOS (bash 3.2) and Linux.
# Usage......: scripts/provide_jre.sh [options] CONTAINER [TARGET_DIR]
# Reference..: doc/dbsat-runbook.md
# License....: Apache License Version 2.0, January 2004 as shown
#              at http://www.apache.org/licenses/
# ------------------------------------------------------------------------------
set -euo pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly JRE_SOURCE="/opt/java/openjdk"
# default keeps in sync with MIN_JAVA in config/common/scripts/run_dbsat.sh,
# CIS-CAT passes --min-java 21 (MIN_JAVA in run_ciscat.sh)
MIN_JAVA=17
# keep in sync with Makefile ASSESS_JRE_IMAGE and scripts/check_requirements.sh
JRE_IMAGE="${ASSESS_JRE_IMAGE:-eclipse-temurin:21-jre}"
DRY_RUN=false
FORCE=false
OWNER=oracle
TMP_CONTAINER=""

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
Usage: ${SCRIPT_NAME} [options] CONTAINER [TARGET_DIR]

Copy a Java ${MIN_JAVA}+ runtime (default image: Java 21) from a local JRE image
into a running Oracle container.

  TARGET_DIR             Default: /opt/oracle/oradata/tools/jre21 when
                         /opt/oracle/oradata is a bind mount, else /tmp/jre21;
                         --owner root: /root/.cache/jre21.
                         Absolute, no whitespace/quotes/'..', name jre*

Options:
  -i, --image IMAGE      JRE image (default: ${JRE_IMAGE}, env ASSESS_JRE_IMAGE)
  -m, --min-java N       Minimum Java major version (default: ${MIN_JAVA}, CIS-CAT: 21)
  -o, --owner USER       oracle (default) or root - root-owned copy for tools that
                         run java as root (CIS-CAT), never in a bind mount
  -f, --force            Replace an existing JRE even if it works
  -n, --dry-run          Show what would happen, change nothing
  -h, --help             Show this help

Exit codes: 0 ready, 1 usage/container, 2 image not available, 3 Java check failed
EOF
    exit "${rc}"
}

# ------------------------------------------------------------------------------
# Function...: cleanup
# Purpose....: Remove the temporary JRE container if one is left
# ------------------------------------------------------------------------------
cleanup() {
    if [[ -n "${TMP_CONTAINER}" ]]; then
        docker rm -f "${TMP_CONTAINER}" > /dev/null 2>&1 || true
        TMP_CONTAINER=""
    fi
}

# ------------------------------------------------------------------------------
# Function...: java_major
# Purpose....: Print the Java major version of TARGET_DIR/bin/java in the
#              container, empty if it does not run
# Notes......: keep in sync with java_major in config/common/scripts/run_dbsat.sh
# ------------------------------------------------------------------------------
java_major() {
    local container="$1" dir="$2" out line ver
    out="$(docker exec -u "${OWNER}" "${container}" "${dir}/bin/java" -version 2>&1)" || true
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
# Function...: default_target
# Purpose....: Print the persistent tools path for bind-mounted oradata, else
#              /tmp; for --owner root /root/.cache/jre21
# Notes......: keep in sync with JRE_CANDIDATES in config/common/scripts/run_dbsat.sh
#              and (--owner root) config/common/scripts/run_ciscat.sh
# ------------------------------------------------------------------------------
default_target() {
    local container="$1" mounts
    if [[ "${OWNER}" == root ]]; then
        echo "/root/.cache/jre21"
        return 0
    fi
    mounts="$(docker inspect -f '{{range .Mounts}}{{if eq .Type "bind"}}{{.Destination}} {{end}}{{end}}' "${container}")"
    case " ${mounts} " in
        *" /opt/oracle/oradata "*) echo "/opt/oracle/oradata/tools/jre21" ;;
        *) echo "/tmp/jre21" ;;
    esac
}

# ------------------------------------------------------------------------------
# Function...: validate_target
# Purpose....: Refuse a TARGET_DIR that is unsafe for the root rm -rf
# ------------------------------------------------------------------------------
validate_target() {
    local target="$1" reason=""
    case "${target}" in
        *\'*) reason="must not contain a single quote" ;;
        *..*) reason="must not contain '..'" ;;
        *[[:space:]]*) reason="must not contain whitespace" ;;
        /*/*) ;;
        *) reason="must be an absolute path below a directory" ;;
    esac
    if [[ -z "${reason}" ]]; then
        case "${target##*/}" in
            jre*) ;;
            *) reason="last path component must start with 'jre' (it is removed as root)" ;;
        esac
    fi
    if [[ -n "${reason}" ]]; then
        echo "ERROR: TARGET_DIR ${reason}, got '${target}' - refused" >&2
        return 1
    fi
}

# ------------------------------------------------------------------------------
# Function...: check_root_target
# Purpose....: --owner root: refuse a TARGET_DIR at or below a bind mount
#              (the host can change it, a chown may not stick there)
# ------------------------------------------------------------------------------
check_root_target() {
    local container="$1" target="$2" mounts m
    mounts="$(docker inspect -f '{{range .Mounts}}{{.Destination}} {{end}}' "${container}")"
    for m in ${mounts}; do
        if [[ "${target}" == "${m}" || "${target}" == "${m%/}/"* ]]; then
            echo "ERROR: --owner root needs a target inside the container filesystem;" \
                "${target} is below the mount ${m} - use e.g. /root/.cache/jre21" >&2
            return 1
        fi
    done
}

# ------------------------------------------------------------------------------
# Function...: non_root_file
# Purpose....: Print the first file below TARGET_DIR not owned by root, empty
#              if none
# ------------------------------------------------------------------------------
non_root_file() {
    docker exec -u root "$1" find "$2/" ! -user root -print -quit 2> /dev/null || true
}

# ------------------------------------------------------------------------------
# Function...: ensure_image
# Purpose....: Make sure the JRE image is local and matches the container arch
# ------------------------------------------------------------------------------
ensure_image() {
    local container="$1" img_arch db_image db_arch
    if ! img_arch="$(docker image inspect -f '{{.Architecture}}' "${JRE_IMAGE}" 2> /dev/null)"; then
        if [[ "${DRY_RUN}" == true ]]; then
            echo "DRY-RUN: docker pull ${JRE_IMAGE} (not present locally)"
            return 0
        fi
        echo "INFO: JRE image ${JRE_IMAGE} not present locally - pulling it"
        if ! docker pull "${JRE_IMAGE}"; then
            echo "ERROR: cannot pull ${JRE_IMAGE}" >&2
            echo "ERROR: pull it with registry access (docker pull ${JRE_IMAGE}), load it offline" >&2
            echo "ERROR: (docker save / docker load), or set ASSESS_JRE_IMAGE to a local JRE ${MIN_JAVA}+ image" >&2
            echo "ERROR: that has the runtime in ${JRE_SOURCE}." >&2
            return 2
        fi
        img_arch="$(docker image inspect -f '{{.Architecture}}' "${JRE_IMAGE}")"
    fi
    if ! db_image="$(docker inspect -f '{{.Image}}' "${container}")" \
        || ! db_arch="$(docker image inspect -f '{{.Architecture}}' "${db_image}")"; then
        echo "ERROR: cannot determine the image architecture of container ${container}" >&2
        return 1
    fi
    if [[ "${img_arch}" != "${db_arch}" ]]; then
        echo "ERROR: ${JRE_IMAGE} is ${img_arch}, container ${container} is ${db_arch}" >&2
        echo "ERROR: run: docker pull --platform linux/${db_arch} ${JRE_IMAGE}" >&2
        return 2
    fi
    echo "INFO: JRE image ${JRE_IMAGE} present (${img_arch})"
}

# ------------------------------------------------------------------------------
# Function...: copy_jre
# Purpose....: Stream the JRE from a temporary container into TARGET_DIR and
#              unpack it as OWNER (oracle: a chown does not stick on Docker
#              Desktop bind mounts, files created by oracle do; root: parent
#              created with mode 700, tar --no-same-owner)
# ------------------------------------------------------------------------------
copy_jre() {
    local container="$1" target="$2" parent staging owner rc=0 tar_args=() bad
    parent="${target%/*}"
    staging="${target}.staging"
    docker exec -u root "${container}" rm -rf -- "${target}" "${staging}"
    if [[ "${OWNER}" == root ]]; then
        docker exec -u root "${container}" bash -c 'umask 077 && mkdir -p -- "$1"' _ "${staging}"
        tar_args=(--no-same-owner)
    elif ! docker exec -u oracle "${container}" mkdir -p -- "${staging}" 2> /dev/null; then
        if docker exec "${container}" test -d "${parent}"; then
            docker exec -u root "${container}" bash -c \
                'mkdir -p -- "$1" && chown oracle:oinstall "$1"' _ "${staging}"
            echo "INFO: oracle cannot create ${staging} - created it as root, owner set to oracle:oinstall"
        else
            docker exec -u root "${container}" bash -c \
                'mkdir -p -- "$2" && chown oracle:oinstall "$1" "$2"' _ "${parent}" "${staging}"
            echo "INFO: oracle cannot create ${parent} - created it as root, owner set to oracle:oinstall"
        fi
    fi
    TMP_CONTAINER="$(docker create "${JRE_IMAGE}")"
    docker cp "${TMP_CONTAINER}:${JRE_SOURCE}" - \
        | docker exec -i -u "${OWNER}" "${container}" tar "${tar_args[@]+"${tar_args[@]}"}" -xf - -C "${staging}" \
        || rc=$?
    cleanup
    if [[ ${rc} -ne 0 ]]; then
        echo "ERROR: copying ${JRE_SOURCE} from ${JRE_IMAGE} into ${container}:${target} failed (rc=${rc})" >&2
        docker exec -u root "${container}" rm -rf -- "${staging}"
        return 1
    fi
    if ! docker exec -u "${OWNER}" "${container}" bash -c 'mv -- "$1" "$2" && rmdir -- "$3"' \
        _ "${staging}/${JRE_SOURCE##*/}" "${target}" "${staging}"; then
        echo "ERROR: ${OWNER} cannot move the JRE to ${container}:${target} - check the owner of ${parent}" >&2
        docker exec -u root "${container}" rm -rf -- "${staging}"
        return 1
    fi
    if [[ "${OWNER}" == root ]]; then
        bad="$(non_root_file "${container}" "${target}")"
        if [[ -n "${bad}" ]]; then
            echo "ERROR: ${container}:${bad} is not owned by root after the copy - the ownership does not stick" >&2
            docker exec -u root "${container}" rm -rf -- "${target}"
            return 1
        fi
    fi
    owner="$(docker exec -u "${OWNER}" "${container}" stat -c '%U:%G' "${target}")"
    echo "INFO: copied ${JRE_IMAGE}:${JRE_SOURCE} to ${container}:${target} (${owner})"
}

# ------------------------------------------------------------------------------
# Function...: main
# Purpose....: Validate, reuse or copy the JRE, verify Java 17+
# ------------------------------------------------------------------------------
main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -i | --image) JRE_IMAGE="${2:?missing value for $1}"; shift 2 ;;
            -m | --min-java) MIN_JAVA="${2:?missing value for $1}"; shift 2 ;;
            -o | --owner) OWNER="${2:?missing value for $1}"; shift 2 ;;
            -f | --force) FORCE=true; shift ;;
            -n | --dry-run) DRY_RUN=true; shift ;;
            -h | --help) usage 0 ;;
            -*) echo "ERROR: unknown option $1" >&2; usage 1 ;;
            *) break ;;
        esac
    done
    case "${MIN_JAVA}" in
        '' | *[!0-9]*) echo "ERROR: --min-java needs a number, got '${MIN_JAVA}'" >&2; usage 1 ;;
    esac
    case "${OWNER}" in
        oracle | root) ;;
        *) echo "ERROR: --owner must be oracle or root, got '${OWNER}'" >&2; usage 1 ;;
    esac
    readonly MIN_JAVA OWNER
    if [[ $# -lt 1 || $# -gt 2 ]]; then
        echo "ERROR: CONTAINER is required, TARGET_DIR is optional" >&2
        usage 1
    fi
    local container="$1" target="${2:-}" major
    if ! docker inspect -f '{{.State.Running}}' "${container}" 2> /dev/null | grep -qx true; then
        echo "ERROR: container '${container}' does not exist or is not running" >&2
        return 1
    fi
    target="${target:-$(default_target "${container}")}"
    target="${target%/}"
    validate_target "${target}"
    if [[ "${OWNER}" == root ]]; then
        check_root_target "${container}" "${target}"
    fi

    major="$(java_major "${container}" "${target}")"
    if [[ -n "${major}" && "${OWNER}" == root && -n "$(non_root_file "${container}" "${target}")" ]]; then
        echo "INFO: ${container}:${target} has files not owned by root - it will be replaced (--owner root)"
    elif [[ -n "${major}" ]] && ((major >= MIN_JAVA)); then
        if [[ "${FORCE}" == false ]]; then
            echo "INFO: reusing Java ${major} in ${container}:${target} (copy skipped, -f replaces it)"
            return 0
        fi
        echo "INFO: Java ${major} in ${container}:${target} will be replaced (--force)"
    elif [[ -n "${major}" ]]; then
        echo "INFO: Java ${major} in ${container}:${target} is older than ${MIN_JAVA} - it will be replaced"
    elif docker exec -u root "${container}" test -e "${target}"; then
        echo "INFO: ${container}:${target} exists without a working bin/java - it will be replaced"
    fi

    ensure_image "${container}"
    if [[ "${DRY_RUN}" == true ]]; then
        echo "DRY-RUN: docker create ${JRE_IMAGE}; docker cp ${JRE_SOURCE} -> ${container}:${target}"
        echo "DRY-RUN: unpack as ${OWNER}; verify ${target}/bin/java -version >= ${MIN_JAVA}"
        return 0
    fi
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    copy_jre "${container}" "${target}"

    major="$(java_major "${container}" "${target}")"
    if [[ -z "${major}" ]] || ((major < MIN_JAVA)); then
        echo "ERROR: ${container}:${target}/bin/java does not run Java ${MIN_JAVA}+ (got '${major:-nothing}')" >&2
        docker exec -u "${OWNER}" "${container}" "${target}/bin/java" -version >&2 || true
        return 3
    fi
    echo "INFO: Java ${major} ready in ${container}:${target} - use JAVA_HOME=${target}"
}

main "$@"
# - EOF ------------------------------------------------------------------------
