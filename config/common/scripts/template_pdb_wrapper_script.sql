-- -----------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
-- -----------------------------------------------------------------------------
--  Name......: template_pdb_wrapper_script.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2025.11.18
--  Revision..: v1.0.0
--  Purpose...: Wrapper script to run script in PDB. Uses common helper scripts
--              for logging and PDB context validation.
--  Notes.....: - Execute as SYSDBA.
--              - Shows runtime messages (e.g. "Session altered.") and PROMPTs,
--                but does not echo SQL or inline comments.
--              - Logs are written to /opt/oracle/scripts/log (mounted writable).
--  License...: Apache License Version 2.0, January 2004 as shown
--              at http://www.apache.org/licenses/
-- -----------------------------------------------------------------------------

-- Fail fast in automation -----------------------------------------------------
WHENEVER SQLERROR EXIT SQL.SQLCODE

-- SQL*Plus formatting ---------------------------------------------------------
-- Show results + PROMPTs, but do not echo SQL text or comments.
SET LINESIZE 256 PAGESIZE 1000
SET SERVEROUTPUT ON FEEDBACK ON ECHO OFF TERMOUT ON VERIFY OFF

PROMPT - Switch to PDB <PDB_NAME>
ALTER SESSION SET CONTAINER=<PDB_NAME>;

-- Begin logging ---------------------------------------------------------------
DEFINE LOG_PREFIX = 'template_pdb_wrapper_script'
DEFINE LOG_DIR    = '/opt/oracle/scripts/logs'
@/opt/oracle/common/scripts/define_logging_begin.sql

-- Require we are in a PDB (not CDB$ROOT) --------------------------------------
@/opt/oracle/common/scripts/require_pdb.sql

-- run the main script ---------------------------------------------------------


-- End logging -----------------------------------------------------------------
@/opt/oracle/common/scripts/define_logging_end.sql
-- EOF -------------------------------------------------------------------------
