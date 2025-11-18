--------------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
--------------------------------------------------------------------------------
--  Name......: lock_all_users.sql
--  Author....: Stefan Oehrli (oes), stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2025.11.18
--  Revision..: v1.0.0
--  Purpose...: Lock all non-Oracle maintained users and explicitly lock Oracle
--              maintained users (except SYS, SYSTEM, and XS$NULL). Random
--              passwords are assigned before locking to prevent reuse.
--  Notes.....:
--    - Must be executed in a PDB as SYSDBA (not in CDB$ROOT).
--    - The script:
--        * Locks all non-Oracle maintained accounts.
--        * Locks all Oracle maintained accounts except SYS, SYSTEM, and XS$NULL.
--        * Assigns random passwords before locking.
--    - Logs all actions to spool file:
--        lock_all_users_<db_name>_<pdb_name>_<log_date>.log
--      where:
--        <db_name>   = database unique name
--        <pdb_name>  = pluggable database name
--        <log_date>  = timestamp (YYYYMMDD_HH24MISS)
--  Reference.: DBA_USERS, DBMS_RANDOM
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
COL policy_name FOR A40
COL entity_name FOR A30
COL comments FOR A80

DECLARE
    v_sql       VARCHAR2(4000);
    v_password  VARCHAR2(128);
BEGIN
    -- lock all user which are not oracle maintained
    FOR r_dba_users IN (SELECT username FROM dba_users WHERE oracle_maintained='N') LOOP
        SELECT dbms_random.string('X', 20) INTO v_password FROM dual;
        v_sql := 'ALTER USER '
            || sys.dbms_assert.enquote_name(r_dba_users.username)
            || ' IDENTIFIED BY '
            || sys.dbms_assert.enquote_name(v_password)
            || ' ACCOUNT LOCK';
        dbms_output.put_line('INFO : lock user '||r_dba_users.username);
        --- execute ALTER USER statement
        EXECUTE IMMEDIATE v_sql;
    END LOOP;

    -- lock all oracle maintained user except SYS, SYSTEM and XS$NULL
    FOR r_dba_users IN (SELECT username FROM dba_users WHERE oracle_maintained='Y' AND username NOT IN ('SYS','SYSTEM','XS$NULL')) LOOP
        SELECT dbms_random.string('X', 20) INTO v_password FROM dual;
        v_sql := 'ALTER USER '
            || sys.dbms_assert.enquote_name(r_dba_users.username)
            || ' ACCOUNT LOCK';
        dbms_output.put_line('INFO : lock user '||r_dba_users.username);
        --- execute ALTER USER statement
        EXECUTE IMMEDIATE v_sql;
    END LOOP;
END;
/
-- EOF -------------------------------------------------------------------------
