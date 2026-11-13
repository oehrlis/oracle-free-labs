--------------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
--------------------------------------------------------------------------------
--  Name......: common_db_config.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2025.11.18
--  Revision..: v1.0.0
--  Purpose...: Common instance configuration (parameters requiring restart)
--  Notes.....: - Execute in CDB$ROOT as SYSDBA (pair with require_cdb_root.sql).
--              - Logging and SQL*Plus formatting are the caller's responsibility.
--  License...: Apache License Version 2.0, January 2004 as shown
--              at http://www.apache.org/licenses/
--------------------------------------------------------------------------------

-- Fail fast in automation -----------------------------------------------------
WHENEVER SQLERROR EXIT SQL.SQLCODE

-- SQL*Plus formatting ---------------------------------------------------------
SET LINESIZE 256 PAGESIZE 1000
SET SERVEROUTPUT ON

-- Main ------------------------------------------------------------------------
-- Must run in CDB$ROOT (prefer also calling require_cdb_root.sql before this)

PROMPT - Set instance parameters (SPFILE)

-- Adjust as needed; these require a restart when changed in SPFILE.
ALTER SYSTEM SET db_domain = 'oradba.ch' SCOPE = SPFILE;
ALTER SYSTEM SET db_files  = 1024        SCOPE = SPFILE;

-- Restart database ------------------------------------------------------------
PROMPT - Restart database to apply parameter changes
SHUTDOWN IMMEDIATE;
STARTUP;

-- Grant roles/privileges as needed here or in a PDB-scoped script.

-- EOF -------------------------------------------------------------------------
