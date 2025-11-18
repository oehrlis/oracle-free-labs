--------------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
--------------------------------------------------------------------------------
--  Name......: post_clone_task_audit.sql
--  Author....: Stefan Oehrli (oes), stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2025.11.18
--  Revision..: v1.0.0
--  Purpose...: Perform post-clone audit configuration tasks, including:
--                - Purge standard audit trail
--                - Purge unified audit trail
--                - Initialize audit tablespace
--                - Create jobs for audit management and cleanup
--  Notes.....:
--    - Must be executed in the target PDB as SYSDBA (not in CDB$ROOT).
--    - The list of application users can be customized in `t_users`.
--    - All actions are logged to a spool file:
--        post_clone_task_audit_<db_name>_<pdb_name>_<log_date>.log
--      where:
--        <db_name>   = database unique name
--        <pdb_name>  = pluggable database name
--        <log_date>  = current timestamp (YYYYMMDD_HH24MISS)
--    - Results are also printed to the console for immediate feedback.
--  Reference.: DBMS_AUDIT_MGMT, DBA_AUDIT_MGMT_CLEANUP_JOBS,
--              DBA_AUDIT_MGMT_CONFIG_PARAMS
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
-- Anonymous PL/SQL Block to configure audit environment
SET SERVEROUTPUT ON
SET LINESIZE 160 PAGESIZE 200
COL "DB ID" FOR A30
COL audit_trail FOR A20
COL comments FOR A80
COL entity_name FOR A30
COL entity_name FOR A30
COL filename FOR A60
COL job_frequency FOR A40
COL job_name FOR A30
COL parameter_name FOR A30
COL parameter_value FOR A20
COL policy_name FOR A40
COL repeat_interval FOR A80
COL user_name FOR A20

COL owner FOR A20
COL segment_name FOR A30
COL tablespace_name FOR A30

DECLARE
    v_sql               VARCHAR2(4000);
    v_version           number;
    v_audit_size        number;
    l_datafile_id       dba_data_files.file_id%TYPE;
    l_datafile_path     dba_data_files.file_name%TYPE;
    l_db_unique_name    v$database.db_unique_name%TYPE;
    v_audit_tablespace  varchar2(30) := 'AUDIT_DATA';
    v_audit_data_file   varchar2(513);
    e_tablespace_exists EXCEPTION;
    e_tablespace_size   EXCEPTION;
    e_job_exists        EXCEPTION;
    e_audit_job_exists  EXCEPTION;
    e_bct               EXCEPTION;

    PRAGMA EXCEPTION_INIT(e_tablespace_exists,-1543);
    PRAGMA EXCEPTION_INIT(e_tablespace_size,-03297);
    PRAGMA EXCEPTION_INIT(e_job_exists, -27477 );
    PRAGMA EXCEPTION_INIT(e_audit_job_exists, -46254);
    PRAGMA EXCEPTION_INIT(e_bct, -19759);
    

