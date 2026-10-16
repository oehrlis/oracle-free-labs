--------------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
--------------------------------------------------------------------------------
--  Name......: precheck_logon_version.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2026.10.15
--  Revision..: v1.0.0
--  Purpose...: Pre-check before raising SQLNET.ALLOWED_LOGON_VERSION_SERVER:
--              list password accounts that would be locked out and those that
--              still carry legacy verifiers.
--  Notes.....: - Read-only. Execute in the PDB to check, as SYSDBA or with
--                SELECT ANY DICTIONARY.
--              - &1 target value: 12a (default, 12C verifier only) or 12
--                (11G or 12C verifier required).
--              - Order of the remediation: first reset the passwords listed
--                as WOULD LOCK OUT (under the new setting they get a 12C
--                verifier), then raise the parameter. The reverse order locks
--                these accounts out.
--  Usage.....: @precheck_logon_version.sql 12a
--  License...: Apache License Version 2.0, January 2004 as shown
--              at http://www.apache.org/licenses/
--------------------------------------------------------------------------------

-- Fail fast in automation -----------------------------------------------------
WHENEVER SQLERROR EXIT SQL.SQLCODE

SET FEEDBACK OFF
SET VERIFY OFF
SET SERVEROUTPUT ON SIZE UNLIMITED
COLUMN 1 NEW_VALUE 1 NOPRINT
SELECT '' "1" FROM dual WHERE ROWNUM = 0;
DEFINE _TARGET = &1 12a

DECLARE
  l_target VARCHAR2(10) := LOWER('&&_TARGET');
  l_lock   PLS_INTEGER := 0;
  l_legacy PLS_INTEGER := 0;
  l_usable BOOLEAN;
BEGIN
  IF l_target NOT IN ('12a', '12') THEN
    RAISE_APPLICATION_ERROR(-20013, 'target must be 12a or 12, got ' || l_target);
  END IF;
  dbms_output.put_line('Pre-check: SQLNET.ALLOWED_LOGON_VERSION_SERVER = ' || l_target);

  FOR r IN (SELECT username, account_status, password_versions
              FROM dba_users
             WHERE authentication_type = 'PASSWORD'
               AND password_versions IS NOT NULL
             ORDER BY username) LOOP
    IF l_target = '12a' THEN
      l_usable := r.password_versions LIKE '%12C%';
    ELSE
      l_usable := r.password_versions LIKE '%12C%' OR r.password_versions LIKE '%11G%';
    END IF;
    IF NOT l_usable THEN
      l_lock := l_lock + 1;
      dbms_output.put_line('WOULD LOCK OUT: ' || r.username || ' (' || TRIM(r.password_versions)
                           || ', ' || r.account_status || ') - reset the password first');
    ELSIF r.password_versions LIKE '%10G%' OR r.password_versions LIKE '%11G%' THEN
      l_legacy := l_legacy + 1;
      dbms_output.put_line('LEGACY VERIFIER: ' || r.username || ' (' || TRIM(r.password_versions)
                           || ') - can log in, but the old verifier stays until the password is reset');
    END IF;
  END LOOP;

  dbms_output.put_line('Result: ' || l_lock || ' account(s) would be locked out, '
                       || l_legacy || ' account(s) keep a legacy verifier.');
END;
/
-- EOF -------------------------------------------------------------------------
