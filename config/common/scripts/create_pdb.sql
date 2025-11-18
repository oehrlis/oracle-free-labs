-- -----------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
-- -----------------------------------------------------------------------------
--  Name......: create_pdb.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2025.11.18
--  Revision..: v1.0.0
--  Purpose...: Create a PDB from PDB$SEED (if not existing), open it RW, save
--              state. Admin user defaults to PDBADMIN with a random password.
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
-- &1 => PDB name (required)
-- &2 => Admin user name (optional, default: PDBADMIN)
COLUMN 1 NEW_VALUE 1 NOPRINT
COLUMN 2 NEW_VALUE 2 NOPRINT
SELECT '' "1" FROM dual WHERE ROWNUM = 0;
SELECT '' "2" FROM dual WHERE ROWNUM = 0;

DEFINE _PDB_NAME = &1
DEFINE _ADMINUSR = &2 PDBADMIN
SET FEEDBACK ON

-- Main ------------------------------------------------------------------------
-- Must run in CDB$ROOT (prefer also calling require_cdb_root.sql before this)
DECLARE
  l_pdbpname          cdb_pdbs.pdb_name%TYPE  := UPPER('&&_PDB_NAME');
  l_user              cdb_users.username%TYPE := UPPER('&&_ADMINUSR');
  l_create_file_dest  cdb_data_files.file_name%TYPE;
  l_db_unique_name    v$database.db_unique_name%TYPE;
  l_password          VARCHAR2(64);
  l_sql               VARCHAR2(1000);
  l_exists            NUMBER;
  e_pdb_exists EXCEPTION;
  e_pdb_open   EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_pdb_exists, -65012);
  PRAGMA EXCEPTION_INIT(e_pdb_open,   -65019);
BEGIN
  -- Must run in CDB$ROOT (prefer also calling require_cdb_root.sql before this)
  IF sys_context('userenv','con_name') <> 'CDB$ROOT' THEN
    RAISE_APPLICATION_ERROR(-20000,'create_pdb.sql must run in CDB$ROOT as SYSDBA');
  END IF;

  -- Check if PDB already exists
  SELECT COUNT(*) INTO l_exists FROM cdb_pdbs WHERE pdb_name = l_pdbpname;
  IF l_exists > 0 THEN
    dbms_output.put_line('- PDB '||l_pdbpname||' already exists (skipping create)');
  ELSE
    -- Derive CREATE_FILE_DEST from an existing SYSTEM datafile path
    SELECT regexp_substr(file_name, '^/.*/')
      INTO l_create_file_dest
      FROM cdb_data_files
     WHERE tablespace_name='SYSTEM' AND ROWNUM=1;

    SELECT db_unique_name INTO l_db_unique_name FROM v$database;

    -- Remove DB unique name segment if present
    l_create_file_dest := REPLACE(l_create_file_dest, '/'||UPPER(l_db_unique_name)||'/', '/');
    l_create_file_dest := REPLACE(l_create_file_dest, '/'||LOWER(l_db_unique_name)||'/', '/');

    -- Generate random password (avoid quotes)
    l_password := REPLACE(DBMS_RANDOM.STRING('p', 20), '"', 'x');

    dbms_output.put_line('- Create '||l_pdbpname||' at '||l_create_file_dest);
    l_sql := 'CREATE PLUGGABLE DATABASE '||l_pdbpname||
             ' ADMIN USER '||l_user||' IDENTIFIED BY "'||l_password||'" '||
             ' CREATE_FILE_DEST='''||l_create_file_dest||'''';
    EXECUTE IMMEDIATE l_sql;
    dbms_output.put_line('- PDB created with admin user '||l_user);
  END IF;

  -- Open PDB and save state
  BEGIN
    EXECUTE IMMEDIATE 'ALTER PLUGGABLE DATABASE '||l_pdbpname||' OPEN READ WRITE';
    dbms_output.put_line('- PDB opened');
  EXCEPTION
    WHEN e_pdb_open THEN
      dbms_output.put_line('- PDB already open');
  END;

  EXECUTE IMMEDIATE 'ALTER PLUGGABLE DATABASE '||l_pdbpname||' SAVE STATE';
  dbms_output.put_line('- PDB state saved');
END;
/

SET VERIFY ON
-- EOF -------------------------------------------------------------------------