BEGIN
    -- get information for audit tablespace
    dbms_output.put_line('INFO : Configure and initialize Audit');
    SELECT file_name INTO l_datafile_path FROM dba_data_files WHERE file_name like '%system%' AND rownum <2;
    SELECT db_unique_name INTO l_db_unique_name FROM v$database;
    SELECT regexp_substr(version,'^\d+') INTO v_version FROM v$instance;
    SELECT round(max(bytes/1024/1024)*1.2) INTO v_audit_size FROM dba_segments WHERE segment_name IN ('AUD$','AUD$UNIFIED');

    -- define a limit fo 20M for v_audit_size
    IF v_audit_size < 20 THEN
        v_audit_size := 25;
    END IF;

    -- Datafile String for Audit Tablespace
    v_audit_data_file := l_datafile_path||lower(v_audit_tablespace)||'01'||l_db_unique_name||'.dbf'; 

    -- Create Tablespace but rise an exeption if it allready exists
    dbms_output.put('INFO : Create '||v_audit_tablespace||' Tablespace ....................... ');
    BEGIN
        v_sql := 'CREATE TABLESPACE '||v_audit_tablespace||' datafile '''||v_audit_data_file||''' size '||v_audit_size||'M autoextend on next 10240K maxsize unlimited';
        --- execute CREATE TABLESPACE statement
        EXECUTE IMMEDIATE v_sql;
        dbms_output.put_line('created');
    EXCEPTION
        WHEN e_tablespace_exists THEN
        dbms_output.put_line('already exists');
    END;

    -- resize tablespace to the segment size of the audit trail.
    dbms_output.put('INFO : Alter '||v_audit_tablespace||' Tablespace ........................ ');
    BEGIN
        SELECT file_id INTO l_datafile_id FROM dba_data_files WHERE tablespace_name=v_audit_tablespace;
        v_sql := 'ALTER DATABASE DATAFILE '||l_datafile_id||' resize '||v_audit_size||'M';
        --- execute ALTER DATABASE statement
        EXECUTE IMMEDIATE v_sql;
        dbms_output.put_line('resize to '||v_audit_size);
        v_sql := 'ALTER DATABASE DATAFILE '||l_datafile_id||' autoextend on next 10240K maxsize unlimited';
        --- execute ALTER DATABASE statement
        EXECUTE IMMEDIATE v_sql;
    EXCEPTION
        WHEN e_tablespace_size THEN
        dbms_output.put_line('unable to resize to '||v_audit_size);
    END;

    -- set location for Standard and FGA Audit Trail
    dbms_output.put_line('INFO : Set location to '||v_audit_tablespace||' for Standard and FGA Audit Trail');
    dbms_audit_mgmt.set_audit_trail_location(
        audit_trail_type           => dbms_audit_mgmt.audit_trail_db_std,
        audit_trail_location_value => v_audit_tablespace
    );

    -- set location for Unified Audit
    dbms_output.put_line('INFO : Set location to '||v_audit_tablespace||' for Unified Audit');
    dbms_audit_mgmt.set_audit_trail_location(
      audit_trail_type           => dbms_audit_mgmt.audit_trail_unified,
      audit_trail_location_value => v_audit_tablespace
    );

    -- Initialize Standard Audit Trail
    dbms_output.put('INFO : initialize standard Audit Trail .................... ');
    IF 
       NOT dbms_audit_mgmt.is_cleanup_initialized(dbms_audit_mgmt.audit_trail_aud_std)
    THEN
        dbms_audit_mgmt.init_cleanup(
            audit_trail_type          => dbms_audit_mgmt.audit_trail_aud_std,
            default_cleanup_interval  => 240 /* hours */);
        dbms_output.put_line('initialized'); 
    ELSE
        dbms_output.put_line('skipped');
    END IF;

    -- Purge Standard Audit Trail
    dbms_output.put_line('INFO : purge standard database audit trails');         
    dbms_audit_mgmt.clean_audit_trail(
        audit_trail_type => dbms_audit_mgmt.audit_trail_aud_std,
        use_last_arch_timestamp => FALSE);

    -- Purge Unified Audit
    dbms_output.put_line('INFO : purge unified audit trails');         
    dbms_audit_mgmt.clean_audit_trail(
        audit_trail_type => dbms_audit_mgmt.audit_trail_unified,
        use_last_arch_timestamp => FALSE);

    -- create a job for daily archive timestamps for Unified Audit
    dbms_output.put('INFO : Create Unified Audit Trail archive timestamp job ... ');
    BEGIN
        DBMS_SCHEDULER.CREATE_JOB (
        job_name   => 'DAILY_UNIFIED_AUDIT_TIMESTAMP',
        job_type   => 'PLSQL_BLOCK',
        job_action => 'begin dbms_audit_mgmt.set_last_archive_timestamp(audit_trail_type => 
                        dbms_audit_mgmt.audit_trail_unified,last_archive_time => SYSDATE-&audit_retention); END;',
        start_date => sysdate,
        repeat_interval => 'FREQ=HOURLY;INTERVAL=24',
        enabled    =>  TRUE,
        comments   => 'Archive timestamp for unified audit to SYSDATE-&audit_retention'
        );
        dbms_output.put_line('created');
    EXCEPTION
        WHEN e_job_exists THEN
        dbms_output.put_LINE('already exists');
    END;

    -- Create daily purge job Unified Audit Trail
    dbms_output.put('INFO : Create Unified Audit Trail purge jobs .............. ');
    BEGIN
        dbms_audit_mgmt.create_purge_job(
        audit_trail_type           => dbms_audit_mgmt.audit_trail_unified,
        audit_trail_purge_interval => 24 /* hours */,
        audit_trail_purge_name     => 'Daily_Unified_Audit_Purge_Job',
        use_last_arch_timestamp    => TRUE
        );
        dbms_output.put_line('created');
    EXCEPTION
        WHEN e_audit_job_exists THEN
        dbms_output.put_line('already exists');
    END;
END;
/

-- Show Information about block change bracking
SELECT * FROM v$block_change_tracking;

SELECT audit_trail,parameter_name, parameter_value 
FROM dba_audit_mgmt_config_params ORDER BY audit_trail;

-- Show Audit Management jobs
SELECT job_name,job_status,audit_trail,job_frequency FROM dba_audit_mgmt_cleanup_jobs;

-- Show Audit specific scheduler jobs
SELECT JOB_NAME,REPEAT_INTERVAL FROM dba_scheduler_jobs WHERE job_name LIKE '%AUDIT%' ;

-- Show enabled unified audit policies
SELECT * FROM audit_unified_enabled_policies;

-- Show amount of standard audit records
SELECT count(*) "STD Audit Records" FROM aud$;

-- Show amount of unified audit records
SELECT
    CASE
        WHEN (dbid) IN (SELECT dbid FROM v$database) THEN dbid ||' (current)'
        ELSE to_char(dbid)
    END "DB ID",
    count(*) "Unified Audit Records"
FROM unified_audit_trail GROUP BY dbid;

-- Show size of audit segments
SELECT owner, segment_name, sum(bytes/1024/1024) "Size (MB)",tablespace_name
FROM dba_segments WHERE segment_name IN ('AUD$','AUD$UNIFIED')
GROUP BY owner, segment_name, tablespace_name;
-- EOF -------------------------------------------------------------------------
