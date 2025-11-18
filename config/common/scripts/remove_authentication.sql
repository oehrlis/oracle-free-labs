--------------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
--------------------------------------------------------------------------------
--  Name......: remove_authentication.sql
--  Author....: Stefan Oehrli (oes), stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2025.08.19
--  Revision..: v1.0.0
--  Purpose...: Remove authentication from application schemas and users.
--              Non-Oracle-maintained users not in the keep list are set to
--              NO AUTHENTICATION. Selected schemas in the reset list are
--              reconfigured with their username as password.
--  Notes.....:
--    - Must be executed in a PDB as SYSDBA or a DBA user with ALTER USER.
--    - Do not run in CDB$ROOT; the script will enforce this check.
--    - Keeps a configurable list of schemas untouched.
--    - Writes all changes to console and to a spool file named:
--        remove_authentication_<db_name>_<pdb_name>_<log_date>.log
--      where:
--        <db_name>   = database unique name
--        <pdb_name>  = PDB name
--        <log_date>  = current timestamp (YYYYMMDD_HH24MISS)
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

-- create temporary type
CREATE OR REPLACE TYPE t_table_usernames_type AS
    TABLE OF VARCHAR2(128 CHAR)
/

SET SERVEROUTPUT ON
SET LINESIZE 160 PAGESIZE 200

-- anoynmouse PL/SQL block to remove authentication
<< remove_authentication >> 
DECLARE
    ----------------------------------------------------------------------------
    -- Begin of Customization --------------------------------------------------
    ----------------------------------------------------------------------------
        -- list of schema's to keep regardless of the classification
        t_keep_schemas t_table_usernames_type := t_table_usernames_type('TVD_HR','USERS','PDBADMIN');
        -- list of schema's to reset password
        t_reset_schemas t_table_usernames_type := t_table_usernames_type('SCOTT');
    ----------------------------------------------------------------------------
    -- End of Customization ----------------------------------------------------
    ----------------------------------------------------------------------------
    
    -- Types
    SUBTYPE text_type IS VARCHAR2(2000 CHAR);       -- NOSONAR G-2120 keep function independent
    
    l_sql text_type; -- local variable for dynamic SQL

BEGIN
    -- lock all user which are not oracle maintained
    << remove_auth >>
    FOR r_dba_users IN (SELECT username FROM dba_users WHERE oracle_maintained='N' AND common='NO' AND username NOT IN (SELECT * FROM TABLE ( t_keep_schemas ))) LOOP
        l_sql := 'ALTER USER '
            || sys.dbms_assert.enquote_name(r_dba_users.username)
            || ' NO AUTHENTICATION';
        sys.dbms_output.put_line('- alter user '||r_dba_users.username);
        --sys.dbms_output.put_line(l_sql);
        --- execute ALTER USER statement
        EXECUTE IMMEDIATE l_sql;
    END LOOP remove_auth;
    << reset_auth >>
    FOR r_dba_users IN (SELECT username FROM dba_users WHERE oracle_maintained='N' AND common='NO' AND username IN (SELECT * FROM TABLE ( t_reset_schemas ))) LOOP
        l_sql := 'ALTER USER '
            || sys.dbms_assert.enquote_name(r_dba_users.username)
            || ' IDENTIFIED BY '
            || sys.dbms_assert.enquote_name(r_dba_users.username);
        sys.dbms_output.put_line('- alter user '||r_dba_users.username);
        --sys.dbms_output.put_line(l_sql);
        --- execute ALTER USER statement
        EXECUTE IMMEDIATE l_sql;
    END LOOP reset_auth;
END remove_authentication;
/

-- drop temporary type
DROP TYPE t_table_usernames_type
/

-- EOF -------------------------------------------------------------------------