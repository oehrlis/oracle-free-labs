#!/bin/bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: lib_dotenv.sh
# Author.....: Stefan Oehrli (oes), stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026.10.16
# Revision...: v1.0.0
# Purpose....: Shared helper for the host scripts: read one value from a
#              docker compose style .env file without sourcing it.
# Notes......: - Sourced by apply_usecase.sh and check_requirements.sh.
#              - Not sourcing .env avoids executing its content and keeps
#                unrelated variables out of the environment.
#              - An inline comment is stripped only when whitespace precedes
#                the '#', so a password may contain '#'.
#              - bash 3.2 compatible (macOS).
# Reference..: https://github.com/oehrlis/oracle-free-labs
# License....: Apache License Version 2.0, January 2004 as shown
#              at http://www.apache.org/licenses/
# ------------------------------------------------------------------------------
set -euo pipefail

# ------------------------------------------------------------------------------
# Function...: dotenv_value
# Purpose....: Print the value of variable $1 from file $2 (empty if absent).
#              The last assignment wins, like in docker compose.
# ------------------------------------------------------------------------------
dotenv_value() {
    local name="$1" file="$2" line value=""
    if [[ ! -r "${file}" ]]; then
        return 0
    fi
    while IFS= read -r line || [[ -n "${line}" ]]; do
        case "${line}" in
            "${name}="*)
                value="${line#*=}"
                value="${value%%[[:space:]]#*}"
                value="${value%"${value##*[![:space:]]}"}"
                ;;
        esac
    done < "${file}"
    echo "${value}"
}
# - EOF ------------------------------------------------------------------------
