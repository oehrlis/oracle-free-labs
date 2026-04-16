-- -----------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
-- -----------------------------------------------------------------------------
--  Name......: prepare_demo_env.sql
--  Author....: Stefan Oehrli (oes), stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2026.03.10
--  Revision..: v1.0.0
--  Purpose...: Create and configure users and security components for the demo.
--  Notes.....:
--  License...: Apache License Version 2.0, January 2004
--              http://www.apache.org/licenses/
-- -----------------------------------------------------------------------------

SET SERVEROUTPUT ON
SET FEEDBACK ON
SET ECHO OFF
SET VERIFY OFF
ALTER SESSION SET CONTAINER = LABPDB1;
PROMPT =========================================================================
PROMPT Prepare demo environment
PROMPT =========================================================================

DECLARE
  PROCEDURE exec_sql(p_sql IN VARCHAR2) IS
  BEGIN
    EXECUTE IMMEDIATE p_sql;
    DBMS_OUTPUT.PUT_LINE('OK   : ' || p_sql);
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('INFO : ' || p_sql || ' -> ' || SQLERRM);
  END;
BEGIN
  DBMS_OUTPUT.PUT_LINE('--- Prepare SCOTT --------------------------------------------');
  exec_sql(q'[ALTER USER scott IDENTIFIED BY "tiger" ACCOUNT UNLOCK]');
  exec_sql('GRANT CREATE SESSION TO scott');

  DBMS_OUTPUT.PUT_LINE('--- Prepare READ ONLY demo user ------------------------------');
  exec_sql('CREATE USER demo_ro IDENTIFIED BY demo');
  exec_sql('ALTER USER demo_ro READ ONLY');
  exec_sql('GRANT CREATE SESSION TO demo_ro');
  exec_sql('GRANT SELECT ON scott.emp TO demo_ro');
  exec_sql('GRANT SELECT ON scott.dept TO demo_ro');

  DBMS_OUTPUT.PUT_LINE('--- Prepare schema-only account ------------------------------');
  exec_sql('CREATE USER hr_app NO AUTHENTICATION');
  exec_sql('GRANT CREATE SESSION TO hr_app');

  DBMS_OUTPUT.PUT_LINE('--- Prepare SEPS demo user -----------------------------------');
  exec_sql('CREATE USER soug_test IDENTIFIED BY manager');
  exec_sql('GRANT CREATE SESSION TO soug_test');

  DBMS_OUTPUT.PUT_LINE('--- Optional helper user for schema privilege demos ----------');
  exec_sql('CREATE USER oehrli IDENTIFIED BY manager');
  exec_sql('GRANT CREATE SESSION TO oehrli');

  DBMS_OUTPUT.PUT_LINE('--- Optional READ ANY TABLE ON SCHEMA demo -------------------');
  BEGIN
    EXECUTE IMMEDIATE 'GRANT READ ANY TABLE ON SCHEMA scott TO oehrli';
    DBMS_OUTPUT.PUT_LINE('OK   : GRANT READ ANY TABLE ON SCHEMA scott TO oehrli');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('INFO : GRANT READ ANY TABLE ON SCHEMA scott TO oehrli -> ' || SQLERRM);
  END;

  DBMS_OUTPUT.PUT_LINE('--- Enable SQL Firewall if not already enabled ---------------');
  BEGIN
    DBMS_SQL_FIREWALL.ENABLE;
    DBMS_OUTPUT.PUT_LINE('OK   : DBMS_SQL_FIREWALL.ENABLE');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('INFO : DBMS_SQL_FIREWALL.ENABLE -> ' || SQLERRM);
  END;
END;
/
EXIT