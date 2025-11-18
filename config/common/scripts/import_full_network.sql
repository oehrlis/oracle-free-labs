-- -----------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
-- -----------------------------------------------------------------------------
--  Name......: import_full_network.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2024.03.12
--  Revision..:  
--  Purpose...: Script to run DBMS_IMPORT.
--  Notes.....: 
--  Reference.: SYS (or grant manually to a DBA)
--  License...: Apache License Version 2.0, January 2004 as shown
--              at http://www.apache.org/licenses/
--------------------------------------------------------------------------------
-- Fail fast in automation -----------------------------------------------------
WHENEVER SQLERROR EXIT SQL.SQLCODE

-- SQL*Plus formatting ---------------------------------------------------------
SET LINESIZE 256 PAGESIZE 1000
SET SERVEROUTPUT ON
SET FEEDBACK OFF
SET VERIFY OFF

-- Main ------------------------------------------------------------------------
SET SERVEROUTPUT on
DECLARE
  l_dp_handle       PLS_INTEGER;
  --l_job_state       VARCHAR2 (100);
BEGIN
  
  -- Open a full export job.
  l_dp_handle := sys.dbms_datapump.open(
      operation   => 'IMPORT',
      job_mode    => 'FULL',
      remote_link => 'source.oradba.ch',
      job_name    => 'ORADBA_IMPORT',
      version     => 'LATEST');
  sys.dbms_output.put_line('Handle=>'||l_dp_handle);

  sys.dbms_datapump.set_parameter(
    handle  => 55,
    name    => 'LOGTIME',
    value   => 'ALL');

  sys.dbms_datapump.metadata_filter(
    handle  => 55,
    name    => 'NAME_EXPR',
    value   => 'NOT IN (''AUD$'',''FGA_LOG$'')');
END;
/
  -- set the import parameters
  sys.dbms_datapump.set_parallel(
    handle  => l_dp_handle,
    degree   => 8);

  sys.dbms_datapump.set_parameter(
    handle  => l_dp_handle,
    name    => 'LOGTIME',
    value   => 'ALL');

  -- Specify the log file name and directory object name.
  sys.dbms_datapump.add_file(
    handle    => l_dp_handle,
    filename  => 'imp_full_'|| sys_context('USERENV', 'DB_NAME')|| '.log',
    directory => 'BCK_DIR_BIT',
    filetype  => sys.dbms_datapump.ku$_file_type_log_file);

  -- Set the EXCLUDE parameters
  sys.dbms_datapump.metadata_filter(
    handle  => l_dp_handle,
    name    => 'SCHEMA_EXPR',
    value   => 'NOT IN (''SYS'',''SYSTEM'',''DBSNMP'',''APPQOSSYS'',''GSMCATUSER'',''XS'',''REMOTE_SCHEDULER_AGENT'',''DBSFWUSER'',''SYSBACKUP'',''GGSYS'',''ANONYMOUS'',''SYSRAC'',''CTXSYS'',''OJVMSYS'',''AUDSYS'',''GSMADMIN_INTERNAL'',''DIP'',''SYSKM'',''OUTLN'',''ORACLE_OCM'',''SYS'',''XDB'',''WMSYS'',''SYSDG'',''GSMUSER'',''C##SEC_ADMIN'',''C##DISCOVERY'',''C##SPARX'',''C##FUB_ADMIN'')');

  sys.dbms_datapump.metadata_filter(
    handle  => l_dp_handle,
    name    => 'NAME_EXPR',
    value   => 'NOT IN (''AUD$'',''FGA_LOG$'')',
    object_path => 'TABLE');

  sys.dbms_datapump.metadata_filter(
    handle  => l_dp_handle,
    name    => 'EXCLUDE_PATH_LIST',
    value   => 'TABLESPACE');

  sys.dbms_datapump.metadata_filter(
    handle  => l_dp_handle,
    name    => 'EXCLUDE_PATH_LIST',
    value   => 'STATISTICS');

  -- Start the Data Pump job
  sys.dbms_datapump.start_job(l_dp_handle);

    -- -- Wait for the job to finish
    -- sys.dbms_datapump.wait_for_job(
    --   handle    => l_dp_handle,
    --   job_state => l_job_state);

  -- Detach from the Data Pump job
  sys.dbms_datapump.detach(handle => l_dp_handle);

  sys.dbms_output.put_line('Data Pump import job ORADBA_IMPORT successfully started with handle ' || l_dp_handle);

EXCEPTION
    WHEN OTHERS THEN
        sys.dbms_output.put_line('Error occurred: ' || sqlerrm);
        IF l_dp_handle IS NOT NULL THEN
            sys.dbms_datapump.detach(handle => l_dp_handle);
        END IF;
        RAISE;
END;
/

COLUMN owner_name   FORMAT A20
COLUMN job_name     FORMAT A30
COLUMN operation    FORMAT A10
COLUMN job_mode     FORMAT A10
COLUMN state        FORMAT A12

SELECT owner_name,
       job_name,
       trim(operation) as operation,
       trim(job_mode) as job_mode,
       state,
       degree,
       attached_sessions,
       datapump_sessions
FROM   dba_datapump_jobs
ORDER BY owner_name, job_name;

-- EOF -------------------------------------------------------------------------