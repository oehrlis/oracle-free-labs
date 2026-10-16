--------------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
--------------------------------------------------------------------------------
--  Name......: seclab_verify.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2026.10.15
--  Revision..: v1.0.0
--  Purpose...: seclab - read-only proof of every catalogued scenario. Prints
--              one line per ID: "<ID> PRESENT|ABSENT|NOT REPRODUCIBLE - <evidence>".
--  Notes.....: - Execute in the seclab PDB as SYSDBA. Changes nothing.
--              - sqlnet.ora is read by the caller (seclab_verify.sh) and passed
--                in: &1 SQLNET.ALLOWED_LOGON_VERSION_SERVER,
--                &2 SQLNET.ENCRYPTION_SERVER, &3 SQLNET.CRYPTO_CHECKSUM_SERVER
--                (empty = not set).
--              - The exit code is set by seclab_verify.sh from the ABSENT count.
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
COLUMN 3 NEW_VALUE 3 NOPRINT
SELECT '' "1" FROM dual WHERE ROWNUM = 0;
SELECT '' "2" FROM dual WHERE ROWNUM = 0;
SELECT '' "3" FROM dual WHERE ROWNUM = 0;
DEFINE _ALVS = "&1"
DEFINE _ENC  = "&2"
DEFINE _CHK  = "&3"

DECLARE
  l_n    NUMBER;
  l_n2   NUMBER;
  l_n3   NUMBER;
  l_txt  VARCHAR2(4000);
  l_alvs VARCHAR2(30) := UPPER(TRIM('&&_ALVS'));
  l_enc  VARCHAR2(30) := UPPER(TRIM('&&_ENC'));
  l_chk  VARCHAR2(30) := UPPER(TRIM('&&_CHK'));

  PROCEDURE result(p_id VARCHAR2, p_present BOOLEAN, p_evidence VARCHAR2) IS
  BEGIN
    dbms_output.put_line(p_id || ' ' || CASE WHEN p_present THEN 'PRESENT' ELSE 'ABSENT' END
                         || ' - ' || p_evidence);
  END result;
