--------------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
--------------------------------------------------------------------------------
--  Name......: 10_create_pdb_from_archive.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2025.11.18
--  Revision..: v1.0.0
--  Purpose...: Script to create PDB ODBDEMO from PPDB$SEED if it does not exists yet and
--              add a tablespace USESRS
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
DEFINE LOG_PREFIX = '10_create_pdb_from_archive'
DEFINE LOG_DIR    = '/opt/oracle/scripts/logs'
@/opt/oracle/common/scripts/define_logging_begin.sql

-- Require we are in a PDB (not CDB$ROOT) --------------------------------------
@/opt/oracle/common/scripts/require_cdb_root.sql

-- run the main script ---------------------------------------------------------
-- Create PDB from PDB$SEED ----------------------------------------------------
@/opt/oracle/common/scripts/create_pdb_from_archive.sql ODBREPO /opt/oracle/data/pdbarch/pdb26ai_odbrepo.pdb

-- End logging -----------------------------------------------------------------
@/opt/oracle/common/scripts/define_logging_end.sql
-- EOF -------------------------------------------------------------------------
