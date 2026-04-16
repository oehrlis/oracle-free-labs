#!/bin/bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: check_demo_env.sh
# Author.....: Stefan Oehrli (oes), stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026.03.10
# Revision...: v1.0.0
# Purpose....: Verify Oracle 26ai demo environment status and key feature flags.
# Notes......:
# License....: Apache License Version 2.0, January 2004
#              http://www.apache.org/licenses/
# ------------------------------------------------------------------------------
# Modified...:
#   see git revision history with git log for more information on changes
# ------------------------------------------------------------------------------

set -euo pipefail

DB_CONNECT="${DB_CONNECT:-/ as sysdba}"

echo "==================================================================="
echo "Check local demo environment"
echo "==================================================================="
echo "DB_CONNECT : ${DB_CONNECT}"
echo

sqlplus -s "${DB_CONNECT}" @"check_demo_env.sql"