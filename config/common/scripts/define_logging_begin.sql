-- -----------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
-- -----------------------------------------------------------------------------
--  Name......: define_logging_begin.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2025.08.20
--  Revision..: v1.0.1
--  Purpose...: Define logging variables and start SPOOL for script execution.
--  Notes.....: 
--              - Optionally set LOG_PREFIX before including this script.
--              - LOG_DIR can also be set; defaults to /opt/oracle/oradata/logs.
--              - Ensure LOG_DIR is writable in the container.
--  License...: Apache License Version 2.0, January 2004
-- -----------------------------------------------------------------------------

-- SQL*Plus formatting ---------------------------------------------------------
SET FEEDBACK OFF

-- Defaults if not provided ----------------------------------------------------
COLUMN LOG_PREFIX NEW_VALUE LOG_PREFIX NOPRINT
SELECT NVL('&&LOG_PREFIX','script') AS LOG_PREFIX FROM dual;

COLUMN LOG_DIR NEW_VALUE LOG_DIR NOPRINT
SELECT NVL('&&LOG_DIR','/opt/oracle/oradata') AS LOG_DIR FROM dual;

-- Identify DB / container / timestamp ----------------------------------------
COLUMN db_name   NEW_VALUE db_name   NOPRINT
COLUMN pdb_name  NEW_VALUE pdb_name  NOPRINT
COLUMN log_date  NEW_VALUE log_date  NOPRINT

SELECT sys_context('userenv','db_unique_name') AS db_name FROM dual;
SELECT REPLACE(sys_context('userenv', 'con_name'), '$', '') AS pdb_name FROM dual;
SELECT TO_CHAR(SYSDATE, 'YYYYMMDD_HH24MISS') AS log_date FROM dual;

-- Start logging ---------------------------------------------------------------
SET FEEDBACK ON
SPOOL &LOG_DIR./&LOG_PREFIX._&db_name._&pdb_name._&log_date..log
PROMPT - &LOG_PREFIX. on &db_name./&pdb_name. at &log_date.
PROMPT - Log file: &LOG_DIR./&LOG_PREFIX._&db_name._&pdb_name._&log_date..log

-- EOF -------------------------------------------------------------------------
