-- -----------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
-- -----------------------------------------------------------------------------
--  Name......: create_pdb_archive.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2025.11.18
--  Revision..: v1.0.0
--  Purpose...: Unplug a PDB into an archive file and drop the source PDB.
--              - Closes PDB if open, UNPLUG INTO <archive>, then DROP INCLUDING DATAFILES.
--  Notes.....: - Execute in CDB$ROOT as SYSDBA (pair with require_cdb_root.sql).
--              - This script DOES NOT shrink datafiles; do that beforehand if desired.
--              - Logging and SQL*Plus formatting are handled by the caller.
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
-- &2 => Archive path (optional; default: /opt/oracle/data/pdbarch/pdb26ai_<pdbname>.pdb)
COLUMN 1 NEW_VALUE 1 NOPRINT
COLUMN 2 NEW_VALUE 2 NOPRINT
SELECT '' "1" FROM dual WHERE ROWNUM = 0;
SELECT '' "2" FROM dual WHERE ROWNUM = 0;

DEFINE _PDB_NAME = &1 PDB1
DEFINE _ARCH     = &2 'default'
SET FEEDBACK ON
-- Main ------------------------------------------------------------------------
DECLARE
  l_pdb_name     cdb_pdbs.pdb_name%TYPE := UPPER('&&_PDB_NAME');
  l_archive_path VARCHAR2(1024);
  l_exists       PLS_INTEGER;
  l_sql          VARCHAR2(1000);

  -- Exceptions
  e_pdb_missing        EXCEPTION; PRAGMA EXCEPTION_INIT(e_pdb_missing,       -65011); -- PDB not found
  e_pdb_already_closed EXCEPTION; PRAGMA EXCEPTION_INIT(e_pdb_already_closed,-65254); -- already closed
  e_already_unplugged  EXCEPTION; PRAGMA EXCEPTION_INIT(e_already_unplugged, -65140); -- already unplugged (context dependent)
BEGIN
  -- Must run in CDB$ROOT
  IF sys_context('userenv','con_name') <> 'CDB$ROOT' THEN
    RAISE_APPLICATION_ERROR(-20000,'create_pdb_archive.sql must run in CDB$ROOT as SYSDBA');
  END IF;

  -- Check PDB existence
  SELECT COUNT(*) INTO l_exists FROM cdb_pdbs WHERE pdb_name = l_pdb_name;
  IF l_exists = 0 THEN
    RAISE_APPLICATION_ERROR(-20001, 'PDB '||l_pdb_name||' does not exist.');
  END IF;

  -- Resolve archive path default if &2 not provided
  IF TRIM('&&_ARCH') = 'default' THEN
    l_archive_path := '/opt/oracle/data/pdbarch/pdb26ai_'||LOWER(l_pdb_name)||'.pdb';
  ELSE
    l_archive_path := '&&_ARCH';
  END IF;

  -- Close PDB (if open)
  dbms_output.put('- Close PDB '||l_pdb_name||' ................. ');
  BEGIN
    l_sql := 'ALTER PLUGGABLE DATABASE '||l_pdb_name||' CLOSE IMMEDIATE';
    EXECUTE IMMEDIATE l_sql;
    dbms_output.put_line('closed');
  EXCEPTION
    WHEN e_pdb_already_closed THEN
      dbms_output.put_line('already closed');
  END;

  -- Unplug to archive
  dbms_output.put('- Unplug '||l_pdb_name||' to '||l_archive_path||' ... ');
  BEGIN
    l_sql := 'ALTER PLUGGABLE DATABASE '||l_pdb_name||
             ' UNPLUG INTO '''||REPLACE(l_archive_path,'''','''''')||'''';
    EXECUTE IMMEDIATE l_sql;
    dbms_output.put_line('unplugged');
    
  EXCEPTION
    WHEN e_already_unplugged THEN
      dbms_output.put_line('already unplugged');
  END;

  -- Drop PDB INCLUDING DATAFILES
  dbms_output.put('- Drop PDB '||l_pdb_name||' (incl. datafiles) .. ');
  BEGIN
    l_sql := 'DROP PLUGGABLE DATABASE '||l_pdb_name||' INCLUDING DATAFILES';
    EXECUTE IMMEDIATE l_sql;
    dbms_output.put_line('dropped');
  EXCEPTION
    WHEN e_pdb_missing THEN
      dbms_output.put_line('not found (already dropped?)');
  END;
END;
/
-- EOF -------------------------------------------------------------------------
