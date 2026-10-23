#!/bin/bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: lib_assess.sh
# Author.....: Stefan Oehrli (oes), stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026.10.23
# Revision...: v1.0.0
# Purpose....: Shared helpers for the assessment tools inside the container
#              (run_dbsat.sh, run_ciscat.sh): newest zip, dangling symlinks,
#              environment without secret-like variables.
# Notes......: - Sourced from the directory of the calling script, not
#                executed. bash 4.4 (Oracle Linux 8 image).
#              - The host side has newest_zip / dangling_links with the same
#                interface and behaviour in scripts/lib_usecase.sh - keep in sync.
# Reference..: https://github.com/oehrlis/oracle-free-labs
# License....: Apache License Version 2.0, January 2004 as shown
#              at http://www.apache.org/licenses/
# ------------------------------------------------------------------------------
# shellcheck disable=SC2034 # SCRUB_ENV and SCRUB_NAMES are used by the sourcing scripts
set -euo pipefail

# ------------------------------------------------------------------------------
# Function...: newest_zip
# Purpose....: Print the newest readable regular file in DIR ($1) matching
#              GLOB ($2), symlinks followed; empty if none
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
#              GLOB ($2), one per line - a host symlink is not visible
#              through a bind mount
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
# Function...: scrub_env
# Purpose....: Fill SCRUB_ENV with env -u options for every secret-like
#              variable of this process and SCRUB_NAMES with their names
#              (" A B", empty if none). The assessment tools need none of
#              them - dbsat collect writes its process environment into the
#              collection JSON, ORACLE_PWD and the SECLAB_*_PWD values would
#              land there in clear text; CIS-CAT gets the DB password in
#              its -cfg file. Run the tool with: env "${SCRUB_ENV[@]}" ...
# ------------------------------------------------------------------------------
scrub_env() {
    local v
    SCRUB_ENV=()
    SCRUB_NAMES=""
    for v in $(compgen -e); do
        case "${v}" in
            PWD | OLDPWD) ;;
            *PWD* | *PASSW* | *SECRET* | *TOKEN*)
                SCRUB_ENV+=(-u "${v}")
                SCRUB_NAMES+=" ${v}"
                ;;
        esac
    done
}
# - EOF ------------------------------------------------------------------------
