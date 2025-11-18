#!/bin/bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: 00_enable_unified_audit.sh
# Author.....: Stefan Oehrli (oes), stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2025.11.18
# Revision...: v1.0.0
# Purpose....: Enable Unified Auditing in the database. Stops the instance,
#              relinks the Oracle binaries with Unified Auditing enabled, and
#              restarts the database to activate the feature.
# Notes......:
#   - Must be executed as the Oracle software owner on the DB server.
#   - Requires ORACLE_HOME and ORACLE_SID environment variables to be set.
#   - Existing database session will be terminated due to shutdown/startup.
# Reference..: https://github.com/oehrlis/oudbase
# License....: Apache License Version 2.0, January 2004
#              http://www.apache.org/licenses/
# ------------------------------------------------------------------------------
# Modified...:
#   see git revision history with git log for more information on changes
# ------------------------------------------------------------------------------

# - configure instance ---------------------------------------------------------
echo "Enable Unified Audit for Database ${ORACLE_SID}:"
echo "  ORACLE_SID          :   ${ORACLE_SID}"
echo "  ORACLE_HOME         :   ${ORACLE_HOME}"

echo "Stop Database ${ORACLE_SID}:"
${ORACLE_HOME}/bin/sqlplus -S -L /nolog <<EOFSQL
connect / as sysdba
SELECT value FROM v\$option WHERE parameter = 'Unified Auditing';
shutdown immediate;
exit;
EOFSQL

echo "Relink Database ${ORACLE_SID} to enable unified audit:"
cd $ORACLE_HOME/rdbms/lib
make -f ins_rdbms.mk uniaud_on ioracle

echo "Start Database ${ORACLE_SID}:"
${ORACLE_HOME}/bin/sqlplus -S -L /nolog <<EOFSQL
connect / as sysdba
startup;
SELECT value FROM v\$option WHERE parameter = 'Unified Auditing';
exit;
EOFSQL
# - EOF ------------------------------------------------------------------------
