--------------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
--------------------------------------------------------------------------------
--  Name......: precheck_revoke_public.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2026.10.15
--  Revision..: v1.0.0
--  Purpose...: Pre-check before revoking EXECUTE on a package from PUBLIC:
--              list custom code that depends on it and would lose access.
--  Notes.....: - Read-only. Execute in the PDB to check, as SYSDBA or with
--                SELECT ANY DICTIONARY.
--              - &1 object name (e.g. UTL_FILE), &2 owner (default SYS).
--              - Definer rights code ignores roles: an owner without a direct
--                grant on the object works only through PUBLIC. Such objects
--                go INVALID after the revoke.
--              - Invoker rights code and dynamic SQL are not visible in
--                DBA_DEPENDENCIES - review them separately.
--  Usage.....: @precheck_revoke_public.sql UTL_FILE
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
DEFINE _OBJECT = &1
DEFINE _OWNER  = &2 SYS

DECLARE
  l_object VARCHAR2(128) := UPPER('&&_OBJECT');
  l_owner  VARCHAR2(128) := UPPER('&&_OWNER');
  l_public PLS_INTEGER;
  l_break  PLS_INTEGER := 0;
  l_ok     PLS_INTEGER := 0;
BEGIN
  SELECT COUNT(*) INTO l_public FROM dba_tab_privs
   WHERE grantee = 'PUBLIC' AND owner = l_owner AND table_name = l_object AND privilege = 'EXECUTE';
  dbms_output.put_line('Pre-check: REVOKE EXECUTE ON ' || l_owner || '.' || l_object || ' FROM PUBLIC');
  dbms_output.put_line('PUBLIC currently holds EXECUTE: ' || CASE WHEN l_public > 0 THEN 'YES' ELSE 'NO' END);

  FOR r IN (SELECT d.owner, d.name, d.type, o.status,
                   (SELECT COUNT(*) FROM dba_tab_privs p
                     WHERE p.grantee = d.owner AND p.owner = l_owner
                       AND p.table_name = l_object AND p.privilege = 'EXECUTE') AS direct_grant
              FROM dba_dependencies d
              JOIN dba_users u   ON u.username = d.owner
              JOIN dba_objects o ON o.owner = d.owner AND o.object_name = d.name AND o.object_type = d.type
             WHERE d.referenced_owner IN (l_owner, 'PUBLIC')
               AND d.referenced_name = l_object
               AND u.oracle_maintained = 'N'
             ORDER BY d.owner, d.name) LOOP
    IF r.direct_grant = 0 THEN
      l_break := l_break + 1;
      dbms_output.put_line('WOULD BREAK: ' || r.owner || '.' || r.name || ' (' || r.type || ', '
                           || r.status || ') - no direct grant, works only through PUBLIC');
    ELSE
      l_ok := l_ok + 1;
      dbms_output.put_line('OK: ' || r.owner || '.' || r.name || ' (' || r.type || ') - direct grant present');
    END IF;
  END LOOP;

  IF l_break = 0 THEN
    dbms_output.put_line('Result: no custom definer rights code depends on the PUBLIC grant ('
                         || l_ok || ' with direct grant). Revoke is safe from this angle.');
  ELSE
    dbms_output.put_line('Result: ' || l_break || ' object(s) would break. Grant EXECUTE ON '
                         || l_owner || '.' || l_object || ' directly to the owner(s) first, then revoke.');
  END IF;
END;
/
-- EOF -------------------------------------------------------------------------
