#!/bin/bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: cleanup_demo_env.sh
# Author.....: Stefan Oehrli (oes), stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026.03.10
# Revision...: v1.0.0
# Purpose....: Remove Oracle 26ai demo users and rollback demo environment.
# Notes......:
# License....: Apache License Version 2.0, January 2004
#              http://www.apache.org/licenses/
# ------------------------------------------------------------------------------
# Modified...:
#   see git revision history with git log for more information on changes
# ------------------------------------------------------------------------------

set -e

DB_CONNECT="${DB_CONNECT:-/ as sysdba}"

echo "Cleaning demo environment..."

sqlplus -s "${DB_CONNECT}" @cleanup_demo_env.sql
sqlplus -s "${DB_CONNECT}" @cleanup_sql_firewall.sql || true

echo "Cleanup complete."