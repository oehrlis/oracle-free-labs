--------------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
--------------------------------------------------------------------------------
--  Name......: sdsec_sysprivs.sql
--  Author....: Stefan Oehrli (oes), stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2023.11.29
--  Revision..: v1.0.0
--  Purpose...: Identify and recreate granted system privileges.
--              The script collects all non-Oracle-maintained system privilege
--              grants, excluding predefined accounts/roles, and generates
--              matching GRANT statements for review or re-execution.
--  Notes.....:
--    - Must be executed in a PDB as SYSDBA (not in CDB$ROOT).
--    - Excludes Oracle-maintained users/roles and those listed in the
--      `excluded_users` collection.
--    - Outputs generated GRANT statements to console and to a spool file:
--        sdsec_sysprivs_<db_name>_<pdb_name>_<log_date>.log
--      where:
--        <db_name>   = database unique name
--        <pdb_name>  = pluggable database name
--        <log_date>  = current timestamp (YYYYMMDD_HH24MISS).
--  Reference.: DBA_SYS_PRIVS, DBA_USERS, DBA_ROLES
--  License...: Apache License Version 2.0, January 2004
--              http://www.apache.org/licenses/
--------------------------------------------------------------------------------


-- fail fast in automation -----------------------------------------------------
WHENEVER SQLERROR EXIT SQL.SQLCODE

-- SQL*Plus formatting ---------------------------------------------------------
SET LINESIZE 256 PAGESIZE 1000
SET SERVEROUTPUT ON
SET FEEDBACK ON
SET ECHO ON
SET TERMOUT ON
SET VERIFY OFF

-- Get PDB name and log date
COLUMN db_name NEW_VALUE db_name NOPRINT
COLUMN pdb_name NEW_VALUE pdb_name NOPRINT
COLUMN log_date NEW_VALUE log_date NOPRINT

-- derive names for spool/log --------------------------------------------------
select sys_context('userenv','db_unique_name') AS db_name from dual;
SELECT REPLACE(sys_context('userenv', 'con_name'), '$', '') AS pdb_name FROM dual;
SELECT TO_CHAR(SYSDATE, 'YYYYMMDD_HH24MISS') AS log_date FROM dual;

-- Start logging ---------------------------------------------------------------
SPOOL sdsec_sysprivs_&db_name._&pdb_name._&log_date..log

-- Validate we are not in CDB$ROOT ---------------------------------------------
PROMPT === Validate we are NOT in CDB$ROOT ===
DECLARE
  v_con VARCHAR2(30) := sys_context('userenv','con_name');
BEGIN
  IF v_con = 'CDB$ROOT' THEN
    RAISE_APPLICATION_ERROR(-20001, 'Run sdsec_sysprivs.sql in target PDB, not CDB$ROOT.');
  END IF;
END;
/
PROMPT OK - running in PDB &pdb_name.

-- Main ------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- create a temporary type
CREATE OR REPLACE TYPE table_varchar AS
    TABLE OF VARCHAR2(128)
/

--------------------------------------------------------------------------------
-- Anonymous PL/SQL Block to get system privileges
DECLARE
    -- list of known user to be excluded
    excluded_users      table_varchar := table_varchar('ZZ_SPOTLIGHT');
    TYPE t_dba_sys_privs IS
       TABLE OF dba_sys_privs%rowtype;
    r_dba_sys_privs     t_dba_sys_privs;
    v_admin_option      VARCHAR2(128) := '';
    v_common            VARCHAR2(128) := '';
    v_container         INT;

BEGIN
    -- check if we are in a multitenant DATABASE
    SELECT sys_context('userenv','con_id') INTO v_container FROM dual;
 
    -- store the information from dba_sys_privs
    SELECT
        *
    BULK COLLECT
    INTO r_dba_sys_privs
    FROM
        dba_sys_privs
    WHERE
        grantee NOT IN (
            SELECT
                username
            FROM
                dba_users
            WHERE
                oracle_maintained='Y'
                OR username IN ( SELECT * FROM TABLE ( excluded_users ) ) UNION
                SELECT
                    role
                FROM
                    dba_roles
                WHERE
                    oracle_maintained='Y'
        );
    
    -- check if we do have an empty collection
    IF r_dba_sys_privs IS NOT EMPTY THEN
        dbms_output.put_line('REM system privilege grants found');
        -- loop through the collection to create the grant statements
        FOR i IN 1..r_dba_sys_privs.last LOOP
            -- set the admin option depending on the current setting
            IF r_dba_sys_privs(i).admin_option = 'YES' THEN
                v_admin_option := ' WITH ADMIN OPTION';
            ELSE
                v_admin_option := '';
            END IF;

            -- set the container option depending on the current setting
            IF v_container = 1 AND r_dba_sys_privs(i).common = 'YES' THEN
                v_common := ' CONTAINER=ALL';
            ELSE
                v_common := '';
            END IF;

            dbms_output.put_line('GRANT '
                                    || r_dba_sys_privs(i).privilege
                                    || ' TO '
                                    || sys.dbms_assert.enquote_name(r_dba_sys_privs(i).grantee)
                                    || v_admin_option
                                    || v_common 
                                    || ';');
        END LOOP;
    ELSE
        dbms_output.put_line('REM no system privilege grants found');
    END IF;
END;
/

--------------------------------------------------------------------------------
-- drop temporary created type
DROP TYPE table_varchar
/

SPOOL off
SET FEEDBACK ON
SET VERIFY ON
-- EOF -------------------------------------------------------------------------