BEGIN
  -- S01 custom object privileges granted to PUBLIC -----------------------------
  SELECT COUNT(*), LISTAGG(privilege || ' ON ' || owner || '.' || table_name, ', ')
    INTO l_n, l_txt
    FROM dba_tab_privs
   WHERE grantee = 'PUBLIC' AND owner IN ('SCOTT', 'APP_OWNER');
  result('S01', l_n > 0, l_n || ' custom grant(s) to PUBLIC: ' || NVL(l_txt, 'none'));

  -- S02 application code depends on UTL_FILE only through PUBLIC ---------------
  SELECT COUNT(*) INTO l_n FROM dba_tab_privs
   WHERE grantee = 'PUBLIC' AND owner = 'SYS' AND table_name = 'UTL_FILE' AND privilege = 'EXECUTE';
  SELECT COUNT(*) INTO l_n2 FROM dba_dependencies
   WHERE owner = 'APP_OWNER' AND name = 'APP_EXPORT' AND referenced_name = 'UTL_FILE';
  SELECT COUNT(*) INTO l_n3 FROM dba_tab_privs
   WHERE grantee = 'APP_OWNER' AND owner = 'SYS' AND table_name = 'UTL_FILE';
  result('S02', l_n > 0 AND l_n2 > 0 AND l_n3 = 0,
         'PUBLIC EXECUTE on UTL_FILE=' || l_n || ', APP_EXPORT depends on UTL_FILE=' || l_n2
         || ', direct grant to APP_OWNER=' || l_n3);

  -- S03 low logon version + account with a legacy verifier ---------------------
  SELECT COUNT(*), MAX(password_versions) INTO l_n, l_txt FROM dba_users
   WHERE username = 'LEGACY_APP'
     AND (password_versions LIKE '%10G%' OR password_versions LIKE '%11G%');
  result('S03', l_n > 0 AND REGEXP_LIKE(l_alvs, '^(8|9|10|11)$'),
         'ALLOWED_LOGON_VERSION_SERVER=' || NVL(l_alvs, '<not set>')
         || ', LEGACY_APP password_versions=' || NVL(l_txt, '<no legacy verifier>'));

  -- S04 weak profile used by personal and service accounts ---------------------
  SELECT COUNT(*) INTO l_n FROM dba_profiles
   WHERE profile = 'SECLAB_UNLIMITED'
     AND ((resource_name IN ('FAILED_LOGIN_ATTEMPTS', 'PASSWORD_LIFE_TIME') AND limit = 'UNLIMITED')
       OR (resource_name = 'PASSWORD_VERIFY_FUNCTION' AND limit = 'NULL'));
  SELECT COUNT(*), LISTAGG(username, ',') WITHIN GROUP (ORDER BY username) INTO l_n2, l_txt
    FROM dba_users WHERE profile = 'SECLAB_UNLIMITED';
  SELECT COUNT(*) INTO l_n3 FROM dba_users WHERE profile = 'SECLAB_UNLIMITED' AND username = 'SVC_BATCH';
  result('S04', l_n = 3 AND l_n2 > 1 AND l_n3 = 1,
         'SECLAB_UNLIMITED weak limits=' || l_n || '/3, assigned to ' || NVL(l_txt, 'nobody'));

  -- S05 over-privileged accounts -------------------------------------------------
  SELECT COUNT(*) INTO l_n FROM dba_role_privs WHERE grantee = 'APP_OWNER' AND granted_role = 'DBA';
  SELECT COUNT(*) INTO l_n2 FROM dba_sys_privs WHERE grantee = 'DEV_USER1' AND privilege = 'SELECT ANY TABLE';
  SELECT COUNT(*) INTO l_n3 FROM dba_sys_privs
   WHERE grantee = 'ANALYST1' AND privilege = 'SELECT ANY TABLE' AND admin_option = 'YES';
  result('S05', l_n > 0 AND l_n2 > 0 AND l_n3 > 0,
         'APP_OWNER has DBA=' || l_n || ', DEV_USER1 SELECT ANY TABLE=' || l_n2
         || ', ANALYST1 SELECT ANY TABLE WITH ADMIN OPTION=' || l_n3);

  -- S06 open, never used custom accounts -----------------------------------------
  SELECT COUNT(*), LISTAGG(username, ',') WITHIN GROUP (ORDER BY username) INTO l_n, l_txt
    FROM dba_users
   WHERE username IN ('OLD_APP', 'TEST_USER') AND account_status = 'OPEN' AND last_login IS NULL;
  result('S06', l_n > 0, l_n || ' open account(s) never logged in: ' || NVL(l_txt, 'none'));

  -- S07 incomplete Unified Audit configuration -----------------------------------
  SELECT COUNT(*) INTO l_n FROM audit_unified_enabled_policies e
   WHERE e.policy_name IN (SELECT policy_name FROM audit_unified_policies
                            WHERE audit_option IN ('LOGON', 'LOGOFF')
                               OR (audit_option = 'ALL' AND audit_option_type = 'STANDARD ACTION'));
  SELECT COUNT(*) INTO l_n2 FROM audit_unified_enabled_policies e
   WHERE e.policy_name IN (SELECT policy_name FROM audit_unified_policies
                            WHERE object_schema IN ('SCOTT', 'TVD_HR', 'APP_OWNER'));
  SELECT COUNT(*) INTO l_n3 FROM dba_audit_mgmt_cleanup_jobs WHERE audit_trail LIKE 'UNIFIED%';
  result('S07', l_n = 0 AND l_n2 = 0 AND l_n3 = 0,
         'enabled logon policies=' || l_n || ', enabled policies on sensitive schemas=' || l_n2
         || ', unified purge jobs=' || l_n3);

  -- S08 no keystore, no encrypted tablespace -------------------------------------
  SELECT COUNT(*) INTO l_n FROM dba_tablespaces WHERE encrypted = 'YES';
  SELECT COUNT(*), MAX(status) INTO l_n2, l_txt FROM v$encryption_wallet
   WHERE con_id = sys_context('userenv', 'con_id') AND status = 'OPEN';
  SELECT MAX(status) INTO l_txt FROM v$encryption_wallet WHERE con_id = sys_context('userenv', 'con_id');
  result('S08', l_n = 0 AND l_n2 = 0,
         'encrypted tablespaces=' || l_n || ', keystore status=' || NVL(l_txt, '<no row>'));

  -- S09 network encryption not enforced ------------------------------------------
  result('S09', NVL(l_enc, 'ACCEPTED') <> 'REQUIRED' AND NVL(l_chk, 'ACCEPTED') <> 'REQUIRED',
         'SQLNET.ENCRYPTION_SERVER=' || NVL(l_enc, '<not set>')
         || ', SQLNET.CRYPTO_CHECKSUM_SERVER=' || NVL(l_chk, '<not set>'));

  -- S10 static security parameter weakened ---------------------------------------
  SELECT MAX(UPPER(value)) INTO l_txt FROM v$parameter WHERE name = 'sql92_security';
  result('S10', l_txt = 'FALSE', 'sql92_security=' || NVL(l_txt, '<unknown>'));

  -- S11 sample schema with its default password ----------------------------------
  SELECT COUNT(*), MAX(u.account_status) INTO l_n, l_txt
    FROM dba_users_with_defpwd d JOIN dba_users u ON u.username = d.username
   WHERE d.username = 'SCOTT' AND u.account_status = 'OPEN';
  result('S11', l_n > 0, 'SCOTT open with default password=' || l_n);
END;
/
-- EOF -------------------------------------------------------------------------
