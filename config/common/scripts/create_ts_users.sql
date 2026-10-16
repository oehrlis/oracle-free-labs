-- -----------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
-- -----------------------------------------------------------------------------
--  Name......: create_ts_users.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2025.11.18
--  Revision..: v1.1.0
--  Purpose...: Create (if needed) a BIGFILE tablespace and set it as the
--              database default tablespace (PDB context).
--  Notes.....: - Must be executed in a PDB (not CDB$ROOT). Pair with require_pdb.sql.
--              - SQL*Plus formatting and logging should be handled by the caller.
--              - v1.1.0: without OMF (db_create_file_dest empty, e.g. FREEPDB1
--                of the Oracle image) the datafile is placed next to the
--                SYSTEM datafile of the PDB. With OMF nothing changes.
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
  l_omf       v$parameter.value%TYPE;
  l_system    dba_data_files.file_name%TYPE;
  l_datafile  VARCHAR2(600);
  l_exists    PLS_INTEGER;
  e_ts_exists EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_ts_exists, -1543);
BEGIN
  -- Must not run in CDB$ROOT (caller should also include require_pdb.sql)
  IF sys_context('userenv','con_name') = 'CDB$ROOT' THEN
    RAISE_APPLICATION_ERROR(-20001,'create_ts_users.sql must run in a PDB (not CDB$ROOT)');
  END IF;

  -- Check first: Oracle validates the file name before the name clash, so a
  -- CREATE without OMF fails with ORA-02236 even if the tablespace exists.
  SELECT COUNT(*) INTO l_exists FROM dba_tablespaces WHERE tablespace_name = l_ts_name;
  IF l_exists > 0 THEN
    dbms_output.put_line('- Tablespace '||l_ts_name||' already exists (skipping create)');
  ELSE
    SELECT value INTO l_omf FROM v$parameter WHERE name = 'db_create_file_dest';
    IF l_omf IS NULL THEN
      -- No OMF: next to the SYSTEM datafile of this PDB, or its ASM disk group
      SELECT file_name INTO l_system FROM dba_data_files
       WHERE tablespace_name = 'SYSTEM' AND ROWNUM = 1;
      IF l_system LIKE '+%' THEN
        l_datafile := regexp_substr(l_system, '^[^/]+');
      ELSE
        l_datafile := regexp_substr(l_system, '^/.*/') || LOWER(l_ts_name) || '01.dbf';
      END IF;
    END IF;
    BEGIN
      IF l_datafile IS NULL THEN
        EXECUTE IMMEDIATE
          'CREATE BIGFILE TABLESPACE '||l_ts_name||
          ' DATAFILE SIZE '||l_size||' AUTOEXTEND ON NEXT 10M MAXSIZE UNLIMITED';
      ELSE
        EXECUTE IMMEDIATE
          'CREATE BIGFILE TABLESPACE '||l_ts_name||
          ' DATAFILE '||DBMS_ASSERT.ENQUOTE_LITERAL(l_datafile)||
          ' SIZE '||l_size||' AUTOEXTEND ON NEXT 10M MAXSIZE UNLIMITED';
      END IF;
      dbms_output.put_line('- Tablespace '||l_ts_name||' created ('||l_size||', '||
                           NVL(l_datafile, 'OMF')||')');
    EXCEPTION
      WHEN e_ts_exists THEN
        dbms_output.put_line('- Tablespace '||l_ts_name||' already exists (skipping create)');
    END;
  END IF;

  -- Set as default tablespace
  EXECUTE IMMEDIATE 'ALTER DATABASE DEFAULT TABLESPACE '||l_ts_name;
  dbms_output.put_line('- Default tablespace set to '||l_ts_name);
END;
/
-- EOF -------------------------------------------------------------------------
