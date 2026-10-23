#!/bin/bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: lib_usecase.sh
# Author.....: Stefan Oehrli (oes), stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026.10.23
# Revision...: v1.0.0
# Purpose....: Shared host helpers for the assessment use cases (DBSAT,
#              CIS-CAT): defaults, newest zip, zip into the container,
#              results back to the host, password variable fallback.
# Notes......: - Sourced by apply_usecase.sh, check_requirements.sh and
#                provide_jre.sh; sources lib_dotenv.sh itself.
#              - Reads the caller globals ENV_FILE (env_from_file) and
#                DRY_RUN (provide_zip, copy_back; default false).
#              - The defaults below are the single host-side place. The
#                container side has its own copy (unavoidable, other tree):
#                config/common/scripts/lib_java.sh (MIN_JAVA), run_dbsat.sh
#                and run_ciscat.sh (ZIP_GLOB); the Makefile has
#                ASSESS_JRE_IMAGE - keep them in sync.
#              - bash 3.2 compatible (macOS).
# Reference..: https://github.com/oehrlis/oracle-free-labs
# License....: Apache License Version 2.0, January 2004 as shown
#              at http://www.apache.org/licenses/
# ------------------------------------------------------------------------------
# shellcheck disable=SC2034 # constants and ZIP_DIR_IN_CONTAINER are used by the sourcing scripts
set -euo pipefail

# shellcheck source=scripts/lib_dotenv.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib_dotenv.sh"

# keep in sync with ZIP_GLOB in config/common/scripts/run_dbsat.sh
readonly DBSAT_GLOB="dbsat*.zip"
# keep in sync with ZIP_GLOB in config/common/scripts/run_ciscat.sh
readonly CISCAT_GLOB="*[Cc][Ii][Ss]*[Cc][Aa][Tt]*.zip"
# keep in sync with DBSAT_MIN_JAVA / CISCAT_MIN_JAVA in config/common/scripts/lib_java.sh
readonly DBSAT_MIN_JAVA=17
readonly CISCAT_MIN_JAVA=21
# keep in sync with ASSESS_JRE_IMAGE in the Makefile
readonly ASSESS_JRE_IMAGE_DEFAULT="eclipse-temurin:21-jre"

# ------------------------------------------------------------------------------
# Function...: newest_zip
# Purpose....: Print the newest readable regular file in DIR ($1) matching GLOB ($2),
#              symlinks followed; empty if none. A dangling symlink does not
#              count - name it with dangling_links.
# ------------------------------------------------------------------------------
newest_zip() {
    local dir="$1" glob="$2" zip="" f
    for f in "${dir}"/${glob}; do
        if [[ -f "${f}" && -r "${f}" && "${f}" -nt "${zip:-/nonexistent}" ]]; then
            zip="${f}"
        fi
    done
    echo "${zip}"
}

# ------------------------------------------------------------------------------
# Function...: dangling_links
# Purpose....: Print the file names of dangling symlinks in DIR ($1) matching
#              GLOB ($2), one per line
# ------------------------------------------------------------------------------
dangling_links() {
    local dir="$1" glob="$2" f
    for f in "${dir}"/${glob}; do
        if [[ -L "${f}" && ! -e "${f}" ]]; then
            echo "${f##*/}"
        fi
    done
}

# ------------------------------------------------------------------------------
# Function...: warn_dangling
# Purpose....: WARN (stderr) for every dangling symlink in DIR ($1) matching
#              GLOB ($2) - skipped by newest_zip, never silently
# ------------------------------------------------------------------------------
warn_dangling() {
    local name
    while IFS= read -r name; do
        echo "WARN: ${1}/${name} is a dangling symlink - skipped" >&2
    done < <(dangling_links "$1" "$2")
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
    value="$(dotenv_value "${name}" "${ENV_FILE:-}")"
    if [[ -n "${value}" ]]; then
        export "${name}=${value}"
    fi
}

# ------------------------------------------------------------------------------
# Function...: env_fallback
# Purpose....: Set TARGET from the environment or ENV_FILE, else export it
#              with the value of the first SRC that is set there (reported).
#              Usage: env_fallback [-n NOTE] TARGET SRC...
#              NOTE is appended to the message in parentheses.
# ------------------------------------------------------------------------------
env_fallback() {
    local note="" target src
    if [[ "${1:-}" == -n ]]; then
        note=" (${2:?missing value for -n})"
        shift 2
    fi
    target="${1:?env_fallback needs TARGET}"
    shift
    env_from_file "${target}"
    for src in "$@"; do
        if [[ -n "${!target:-}" ]]; then
            return 0
        fi
        env_from_file "${src}"
        if [[ -n "${!src:-}" ]]; then
            export "${target}=${!src}"
            echo "INFO: ${target} not set - using ${src}${note}"
        fi
    done
}

