#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: template.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026.04.15
# Version....: v0.2.0
# Purpose....: Generic Bash script template with logging and parameter parsing.
# Notes......: Extend this script to automate a specific task.
#              Features:
#              - Verbose and debug logging
#              - Dry run support
#              - Argument parsing with usage display
# Reference..: https://github.com/oehrlis/oracle-free-labs
# License....: Apache License Version 2.0, January 2004 as shown
#              at http://www.apache.org/licenses/
# ------------------------------------------------------------------------------
# Modified...:
# 2025.05.02 oehrli - initial version
# 2026.04.15 oehrli - hardened to set -euo pipefail; updated header
# ------------------------------------------------------------------------------
set -euo pipefail

# - Default Values -------------------------------------------------------------
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
SCRIPT_BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
SCRIPT_BASE="$(dirname "${SCRIPT_BIN_DIR}")"
export SCRIPT_BASE
VERBOSE=""
DEBUG=""
DRY_RUN=""
# - End of Default Values ------------------------------------------------------

# - Functions ------------------------------------------------------------------
function usage {
    cat <<EOF

Usage: ${SCRIPT_NAME} [OPTIONS]

Generic script template. Replace this description with your script purpose.

Options:
    -h      Show this help message.
    -v      Enable verbose logging.
    -d      Enable debug mode.
    -n      Dry run (no changes applied).

Example:
    ${SCRIPT_NAME} -v -n
EOF
    exit 0
}

function log_message {
    local message="$1"
    local level="${2:-INFO}"
    if [[ -n "${VERBOSE}" || ("${level}" == "DEBUG" && -n "${DEBUG}") ]]; then
        echo "[${level}] ${message}"
    fi
}
# - End of Functions -----------------------------------------------------------

# - Argument Parsing -----------------------------------------------------------
while getopts "hvnd" opt; do
    case ${opt} in
        h) usage ;;
        v) VERBOSE=1 ;;
        d) DEBUG=1 ;;
        n) DRY_RUN=1 ;;
        *) usage ;;
    esac
done
# - End of Argument Parsing ----------------------------------------------------

# - Main Logic -----------------------------------------------------------------
log_message "Starting script execution..." "INFO"

if [[ -n "${DRY_RUN}" ]]; then
    log_message "Dry run enabled. No actions will be performed." "INFO"
else
    log_message "Performing live operations..." "INFO"
    # Insert live commands here
fi

log_message "Script execution completed." "INFO"
# - End of script --------------------------------------------------------------
