--------------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
--------------------------------------------------------------------------------
--  Name......: export_full_data.sql
--  Author....: Stefan Oehrli (oes), stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2025.11.18
--  Revision..: v1.0.0
--  Purpose...: Perform a full PDB export using DBMS_DATAPUMP. Creates a dump
--              file set and log file in the COMMON_DATA directory and starts
--              a Data Pump job in FULL mode.
--  Notes.....:
--    - Must be executed in a PDB as SYSDBA (not in CDB$ROOT).
--    - Generates dump files and logs in the Oracle directory COMMON_DATA.
--    - The dump file name format is:
--        pdb_default_data_<pdb_name>.%U.dmp
--    - The log file name is:
--        pdb_default_data_<pdb_name>.log
--    - Actions and job state are logged to spool file:
--        export_full_data_<db_name>_<pdb_name>_<log_date>.log
--      where:
--        <db_name>   = database unique name
--        <pdb_name>  = pluggable database name
--        <log_date>  = timestamp (YYYYMMDD_HH24MISS)
--  Reference.: DBMS_DATAPUMP, DBA_DATAPUMP_JOBS
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
DECLARE
  l_dp_handle       PLS_INTEGER;
BEGIN
  -- Open a full export job.
  l_dp_handle := sys.dbms_datapump.open(
    operation   => 'EXPORT',
    job_mode    => 'FULL',
    remote_link => NULL,
    job_name    => 'PDB_FULL_EXPORT',
    version     => 'LATEST');

  -- Specify the dump file name and directory object name.
  sys.dbms_datapump.add_file(
    handle    => l_dp_handle,
    filename  => 'pdb_default_data_&pdb_name.%U.dmp',
    directory => 'COMMON_DATA',
    filesize  => '10G',
    reusefile => 1 );

  -- Specify the log file name and directory object name.
  sys.dbms_datapump.add_file(
    handle    => l_dp_handle,
    filename  => 'pdb_default_data_&pdb_name.log',
    directory => 'COMMON_DATA',
    filetype  => SYS.DBMS_DATAPUMP.KU$_FILE_TYPE_LOG_FILE);

  sys.dbms_datapump.start_job(l_dp_handle);

  sys.dbms_datapump.detach(l_dp_handle);
END;
/

COLUMN owner_name   FORMAT A20
COLUMN job_name     FORMAT A30
COLUMN operation    FORMAT A10
COLUMN job_mode     FORMAT A10
COLUMN state    FORMAT A12

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