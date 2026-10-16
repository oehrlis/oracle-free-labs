--------------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
--------------------------------------------------------------------------------
--  Name......: create_dbsat_user.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2026.10.15
--  Revision..: v1.0.0
--  Purpose...: Create a dedicated, minimally privileged account for the DBSAT
--              collector (instead of SYS).
--  Notes.....: - Execute in the PDB to assess as SYSDBA (pair with require_pdb.sql).
--              - &1 user name, &2 password (from the environment, see
--                run_sql_script.sh -e).
--              - Privilege list after the DBSAT User Guide, section on the
--                collector prerequisites. It differs between DBSAT versions:
--                check it against the guide of the version in use. Each grant
--                is reported; a grant that fails is named as WARN, not hidden.
--              - Idempotent: an existing account is dropped and reported.
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
DEFINE _USER = &1 DBSAT_USER
DEFINE _PWD  = "&2"
SET FEEDBACK ON

PROMPT - Create DBSAT collector account &_USER
DECLARE
  l_user  VARCHAR2(128) := UPPER('&&_USER');
  l_count PLS_INTEGER;
  TYPE t_list IS TABLE OF VARCHAR2(200);
  l_grants t_list := t_list(
    'CREATE SESSION',
    'SELECT_CATALOG_ROLE',
    'SELECT ON sys.registry$history',
    'SELECT ON sys.dba_users_with_defpwd',
    'SELECT ON audsys.aud$unified',
    'AUDIT_VIEWER',
    'CAPTURE_ADMIN',
    'SELECT ON sys.dba_audit_mgmt_config_params');
BEGIN
  IF '&&_PWD' IS NULL THEN
    RAISE_APPLICATION_ERROR(-20010, 'create_dbsat_user.sql: password parameter is empty');
  END IF;
  SELECT COUNT(*) INTO l_count FROM dba_users WHERE username = l_user;
  IF l_count > 0 THEN
    EXECUTE IMMEDIATE 'DROP USER ' || l_user || ' CASCADE';
    dbms_output.put_line('- dropped existing user ' || l_user);
  END IF;
  EXECUTE IMMEDIATE 'CREATE USER ' || l_user || ' IDENTIFIED BY "&&_PWD"';
  dbms_output.put_line('- created user ' || l_user);
  FOR i IN 1 .. l_grants.COUNT LOOP
    BEGIN
      EXECUTE IMMEDIATE 'GRANT ' || l_grants(i) || ' TO ' || l_user;
      dbms_output.put_line('- granted ' || l_grants(i));
    EXCEPTION
      WHEN OTHERS THEN
        dbms_output.put_line('- WARN: GRANT ' || l_grants(i) || ' failed: ' || SQLERRM);
    END;
  END LOOP;
END;
/

PROMPT - Privileges of &_USER
COL privilege FOR A40
SELECT 'ROLE' AS kind, granted_role AS privilege FROM dba_role_privs WHERE grantee = UPPER('&_USER')
UNION ALL
SELECT 'SYSPRIV', privilege FROM dba_sys_privs WHERE grantee = UPPER('&_USER')
UNION ALL
SELECT 'OBJPRIV', privilege || ' ON ' || owner || '.' || table_name FROM dba_tab_privs WHERE grantee = UPPER('&_USER')
 ORDER BY 1, 2;
-- EOF -------------------------------------------------------------------------
