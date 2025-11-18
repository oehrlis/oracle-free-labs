-- -----------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
-- -----------------------------------------------------------------------------
--  Name......: drop_pdb.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2025.08.21
--  Revision..: v1.0.1
--  Purpose...: Drop a pluggable database (PDB) if it exists. Closes the PDB
--              if open, then drops INCLUDING DATAFILES.
--  Notes.....: - Execute in CDB$ROOT as SYSDBA (pair with require_cdb_root.sql).
--              - Logging and SQL*Plus formatting are the caller's responsibility.
--  License...: Apache License Version 2.0, January 2004 as shown
--              at http://www.apache.org/licenses/
-- -----------------------------------------------------------------------------

-- Fail fast in automation -----------------------------------------------------
WHENEVER SQLERROR EXIT SQL.SQLCODE

-- SQL*Plus formatting ---------------------------------------------------------
SET LINESIZE 256 PAGESIZE 1000
SET SERVEROUTPUT ON
SET FEEDBACK OFF
SET VERIFY OFF

-- Parameters ------------------------------------------------------------------
-- &1 => PDB name (optional; default: PDB1)
COLUMN 1 NEW_VALUE 1 NOPRINT
SELECT '' "1" FROM dual WHERE ROWNUM = 0;

DEFINE _PDB_NAME = &1 PDB1
SET FEEDBACK ON
-- Main ------------------------------------------------------------------------
-- Must run in CDB$ROOT (prefer also calling require_cdb_root.sql before this
DECLARE
  l_pdbpname   dba_pdbs.pdb_name%TYPE := UPPER('&&_PDB_NAME');
  l_exists     PLS_INTEGER;
  l_sql        VARCHAR2(1000);
  e_already_closed EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_already_closed, -65020); -- PDB already closed
BEGIN
  -- Must run in CDB$ROOT
  IF sys_context('userenv','con_name') <> 'CDB$ROOT' THEN
    RAISE_APPLICATION_ERROR(-20000,'drop_pdb.sql must run in CDB$ROOT as SYSDBA');
  END IF;

  -- Check existence
  SELECT COUNT(*) INTO l_exists FROM cdb_pdbs WHERE pdb_name = l_pdbpname;

  IF l_exists = 0 THEN
    dbms_output.put_line('- PDB '||l_pdbpname||' does not exist (nothing to do)');
    RETURN;
  END IF;

  -- Close PDB (if open)
  dbms_output.put('- Close '||l_pdbpname||' ... ');
  BEGIN
    l_sql := 'ALTER PLUGGABLE DATABASE '||l_pdbpname||' CLOSE IMMEDIATE';
    EXECUTE IMMEDIATE l_sql;
    dbms_output.put_line('closed');
  EXCEPTION
    WHEN e_already_closed THEN
      dbms_output.put_line('already closed');
  END;

  -- Drop PDB (including datafiles)
  dbms_output.put('- Drop '||l_pdbpname||' ... ');
  l_sql := 'DROP PLUGGABLE DATABASE '||l_pdbpname||' INCLUDING DATAFILES';
  EXECUTE IMMEDIATE l_sql;
  dbms_output.put_line('dropped');
END;
/
SET VERIFY ON
-- EOF -------------------------------------------------------------------------
