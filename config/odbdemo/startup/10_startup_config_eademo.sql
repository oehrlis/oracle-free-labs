--------------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
--------------------------------------------------------------------------------
--  Name......: 10_startup_config_odbdemo.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2025.11.18
--  Revision..: v1.0.0
--  Purpose...: Basic instance startup configuration for PDB ODBDEMO
--  Notes.....: Must be executed as SYSDBA connected to CDB$ROOT
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

-- Switch to PDB ODBDEMO --------------------------------------------------------
PROMPT - Switch to PDB ODBDEMO
ALTER SESSION SET CONTAINER=ODBDEMO;

-- Begin logging ---------------------------------------------------------------
DEFINE LOG_PREFIX = '10_startup_config_odbdemo'
DEFINE LOG_DIR    = '/opt/oracle/scripts/logs'
@/opt/oracle/common/scripts/define_logging_begin.sql

-- Require we are in a PDB (not CDB$ROOT) -------------------------------------
@/opt/oracle/common/scripts/require_pdb.sql

-- Main ------------------------------------------------------------------------
PROMPT - Startup baseline executed at
SELECT sysdate AS startup_time FROM dual;

-- End logging -----------------------------------------------------------------
@/opt/oracle/common/scripts/define_logging_end.sql
-- EOF -------------------------------------------------------------------------
