-- -----------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
-- -----------------------------------------------------------------------------
--  Name......: clone_pdb.sql
--  Author....: Stefan Oehrli (oes), stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2025.08.21
--  Revision..: v1.0.0
--  Purpose...: Clone a source PDB into a new target PDB.
--              Defaults:
--                - Source PDB : ODBSEED
--                - Target PDB : ODBDEMO
--  Notes.....:
--    - Must be executed in CDB$ROOT as SYSDBA.
--    - Target PDB is created with admin user PDBADMIN and a random password.
--    - If the target PDB already exists, the script will skip creation.
--    - Action log is written to spool file:
--        clone_pdb_<db_name>_<src_pdb>_to_<tgt_pdb>_<log_date>.log
--  Reference.: CREATE PLUGGABLE DATABASE ... FROM, ALTER PLUGGABLE DATABASE
--  License...: Apache License Version 2.0, January 2004
--              http://www.apache.org/licenses/
-- -----------------------------------------------------------------------------

-- Fail fast in automation -----------------------------------------------------
WHENEVER SQLERROR EXIT SQL.SQLCODE

-- SQL*Plus formatting ---------------------------------------------------------
SET LINESIZE 256 PAGESIZE 1000
SET SERVEROUTPUT ON
SET FEEDBACK OFF
SET VERIFY OFF

-- Parameters ------------------------------------------------------------------
-- &1 => Source PDB (required)
-- &2 => Target PDB (required)
COLUMN 1 NEW_VALUE 1 NOPRINT
COLUMN 2 NEW_VALUE 2 NOPRINT
SELECT '' "1" FROM dual WHERE ROWNUM = 0;
SELECT '' "2" FROM dual WHERE ROWNUM = 0;

DEFINE _PDB_SOURCE = &1 
DEFINE _PDB_TARGET = &2
SET FEEDBACK ON

-- Main ------------------------------------------------------------------------
DECLARE
  l_src_pdb    cdb_pdbs.pdb_name%TYPE := UPPER('&&_PDB_SOURCE');
  l_tgt_pdb    cdb_pdbs.pdb_name%TYPE := UPPER('&&_PDB_TARGET');
  l_exists     NUMBER;
  l_create_file_dest VARCHAR2(512);
  l_sql        VARCHAR2(1024);

  e_pdb_exists EXCEPTION; PRAGMA EXCEPTION_INIT(e_pdb_exists,-65012);

BEGIN
  -- check if target already exists
  SELECT COUNT(*) INTO l_exists FROM cdb_pdbs WHERE pdb_name = l_tgt_pdb;
  IF l_exists > 0 THEN
    dbms_output.put_line('- Target PDB '||l_tgt_pdb||' already exists. Skipping.');
    RETURN;
  END IF;

  -- determine create file dest
  SELECT regexp_substr(file_name, '^/.*/')
    INTO l_create_file_dest
    FROM cdb_data_files
   WHERE tablespace_name='SYSTEM' AND ROWNUM=1;

  -- create pluggable database from source
  dbms_output.put('- Clone '||l_src_pdb||' to '||l_tgt_pdb||' ... ');
  BEGIN
    l_sql := 'CREATE PLUGGABLE DATABASE '||l_tgt_pdb||
             ' FROM '||l_src_pdb||
             ' CREATE_FILE_DEST='''||l_create_file_dest||'''';
    EXECUTE IMMEDIATE l_sql;

    dbms_output.put_line('created');
  EXCEPTION
    WHEN e_pdb_exists THEN
      dbms_output.put_line('already exists');
  END;

  -- open target
  dbms_output.put('- Open PDB '||l_tgt_pdb||' ... ');
  l_sql := 'ALTER PLUGGABLE DATABASE '||l_tgt_pdb||' OPEN READ WRITE';
  EXECUTE IMMEDIATE l_sql;
  dbms_output.put_line('open');

  -- save state
  dbms_output.put_line('- Save state for '||l_tgt_pdb);
  l_sql := 'ALTER PLUGGABLE DATABASE '||l_tgt_pdb||' SAVE STATE';
  EXECUTE IMMEDIATE l_sql;
END;
/

-- EOF -------------------------------------------------------------------------
