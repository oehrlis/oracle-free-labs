-- -----------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
-- -----------------------------------------------------------------------------
--  Name......: create_ts_users.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2025.11.18
--  Revision..: v1.0.0
--  Purpose...: Create (if needed) a BIGFILE tablespace and set it as the
--              database default tablespace (PDB context).
--  Notes.....: - Must be executed in a PDB (not CDB$ROOT). Pair with require_pdb.sql.
--              - SQL*Plus formatting and logging should be handled by the caller.
--  License...: Apache License Version 2.0, January 2004 as shown
--              at http://www.apache.org/licenses/
-- -----------------------------------------------------------------------------

-- Fail fast in automation -----------------------------------------------------
WHENEVER SQLERROR EXIT SQL.SQLCODE

-- SQL*Plus formatting ---------------------------------------------------------
SET LINESIZE 256 PAGESIZE 1000
SET SERVEROUTPUT ON
SET FEEDBACK OFF

-- Parameters (defaults)
--   &1 => tablespace name (default: USERS)
--   &2 => initial size (default: 20480K)
COLUMN 1 NEW_VALUE 1 NOPRINT
COLUMN 2 NEW_VALUE 2 NOPRINT
SELECT '' "1" FROM dual WHERE ROWNUM = 0;
SELECT '' "2" FROM dual WHERE ROWNUM = 0;

DEFINE _TS_NAME = &1 USERS
DEFINE _TS_SIZE = &2 20480K

SET FEEDBACK ON

-- Main ------------------------------------------------------------------------
-- Must not run in CDB$ROOT (caller should also include require_pdb.sql)
DECLARE
  l_ts_name   VARCHAR2(30) := UPPER('&&_TS_NAME');
  l_size      VARCHAR2(30) := '&&_TS_SIZE';
  e_ts_exists EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_ts_exists, -1543);
BEGIN
  -- Must not run in CDB$ROOT (caller should also include require_pdb.sql)
  IF sys_context('userenv','con_name') = 'CDB$ROOT' THEN
    RAISE_APPLICATION_ERROR(-20001,'create_ts_users.sql must run in a PDB (not CDB$ROOT)');
  END IF;

  -- Create tablespace if it does not exist
  BEGIN
    EXECUTE IMMEDIATE
      'CREATE BIGFILE TABLESPACE '||l_ts_name||
      ' DATAFILE SIZE '||l_size||' AUTOEXTEND ON NEXT 10M MAXSIZE UNLIMITED';
    dbms_output.put_line('- Tablespace '||l_ts_name||' created ('||l_size||')');
  EXCEPTION
    WHEN e_ts_exists THEN
      dbms_output.put_line('- Tablespace '||l_ts_name||' already exists (skipping create)');
  END;

  -- Set as default tablespace
  EXECUTE IMMEDIATE 'ALTER DATABASE DEFAULT TABLESPACE '||l_ts_name;
  dbms_output.put_line('- Default tablespace set to '||l_ts_name);
END;
/
-- EOF -------------------------------------------------------------------------
