--------------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
--------------------------------------------------------------------------------
--  Name......: post_clone_task_df.sql
--  Author....: Stefan Oehrli (oes), stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2025.11.18
--  Revision..: v1.0.0
--  Purpose...: Resize datafiles down to the high-water mark after a clone
--              operation. Disables block change tracking in the CDB root if
--              enabled, then iterates through autoextensible datafiles and
--              resizes them to minimize space usage.
--  Notes.....:
--    - Must be executed in the target PDB as SYSDBA (not in CDB$ROOT).
--    - Automatically logs all actions to a spool file:
--        post_clone_task_df_<db_name>_<pdb_name>_<log_date>.log
--      where:
--        <db_name>   = database unique name
--        <pdb_name>  = pluggable database name
--        <log_date>  = current timestamp (YYYYMMDD_HH24MISS)
--    - Script will also print actions and results to the console.
--  Reference.: DBA_DATA_FILES, V$BLOCK_CHANGE_TRACKING
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

-- Main ------------------------------------------------------------------------
COL filename FOR A60
COL size FOR A20
COL tablespace_name FOR A30
SELECT tablespace_name, dbms_xplan.format_size(sum(bytes)) "SIZE" FROM dba_data_files GROUP BY tablespace_name ORDER BY tablespace_name;
SELECT dbms_xplan.format_size(sum(bytes)) "SIZE" FROM dba_data_files;

DECLARE

    -- Types
    SUBTYPE text_type IS VARCHAR2(2000 CHAR);       -- NOSONAR G-2120 keep function independent
    l_sql text_type; 
    l_con_id    NUMBER;
    l_resize    NUMBER;
    e_bct               EXCEPTION;

    PRAGMA EXCEPTION_INIT(e_bct, -19759);

BEGIN

    -- Check if the current container is the root container
    SELECT SYS_CONTEXT('USERENV', 'CON_ID') INTO l_con_id FROM DUAL;

    IF l_con_id = 1 THEN
        -- Disable block change tracking
        BEGIN
            dbms_output.put('INFO : Disable block change tracking ...................... ');
            l_sql := 'ALTER DATABASE DISABLE block change tracking';
            --- execute ALTER USER statement
            EXECUTE IMMEDIATE l_sql;
            dbms_output.put_line('done');
        EXCEPTION
            WHEN e_bct THEN
            dbms_output.put_line('already disabled');
        END;
    ELSE
        dbms_output.put_line('INFO : Not running in root container, block not executed.');
    END IF;

    -- resize datafiles based on there contents
    dbms_output.put_line('INFO : resize datafiles based there contents');
    FOR r_data_files IN (WITH
            hwm AS (
                SELECT /*+ materialize */ ktfbuesegtsn ts#,ktfbuefno relative_fno,max(ktfbuebno+ktfbueblks-1) hwm_blocks
                FROM sys.x$ktfbue GROUP BY ktfbuefno,ktfbuesegtsn
            ),
            hwmts AS (
                SELECT name tablespace_name,relative_fno,hwm_blocks
                FROM hwm JOIN v$tablespace USING(ts#)
            ),
            hwmdf AS (
                SELECT file_id,file_name,nvl(hwm_blocks*(bytes/blocks),5*1024*1024) hwm_bytes,bytes,autoextensible,maxbytes
                FROM hwmts RIGHT JOIN dba_data_files USING(tablespace_name,relative_fno) WHERE autoextensible='YES' AND maxbytes>=bytes
            )
            SELECT
                file_id, file_name, ceil(hwm_bytes/1024/1024) AS resize
            FROM hwmdf WHERE bytes-hwm_bytes>1024*1024
            ORDER BY bytes-hwm_bytes DESC ) LOOP
        IF r_data_files.resize < 20 THEN
            l_resize:= 20;
        ELSE
            l_resize:= r_data_files.resize;
        END IF;

        l_sql := 'ALTER DATABASE DATAFILE '|| r_data_files.file_id ||' resize '||l_resize||'M';
        dbms_output.put_line('INFO : Resize datafile '||r_data_files.file_id||' to '||r_data_files.resize);
        --- execute ALTER DATABASE statement
        EXECUTE IMMEDIATE l_sql;
    END LOOP;
END;
/

-- Show Information about block change bracking
SELECT * FROM v$block_change_tracking;

COL filename FOR A60
COL size FOR A20
COL tablespace_name FOR A30
SELECT tablespace_name, dbms_xplan.format_size(sum(bytes)) "SIZE" FROM dba_data_files GROUP BY tablespace_name ORDER BY tablespace_name;
SELECT dbms_xplan.format_size(sum(bytes)) "SIZE" FROM dba_data_files;
-- EOF -------------------------------------------------------------------------
