-- -----------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
-- -----------------------------------------------------------------------------
--  Name......: 15_create_ts_users_odbencprod.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2026.09.03
--  Revision..: v1.0.0
--  Purpose...: Create USERS tablespace in PDB ODBENCPROD and set it as the
--              default database tablespace. Uses common helper scripts for
--              logging and PDB context validation.
--  Notes.....: - Execute as SYSDBA.
--              - Shows runtime messages (e.g. "Session altered.") and PROMPTs,
--                but does not echo SQL or inline comments.
--              - Logs are written to /opt/oracle/scripts/logs (mounted writable).
--  License...: Apache License Version 2.0, January 2004 as shown
--              at http://www.apache.org/licenses/
-- -----------------------------------------------------------------------------

-- Fail fast in automation ------------------------------------------------------
WHENEVER SQLERROR EXIT SQL.SQLCODE

-- SQL*Plus formatting ----------------------------------------------------------
-- Show results + PROMPTs, but do not echo SQL text or comments.
SET LINESIZE 256 PAGESIZE 1000
SET SERVEROUTPUT ON FEEDBACK ON ECHO OFF TERMOUT ON VERIFY OFF

PROMPT - Switch to PDB ODBENCPROD
ALTER SESSION SET CONTAINER=ODBENCPROD;

-- Begin logging ---------------------------------------------------------------
DEFINE LOG_PREFIX = '15_create_ts_users_odbencprod'
DEFINE LOG_DIR    = '/opt/oracle/scripts/logs'
@/opt/oracle/common/scripts/define_logging_begin.sql

-- Require we are in a PDB (not CDB$ROOT) -------------------------------------
@/opt/oracle/common/scripts/require_pdb.sql

-- Create USERS tablespace (20 MB) and set as default --------------------------
@/opt/oracle/common/scripts/create_ts_users.sql USERS 20480K

-- End logging -----------------------------------------------------------------
@/opt/oracle/common/scripts/define_logging_end.sql
-- EOF -------------------------------------------------------------------------
