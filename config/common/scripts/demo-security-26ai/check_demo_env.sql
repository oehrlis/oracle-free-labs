-- -----------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
-- -----------------------------------------------------------------------------
--  Name......: check_demo_env.sql
--  Author....: Stefan Oehrli (oes), stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2026.03.10
--  Revision..: v1.0.0
--  Purpose...: Check demo users, SQL Firewall state, and enabled audit policies.
--  Notes.....:
--  License...: Apache License Version 2.0, January 2004
--              http://www.apache.org/licenses/
-- -----------------------------------------------------------------------------

SET PAGESIZE 200
SET LINESIZE 220
SET FEEDBACK ON
SET VERIFY OFF
SET ECHO OFF
SET TAB OFF
SET TRIMSPOOL ON

COLUMN name                           FORMAT A40
COLUMN value                          FORMAT A60
COLUMN username                       FORMAT A25
COLUMN account_status                 FORMAT A20
COLUMN authentication_type            FORMAT A20
COLUMN password_versions              FORMAT A20
COLUMN mfa                            FORMAT A10
COLUMN read_only                      FORMAT A10
COLUMN dictionary_protected           FORMAT A10
COLUMN status                         FORMAT A15
COLUMN enabled_option                 FORMAT A20
COLUMN multifactor_authentication_methods FORMAT A40
COLUMN sql_text                       FORMAT A80 WORD_WRAPPED
COLUMN event_timestamp                FORMAT A35
COLUMN policy_name                    FORMAT A40
COLUMN entity_name                    FORMAT A40
ALTER SESSION SET NLS_DATE_FORMAT = 'YYYY-MM-DD HH24:MI:SS';
ALTER SESSION SET NLS_TIMESTAMP_FORMAT = 'YYYY-MM-DD HH24:MI:SS.FF';
ALTER SESSION SET NLS_TIMESTAMP_TZ_FORMAT = 'YYYY-MM-DD HH24:MI:SS.FF TZR';
ALTER SESSION SET CONTAINER = LABPDB1;

PROMPT =========================================================================
PROMPT Oracle AI Database 26ai Demo Environment Check
PROMPT =========================================================================

PROMPT
PROMPT =========================================================================
PROMPT 1. Database Identity
PROMPT =========================================================================
SELECT name, open_mode
FROM v$pdbs
WHERE UPPER(name) = 'LABPDB1';

PROMPT
PROMPT =========================================================================
PROMPT 2. SQL Firewall Status
PROMPT =========================================================================
SELECT status, status_updated_on, exclude_jobs
FROM dba_sql_firewall_status;

PROMPT
PROMPT === SQL Firewall capture logs for SCOTT =================================
SELECT username, COUNT(*) AS capture_entries
FROM dba_sql_firewall_capture_logs
WHERE username = 'SCOTT'
GROUP BY username;

PROMPT
PROMPT === SQL Firewall violations for SCOTT ===================================
SELECT username, COUNT(*) AS violation_entries
FROM dba_sql_firewall_violations
WHERE username = 'SCOTT'
GROUP BY username;

PROMPT
PROMPT =========================================================================
PROMPT 3. Demo Users Overview
PROMPT =========================================================================
SELECT username,
       account_status,
       authentication_type,
       password_versions,
       read_only,
       mfa,
       dictionary_protected
FROM dba_users
WHERE username IN ('SCOTT','DEMO_RO','HR_APP','SOUG_TEST','OEHRLI')
ORDER BY username;

PROMPT
PROMPT =========================================================================
PROMPT 4. Schema-Only Accounts
PROMPT =========================================================================
SELECT username, authentication_type
FROM dba_users
WHERE authentication_type = 'NONE'
ORDER BY username;

PROMPT
PROMPT =========================================================================
PROMPT 5. Read-Only Users
PROMPT =========================================================================
SELECT username, read_only
FROM dba_users
WHERE read_only = 'YES'
ORDER BY username;

PROMPT
PROMPT =========================================================================
PROMPT 6. MFA Information
PROMPT =========================================================================
SELECT username, mfa
FROM dba_users
WHERE username IN ('SCOTT')
ORDER BY username;

PROMPT
PROMPT === Current session MFA methods =========================================
SELECT SYS_CONTEXT(
       'USERENV',
       'MULTIFACTOR_AUTHENTICATION_METHODS') AS multifactor_authentication_methods
FROM dual;

PROMPT
PROMPT =========================================================================
PROMPT 7. Data Dictionary Protection
PROMPT =========================================================================
SELECT username, dictionary_protected
FROM dba_users
WHERE dictionary_protected = 'YES'
ORDER BY username;

PROMPT
PROMPT =========================================================================
PROMPT 8. Schema Privileges
PROMPT =========================================================================
SELECT grantee, privilege, schema
FROM dba_schema_privs
WHERE grantee IN ('OEHRLI')
ORDER BY grantee, privilege, schema;

PROMPT
PROMPT =========================================================================
PROMPT 9. Default / Enabled Unified Audit Policies
PROMPT =========================================================================
SELECT policy_name, enabled_option, entity_name
FROM audit_unified_enabled_policies
ORDER BY policy_name, entity_name;

PROMPT
PROMPT =========================================================================
PROMPT 10. Legacy Password Versions
PROMPT =========================================================================
SELECT username, password_versions
FROM dba_users
WHERE password_versions LIKE '%10G%'
ORDER BY username;

PROMPT
PROMPT =========================================================================
PROMPT 11. Quick Validation Queries
PROMPT =========================================================================
PROMPT === SCOTT objects for SQL Firewall / read-only demos ====================
SELECT owner, object_name, object_type
FROM dba_objects
WHERE owner = 'SCOTT'
  AND object_name IN ('EMP','DEPT')
ORDER BY object_name;

PROMPT
PROMPT =========================================================================
PROMPT End of Demo Environment Check
PROMPT =========================================================================
exit