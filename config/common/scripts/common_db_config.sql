--------------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
--------------------------------------------------------------------------------
--  Name......: common_db_config.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2025.08.20
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

-- common password verification function ---------------------------------------
PROMPT - Create common password verification function
CREATE OR REPLACE FUNCTION verify_function_bit (
  username     VARCHAR2,
  password     VARCHAR2,
  old_password VARCHAR2
) RETURN BOOLEAN IS
BEGIN
  IF NOT ora_complexity_check(password, chars => 8) THEN
    RETURN FALSE;
  END IF;
  RETURN TRUE;
END;
/
-- Create common profiles similar to the BIT environment -----------------------
PROMPT - Create common user profiles
CREATE PROFILE c##u_user LIMIT sessions_per_user UNLIMITED PASSWORD_VERIFY_FUNCTION verify_function_bit;
CREATE PROFILE c##m_user LIMIT sessions_per_user UNLIMITED PASSWORD_VERIFY_FUNCTION verify_function_bit;
CREATE PROFILE c##admin_user LIMIT sessions_per_user UNLIMITED PASSWORD_VERIFY_FUNCTION verify_function_bit;
CREATE PROFILE c##end_user LIMIT sessions_per_user UNLIMITED PASSWORD_VERIFY_FUNCTION verify_function_bit;

-- Create COMMON users similar to BIT environmentbut without authentication:
PROMPT - Create common users without authentication
CREATE USER c##discovery NO AUTHENTICATION CONTAINER=ALL;
CREATE USER c##sparx     NO AUTHENTICATION CONTAINER=ALL;
CREATE USER c##fub_admin NO AUTHENTICATION CONTAINER=ALL;
CREATE USER c##sec_admin NO AUTHENTICATION CONTAINER=ALL;

-- Grant roles/privileges as needed here or in a PDB-scoped script.

-- EOF -------------------------------------------------------------------------
