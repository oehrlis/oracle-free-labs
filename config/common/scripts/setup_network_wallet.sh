#!/bin/bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: setup_network_wallet.sh
# Author.....: Stefan Oehrli (oes), stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026.05.18
# Revision...: v1.0.0
# Purpose....: Redirect the Oracle wallet directory to the bind-mounted dbconfig
#              area so it survives container restarts and full resets.
#              Also verifies that /opt/oracle/network/admin is a valid symlink.
# Notes......: - Idempotent - safe to run on every container start.
#              - Skip silently if dbconfig is not bind-mounted (e.g. cdbfree).
#              - Migrates an existing wallet dir on first call.
# Reference..: https://github.com/oehrlis/oracle-free-labs
# License....: Apache License Version 2.0, January 2004 as shown
#              at http://www.apache.org/licenses/
# ------------------------------------------------------------------------------
# Modified...:
#   see git revision history with git log for more information on changes
# ------------------------------------------------------------------------------
set -euo pipefail

ORACLE_SID="${ORACLE_SID:-FREE}"
DBCONFIG_DIR="/opt/oracle/dbconfig/${ORACLE_SID}"
WALLET_PERSIST="${DBCONFIG_DIR}/wallet"
WALLET_DEFAULT="/opt/oracle/admin/${ORACLE_SID}/wallet"

echo "INFO: setup_network_wallet.sh - ORACLE_SID=${ORACLE_SID}"

# Skip if dbconfig is not bind-mounted (cdbfree uses oradata-based paths)
if [[ ! -d "${DBCONFIG_DIR}" ]]; then
    echo "INFO: ${DBCONFIG_DIR} not found - skipping wallet persistence setup"
    exit 0
fi

# - Wallet persistence ---------------------------------------------------------
mkdir -p "${WALLET_PERSIST}"
mkdir -p "$(dirname "${WALLET_DEFAULT}")"

if [[ -L "${WALLET_DEFAULT}" ]]; then
    echo "INFO: Wallet symlink already in place at ${WALLET_DEFAULT}"
elif [[ -d "${WALLET_DEFAULT}" ]]; then
    # Real directory exists - migrate contents then replace with symlink
    if [[ -n "$(ls -A "${WALLET_DEFAULT}")" ]]; then
        cp -a "${WALLET_DEFAULT}/." "${WALLET_PERSIST}/"
        echo "INFO: Wallet contents migrated to ${WALLET_PERSIST}"
    fi
    rm -rf "${WALLET_DEFAULT}"
    ln -sf "${WALLET_PERSIST}" "${WALLET_DEFAULT}"
    echo "INFO: Wallet redirected: ${WALLET_DEFAULT} -> ${WALLET_PERSIST}"
else
    ln -sf "${WALLET_PERSIST}" "${WALLET_DEFAULT}"
    echo "INFO: Wallet symlink created: ${WALLET_DEFAULT} -> ${WALLET_PERSIST}"
fi
# - EOF ------------------------------------------------------------------------
