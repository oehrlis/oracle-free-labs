--------------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
--------------------------------------------------------------------------------
--  Name......: seclab_s01_public_grants.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2026.10.15
--  Revision..: v1.0.0
--  Purpose...: seclab S01 - custom object privileges granted to PUBLIC.
--  Notes.....: *** INTENTIONALLY INSECURE - lab use only ***
--              - Execute in the seclab PDB as SYSDBA (pair with require_pdb.sql).
--              - &1 mode: INSECURE grants to PUBLIC (setup and rollback),
--                         FIX revokes them again (remediation class 1).
--              - The grant list lives only here, so setup, fix and rollback
--                cannot drift apart.
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

PROMPT - S01 PUBLIC grants, mode &_MODE
DECLARE
  TYPE t_grant IS RECORD (priv VARCHAR2(30), obj VARCHAR2(261));
  TYPE t_grants IS TABLE OF t_grant;
  l_grants t_grants := t_grants();
  l_mode   VARCHAR2(10) := UPPER('&&_MODE');
  e_not_granted EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_not_granted, -1927);
  PROCEDURE add(p_priv VARCHAR2, p_obj VARCHAR2) IS
  BEGIN
    l_grants.EXTEND;
    l_grants(l_grants.LAST).priv := p_priv;
    l_grants(l_grants.LAST).obj  := p_obj;
  END add;
BEGIN
  add('SELECT',  'SCOTT.EMP');
  add('EXECUTE', 'APP_OWNER.APP_UTIL');

  IF l_mode NOT IN ('INSECURE', 'FIX') THEN
    RAISE_APPLICATION_ERROR(-20011, 'mode must be INSECURE or FIX, got ' || l_mode);
  END IF;

  FOR i IN 1 .. l_grants.COUNT LOOP
    IF l_mode = 'INSECURE' THEN
      EXECUTE IMMEDIATE 'GRANT ' || l_grants(i).priv || ' ON ' || l_grants(i).obj || ' TO PUBLIC';
      dbms_output.put_line('- granted ' || l_grants(i).priv || ' on ' || l_grants(i).obj || ' to PUBLIC');
    ELSE
      BEGIN
        EXECUTE IMMEDIATE 'REVOKE ' || l_grants(i).priv || ' ON ' || l_grants(i).obj || ' FROM PUBLIC';
        dbms_output.put_line('- revoked ' || l_grants(i).priv || ' on ' || l_grants(i).obj || ' from PUBLIC');
      EXCEPTION
        WHEN e_not_granted THEN
          dbms_output.put_line('- ' || l_grants(i).priv || ' on ' || l_grants(i).obj
                               || ' was not granted to PUBLIC (nothing to revoke)');
      END;
    END IF;
  END LOOP;
END;
/

PROMPT - Custom object privileges granted to PUBLIC after this step
COL owner      FOR A16
COL table_name FOR A24
COL privilege  FOR A12
SELECT owner, table_name, privilege
  FROM dba_tab_privs
 WHERE grantee = 'PUBLIC' AND owner IN ('SCOTT', 'APP_OWNER')
 ORDER BY owner, table_name;
-- EOF -------------------------------------------------------------------------
