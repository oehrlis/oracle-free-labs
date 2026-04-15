--------------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
--------------------------------------------------------------------------------
--  Name......: 21_setup_scott_odbenc.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2025.11.18
--  Revision..: v1.0.0
--  Purpose...: PDB-scoped security baseline for OraDBA demo
--              - Create demo role with minimum required privileges
--              - Create demo profile and demo user, grant role and directory access
--  Notes.....: Must be executed as a DBA user connected to the target PDB
--  Reference.: --
--  License...: Apache License Version 2.0, January 2004 as shown
--              at http://www.apache.org/licenses/
--------------------------------------------------------------------------------

-- Fail fast in automation -----------------------------------------------------
WHENEVER SQLERROR EXIT SQL.SQLCODE

-- SQL*Plus formatting ---------------------------------------------------------
-- Show results + PROMPTs, but do not echo SQL text or comments.
SET LINESIZE 256 PAGESIZE 1000
SET SERVEROUTPUT ON FEEDBACK ON ECHO OFF TERMOUT ON VERIFY OFF

PROMPT - Switch to PDB ODBENC
ALTER SESSION SET CONTAINER=ODBENC;

-- Begin logging ---------------------------------------------------------------
DEFINE LOG_PREFIX = '21_setup_scott_odbenc'
DEFINE LOG_DIR    = '/opt/oracle/scripts/logs'
@/opt/oracle/common/scripts/define_logging_begin.sql

-- Require we are in a PDB (not CDB$ROOT) --------------------------------------
@/opt/oracle/common/scripts/require_pdb.sql

-- Main ------------------------------------------------------------------------
@/opt/oracle/common/scripts/create_scott.sql

-- End logging -----------------------------------------------------------------
@/opt/oracle/common/scripts/define_logging_end.sql
-- EOF -------------------------------------------------------------------------
