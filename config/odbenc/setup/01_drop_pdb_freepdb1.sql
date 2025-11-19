--------------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
--------------------------------------------------------------------------------
--  Name......: 01_drop_pdb_freepdb1.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2025.11.18
--  Revision..: v1.0.0
--  Purpose...: Script to drop FREEPDB1 if it does exists
--  Notes.....: Must be executed as SYSDBA connected to CDB$ROOT
--  Reference.: --
--  License...: Apache License Version 2.0, January 2004 as shown
--              at http://www.apache.org/licenses/
--------------------------------------------------------------------------------

-- Fail fast in automation ------------------------------------------------------
WHENEVER SQLERROR EXIT SQL.SQLCODE

-- SQL*Plus formatting ----------------------------------------------------------
-- Show results + PROMPTs, but do not echo SQL text or comments.
SET LINESIZE 256 PAGESIZE 1000
SET SERVEROUTPUT ON FEEDBACK ON ECHO OFF TERMOUT ON VERIFY OFF

-- Begin logging ---------------------------------------------------------------
DEFINE LOG_PREFIX = '01_drop_pdb_freepdb1'
DEFINE LOG_DIR    = '/opt/oracle/scripts/logs'
@/opt/oracle/common/scripts/define_logging_begin.sql

-- Require we are in CDB$ROOT (not a PDB) --------------------------------------
@/opt/oracle/common/scripts/require_cdb_root.sql

-- run the main script ---------------------------------------------------------
-- Drop PDB FREEPDB1 if it exists ----------------------------------------------
@/opt/oracle/common/scripts/drop_pdb.sql FREEPDB1

-- End logging -----------------------------------------------------------------
@/opt/oracle/common/scripts/define_logging_end.sql
-- EOF -------------------------------------------------------------------------
