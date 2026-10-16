--------------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
--------------------------------------------------------------------------------
--  Name......: seclab_s06_unused_accounts.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2026.10.15
--  Revision..: v1.0.0
--  Purpose...: seclab S06 - open custom accounts that were never used.
--  Notes.....: *** INTENTIONALLY INSECURE - lab use only ***
--              - Execute in the seclab PDB as SYSDBA (pair with require_pdb.sql).
--              - &1 mode: INSECURE unlocks the accounts (setup and rollback),
--                         FIX locks them (remediation class 1: lock, not drop).
--  License...: Apache License Version 2.0, January 2004 as shown
--              at http://www.apache.org/licenses/
--------------------------------------------------------------------------------

-- Fail fast in automation -----------------------------------------------------
WHENEVER SQLERROR EXIT SQL.SQLCODE

SET FEEDBACK OFF
SET VERIFY OFF
COLUMN 1 NEW_VALUE 1 NOPRINT
SELECT '' "1" FROM dual WHERE ROWNUM = 0;
DEFINE _MODE = &1 INSECURE
SET FEEDBACK ON

PROMPT - S06 unused accounts, mode &_MODE
DECLARE
  TYPE t_list IS TABLE OF VARCHAR2(128);
  l_users t_list := t_list('OLD_APP', 'TEST_USER');
  l_mode  VARCHAR2(10) := UPPER('&&_MODE');
  l_count PLS_INTEGER;
BEGIN
  IF l_mode NOT IN ('INSECURE', 'FIX') THEN
    RAISE_APPLICATION_ERROR(-20011, 'mode must be INSECURE or FIX, got ' || l_mode);
  END IF;
  FOR i IN 1 .. l_users.COUNT LOOP
    SELECT COUNT(*) INTO l_count FROM dba_users WHERE username = l_users(i);
    IF l_count = 0 THEN
      RAISE_APPLICATION_ERROR(-20012, l_users(i) || ' does not exist - run seclab_accounts.sql first');
    END IF;
    IF l_mode = 'INSECURE' THEN
      EXECUTE IMMEDIATE 'ALTER USER ' || l_users(i) || ' ACCOUNT UNLOCK';
      dbms_output.put_line('- unlocked ' || l_users(i));
    ELSE
      EXECUTE IMMEDIATE 'ALTER USER ' || l_users(i) || ' ACCOUNT LOCK';
      dbms_output.put_line('- locked ' || l_users(i));
    END IF;
  END LOOP;
END;
/

PROMPT - Status of the S06 accounts after this step
COL username       FOR A12
COL account_status FOR A16
COL last_login     FOR A30
SELECT username, account_status, created, last_login
  FROM dba_users WHERE username IN ('OLD_APP', 'TEST_USER') ORDER BY username;
-- EOF -------------------------------------------------------------------------
