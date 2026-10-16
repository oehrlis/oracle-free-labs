--------------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
--------------------------------------------------------------------------------
--  Name......: seclab_s11_default_password.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2026.10.15
--  Revision..: v1.0.0
--  Purpose...: seclab S11 - sample schema SCOTT open with its well-known
--              default password.
--  Notes.....: *** INTENTIONALLY INSECURE - lab use only ***
--              - Execute in the seclab PDB as SYSDBA (pair with require_pdb.sql).
--              - Requires create_scott.sql (creates SCOTT without password).
--              - &1 mode: INSECURE sets the password &2 (SECLAB_SCOTT_PWD,
--                the documented default) and unlocks the account;
--                FIX sets a random password and locks the account.
--  License...: Apache License Version 2.0, January 2004 as shown
--              at http://www.apache.org/licenses/
--------------------------------------------------------------------------------

-- Fail fast in automation -----------------------------------------------------
WHENEVER SQLERROR EXIT SQL.SQLCODE

SET FEEDBACK OFF
SET VERIFY OFF
COLUMN 1 NEW_VALUE 1 NOPRINT
COLUMN 2 NEW_VALUE 2 NOPRINT
SELECT '' "1" FROM dual WHERE ROWNUM = 0;
SELECT '' "2" FROM dual WHERE ROWNUM = 0;
DEFINE _MODE = &1 INSECURE
DEFINE _PWD  = "&2"
SET FEEDBACK ON

PROMPT - S11 SCOTT default password, mode &_MODE
DECLARE
  l_mode VARCHAR2(10) := UPPER('&&_MODE');
BEGIN
  IF l_mode = 'INSECURE' THEN
    IF '&&_PWD' IS NULL THEN
      RAISE_APPLICATION_ERROR(-20010, 'INSECURE mode needs the password as second parameter');
    END IF;
    EXECUTE IMMEDIATE 'ALTER USER scott IDENTIFIED BY "&&_PWD" ACCOUNT UNLOCK';
    dbms_output.put_line('- SCOTT password set to the configured default, account unlocked');
  ELSIF l_mode = 'FIX' THEN
    EXECUTE IMMEDIATE 'ALTER USER scott IDENTIFIED BY "'
                      || REPLACE(dbms_random.string('a', 24), '"', 'x') || '1#" ACCOUNT LOCK';
    dbms_output.put_line('- SCOTT password set to a random value, account locked');
  ELSE
    RAISE_APPLICATION_ERROR(-20011, 'mode must be INSECURE or FIX, got ' || l_mode);
  END IF;
END;
/

PROMPT - Accounts with default passwords after this step
COL username FOR A16
SELECT d.username, u.account_status, u.password_versions
  FROM dba_users_with_defpwd d JOIN dba_users u ON u.username = d.username
 WHERE u.oracle_maintained = 'N'
 ORDER BY d.username;
-- EOF -------------------------------------------------------------------------
