--------------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
--------------------------------------------------------------------------------
--  Name......: precheck_profile_hardening.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2026.10.15
--  Revision..: v1.0.0
--  Purpose...: Pre-check before hardening a profile (lifetime, lockout, verify
--              function): show who uses it and which accounts look like
--              non-personal service accounts that would expire or lock.
--  Notes.....: - Read-only. Execute in the PDB to check, as SYSDBA or with
--                SELECT ANY DICTIONARY.
--              - &1 profile name.
--              - Service account detection is a name heuristic: regular
--                expression &2, default ^(SVC_|APP_|BATCH). Review the list,
--                the dictionary cannot tell a person from a technical account.
--  Usage.....: @precheck_profile_hardening.sql SECLAB_UNLIMITED
--  License...: Apache License Version 2.0, January 2004 as shown
--              at http://www.apache.org/licenses/
--------------------------------------------------------------------------------

-- Fail fast in automation -----------------------------------------------------
WHENEVER SQLERROR EXIT SQL.SQLCODE

SET FEEDBACK OFF
SET VERIFY OFF
SET SERVEROUTPUT ON SIZE UNLIMITED
COLUMN 1 NEW_VALUE 1 NOPRINT
COLUMN 2 NEW_VALUE 2 NOPRINT
SELECT '' "1" FROM dual WHERE ROWNUM = 0;
SELECT '' "2" FROM dual WHERE ROWNUM = 0;
DEFINE _PROFILE = &1
DEFINE _SVC_PATTERN = &2 ^(SVC_|APP_|BATCH)

PROMPT - Current password limits of profile &_PROFILE
COL resource_name FOR A26
COL limit         FOR A24
SELECT resource_name, limit
  FROM dba_profiles
 WHERE profile = UPPER('&_PROFILE') AND resource_type = 'PASSWORD'
 ORDER BY resource_name;

DECLARE
  l_profile VARCHAR2(128) := UPPER('&&_PROFILE');
  l_svc     PLS_INTEGER := 0;
  l_pers    PLS_INTEGER := 0;
BEGIN
  dbms_output.put_line('Accounts on profile ' || l_profile || ':');
  FOR r IN (SELECT username, account_status, created, last_login, password_change_date
              FROM dba_users WHERE profile = l_profile ORDER BY username) LOOP
    IF REGEXP_LIKE(r.username, '&&_SVC_PATTERN') THEN
      l_svc := l_svc + 1;
      dbms_output.put_line('SERVICE ACCOUNT?: ' || r.username || ' (' || r.account_status
                           || ', last login ' || NVL(TO_CHAR(r.last_login, 'YYYY-MM-DD'), 'never')
                           || ') - lifetime/lockout would stop this account; move it to a service profile first');
    ELSE
      l_pers := l_pers + 1;
      dbms_output.put_line('PERSONAL: ' || r.username || ' (' || r.account_status
                           || ', last login ' || NVL(TO_CHAR(r.last_login, 'YYYY-MM-DD'), 'never') || ')');
    END IF;
  END LOOP;
  dbms_output.put_line('Result: ' || l_pers || ' personal and ' || l_svc
                       || ' probable service account(s). Harden the profile only after the service'
                       || ' accounts have their own profile.');
END;
/
-- EOF -------------------------------------------------------------------------
