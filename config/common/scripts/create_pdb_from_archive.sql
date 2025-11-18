--------------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
--------------------------------------------------------------------------------
--  Name......: create_pdb_from_archive.sql
--  Author....: Stefan Oehrli (oes), stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2025.08.19
--  Revision..: v1.0.0
--  Purpose...: Create a pluggable database (PDB) from an existing PDB archive
--              file (XML/metadata). Checks compatibility, creates the PDB,
--              opens it in READ WRITE mode, and saves its state.
--  Notes.....:
--    - Must be executed in CDB$ROOT as SYSDBA.
--    - Default values:
--        pdb_name    = odbseed
--        pdb_archive = /opt/oracle/data/pdbarch/pdb23ai_odbseed.pdb
--  Reference.: DBMS_PDB.CHECK_PLUG_COMPATIBILITY, CREATE PLUGGABLE DATABASE
--  License...: Apache License Version 2.0, January 2004
--              http://www.apache.org/licenses/
--------------------------------------------------------------------------------

-- Fail fast in automation -----------------------------------------------------
WHENEVER SQLERROR EXIT SQL.SQLCODE

-- SQL*Plus formatting ---------------------------------------------------------
SET LINESIZE 256 PAGESIZE 1000
SET SERVEROUTPUT ON
SET FEEDBACK OFF
SET VERIFY OFF

-- Parameters ------------------------------------------------------------------
-- &1 => PDB name (optional; default: PDB1)
-- &2 => Archive path (optional; default: /opt/oracle/data/pdbarch/pdb23ai_<pdbname>.pdb)
COLUMN 1 NEW_VALUE 1 NOPRINT
COLUMN 2 NEW_VALUE 2 NOPRINT
SELECT '' "1" FROM dual WHERE ROWNUM = 0;
SELECT '' "2" FROM dual WHERE ROWNUM = 0;

DEFINE _PDB_NAME = &1 'odbseed'
DEFINE _PDB_ARCH = &2 '/opt/oracle/data/pdbarch/pdb23ai_odbseed.pdb'
SET FEEDBACK ON

-- Main ------------------------------------------------------------------------
DECLARE
    l_pdbpname          cdb_pdbs.pdb_name%TYPE          := '&&_PDB_NAME';
    l_pdb_archive       cdb_data_files.file_name%TYPE   := '&&_PDB_ARCH';
    l_create_file_dest  cdb_data_files.file_name%TYPE;
    l_db_unique_name    v$database.db_unique_name%TYPE;
    l_result BOOLEAN;
    l_sql               VARCHAR2(512 CHAR);         -- local variable for sql used in EXECUTE IMMEDIATE NOSONAR
    e_pdb_exists        EXCEPTION;
    e_pdb_open          EXCEPTION;
    PRAGMA exception_init ( e_pdb_exists, -65012 );
    PRAGMA exception_init ( e_pdb_open, -65019 );

BEGIN
    <<get_metadata>>
    BEGIN
        SELECT
            regexp_substr(file_name, '^/.*/')
        INTO l_create_file_dest
        FROM
             cdb_data_files
        WHERE
                tablespace_name = 'SYSTEM'
            AND ROWNUM < 2;

        SELECT
            db_unique_name
        INTO l_db_unique_name
        FROM
            v$database;

    EXCEPTION
    WHEN no_data_found THEN
        RAISE;
    WHEN too_many_rows THEN
        RAISE;
    END get_metadata;

    -- check compatibility
    l_result := sys.dbms_pdb.check_plug_compatibility(
                pdb_descr_file => l_pdb_archive,
                pdb_name       => l_pdbpname);

    IF l_result THEN
        sys.dbms_output.put_line('- PDB archive '||l_pdb_archive||' is compatible');
    ELSE
        raise_application_error(-20001, 'PDB archive '||l_pdb_archive||' is incompatible.');
    END IF;

    -- Remove the database unique name from the l_create_file_dest
    l_create_file_dest := replace(l_create_file_dest, '/' || upper(l_db_unique_name) || '/', '/');
    l_create_file_dest := replace(l_create_file_dest, '/' || lower(l_db_unique_name) || '/', '/');

    sys.dbms_output.put('- Create '|| l_pdbpname|| ' ... ');
    <<create_pdb>>
    BEGIN
        l_sql := 'CREATE PLUGGABLE DATABASE '
            || l_pdbpname
            || ' USING '''
            || l_pdb_archive
            || ''' CREATE_FILE_DEST='''||l_create_file_dest||'''';

        EXECUTE IMMEDIATE l_sql;
        sys.dbms_output.put_line('created');

    EXCEPTION
        WHEN e_pdb_exists THEN
            sys.dbms_output.put_line('already exists');
    END create_pdb;

    sys.dbms_output.put('- '|| l_pdbpname|| ' open ..... ');
    
    <<configure_pdb>>
    BEGIN
        l_sql := 'ALTER PLUGGABLE DATABASE '|| l_pdbpname|| ' OPEN READ WRITE';
        EXECUTE IMMEDIATE l_sql;
        sys.dbms_output.put_line('open');
    EXCEPTION
        WHEN e_pdb_open THEN
            sys.dbms_output.put_line('already open');
    END configure_pdb;

    sys.dbms_output.put_line('- '|| l_pdbpname|| ' save state');
    l_sql := 'ALTER PLUGGABLE DATABASE '|| l_pdbpname|| ' SAVE STATE';
    EXECUTE IMMEDIATE l_sql;
END;
/

-- EOF -------------------------------------------------------------------------