# ------------------------------------------------------------------------------
# Function...: provide_zip
# Purpose....: Make the host ZIP available in the container and set
#              ZIP_DIR_IN_CONTAINER to the directory that holds it.
#              Usage: provide_zip CONTAINER ZIP COPY_DIR OWNER [MOUNT_DIR]
#              MOUNT_DIR (optional): container directory that shows the zip
#              when it lies at or below a mount - used if the zip is readable
#              there. A host symlink dangles through a bind mount: then, and
#              without MOUNT_DIR, the zip is copied (docker cp -L, resolves
#              symlinks, keeps the mtime) into a fresh COPY_DIR.
#              OWNER oracle: COPY_DIR created by the default user of the
#              container. OWNER root: COPY_DIR root-owned, mode 700, zip 600
#              (CIS-CAT runs the zip content as root).
# ------------------------------------------------------------------------------
provide_zip() {
    local container="$1" zip="$2" copy_dir="$3" owner="$4" mount_dir="${5:-}" name="${2##*/}" mounts m
    ZIP_DIR_IN_CONTAINER=""
    if [[ -n "${mount_dir}" ]]; then
        mounts="$(docker inspect -f '{{range .Mounts}}{{.Destination}} {{end}}' "${container}")"
        for m in ${mounts}; do
            if [[ "${mount_dir}" == "${m%/}" || "${mount_dir}" == "${m%/}/"* ]]; then
                if docker exec "${container}" bash -c 'test -f "$1" && test -r "$1"' _ "${mount_dir}/${name}"; then
                    ZIP_DIR_IN_CONTAINER="${mount_dir}"
                    echo "INFO: using the bind-mounted ${mount_dir} of ${container}"
                    return 0
                fi
                echo "WARN: ${name} is not readable in the bind-mounted ${mount_dir} of ${container}" \
                    "(a host symlink dangles there) - copying it to ${copy_dir} instead" >&2
                break
            fi
        done
    fi
    ZIP_DIR_IN_CONTAINER="${copy_dir}"
    if [[ "${owner}" == root ]]; then
        if [[ "${DRY_RUN:-false}" == true ]]; then
            echo "DRY-RUN: docker cp -L ${zip} -> ${container}:${copy_dir}/ (root, mode 700)"
            return 0
        fi
        docker exec -u root "${container}" bash -c 'umask 077 && rm -rf -- "$1" && mkdir -p -- "$1"' _ "${copy_dir}"
        docker cp -L "${zip}" "${container}:${copy_dir}/"
        docker exec -u root "${container}" bash -c 'chown -R root:root -- "$1" && chmod 600 -- "$1"/*' _ "${copy_dir}"
        echo "INFO: copied ${name} to ${container}:${copy_dir}/ (root, mode 700, previous copy removed)"
        return 0
    fi
    if [[ "${DRY_RUN:-false}" == true ]]; then
        echo "DRY-RUN: docker cp -L ${zip} -> ${container}:${copy_dir}/"
        return 0
    fi
    docker exec "${container}" bash -c 'rm -rf -- "$1" && mkdir -p -- "$1"' _ "${copy_dir}"
    docker cp -L "${zip}" "${container}:${copy_dir}/"
    echo "INFO: copied ${name} to ${container}:${copy_dir}/ (previous copy removed)"
}

# ------------------------------------------------------------------------------
# Function...: copy_back
# Purpose....: Copy OUT_DIR of the container to HOST_OUT, WARN for files that
#              are not readable on the host, print MESSAGE (to stderr if it
#              starts with ERROR: or WARN:) and list HOST_OUT.
#              Usage: copy_back CONTAINER OUT_DIR HOST_OUT MESSAGE
#              DRY_RUN=true: print the docker cp only.
# ------------------------------------------------------------------------------
copy_back() {
    local container="$1" out_dir="$2" host_out="$3" msg="$4" f
    if [[ "${DRY_RUN:-false}" == true ]]; then
        echo "DRY-RUN: docker cp ${container}:${out_dir}/. ${host_out}/"
        return 0
    fi
    mkdir -p "${host_out}"
    docker cp "${container}:${out_dir}/." "${host_out}/"
    for f in "${host_out}"/*; do
        if [[ -f "${f}" && ! -r "${f}" ]]; then
            echo "WARN: ${f} is not readable on the host" >&2
        fi
    done
    case "${msg}" in
        ERROR:* | WARN:*) echo "${msg}" >&2 ;;
        *) echo "${msg}" ;;
    esac
    ls -l "${host_out}"
}
# - EOF ------------------------------------------------------------------------
