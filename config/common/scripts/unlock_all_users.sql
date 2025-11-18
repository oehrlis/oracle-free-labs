--------------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
--------------------------------------------------------------------------------
--  Name......: unlock_all_users.sql
--  Author....: Stefan Oehrli (oes), stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2025.11.18
--  Revision..: v1.0.0
--  Purpose...: Unlock all non-Oracle-maintained users and lock Oracle-maintained
--              users explicitly.
--  Notes.....: 
--    - Must be executed in a PDB as SYSDBA or a user with ALTER USER privileges.
--    - Non-Oracle-maintained users will be unlocked and their password set to
--      the lowercase username.
--    - Oracle-maintained users will be locked, except for SYS, SYSTEM,
--      DBSNMP, and XS$NULL.
--    - Actions are logged both to the console and to a spool file named:
--        unlock_all_users_<db_name>_<pdb_name>_<log_date>.log
--      where:
--        <db_name>   = database unique name
--        <pdb_name>  = pluggable database name
--        <log_date>  = current timestamp in format YYYYMMDD_HH24MISS.
--  Reference.: --
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

    -- update default profile and set password life time to UNLIMITED
    dbms_output.put_line('INFO : Update default profile and release password life time');
    v_sql := 'ALTER PROFILE DEFAULT LIMIT password_life_time UNLIMITED ';
    --- execute ALTER USER statement
    EXECUTE IMMEDIATE v_sql;
    
    -- unlock all user which are not oracle maintained
    FOR r_dba_users IN (SELECT username FROM dba_users WHERE oracle_maintained='N' AND common='NO') LOOP
        SELECT dbms_random.string('X', 20) INTO v_password FROM dual;
        v_sql := 'ALTER USER '
            || sys.dbms_assert.enquote_name(r_dba_users.username)
            || ' IDENTIFIED BY '
            || lower(sys.dbms_assert.enquote_name(r_dba_users.username))
            || ' ACCOUNT UNLOCK PROFILE default';
        dbms_output.put_line('INFO : unlock and reset user '||r_dba_users.username);
        --- execute ALTER USER statement
        EXECUTE IMMEDIATE v_sql;
    END LOOP;

    -- lock all oracle maintained user except SYS, SYSTEM, DBSNMP and XS$NULL
    FOR r_dba_users IN (SELECT username FROM dba_users WHERE oracle_maintained='Y' AND username NOT IN ('SYS','SYSTEM','DBSNMP','XS$NULL')) LOOP
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