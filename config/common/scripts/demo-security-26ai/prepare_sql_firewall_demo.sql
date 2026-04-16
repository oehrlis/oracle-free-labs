-- -----------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
-- -----------------------------------------------------------------------------
--  Name......: prepare_sql_firewall_demo.sql
--  Author....: Stefan Oehrli (oes), stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2026.03.10
--  Revision..: v1.0.0
--  Purpose...: Create and start SQL Firewall capture for the demo user SCOTT.
--  Notes.....:
--  License...: Apache License Version 2.0, January 2004
--              http://www.apache.org/licenses/
-- -----------------------------------------------------------------------------

SET SERVEROUTPUT ON
SET FEEDBACK ON

PROMPT =========================================================================
PROMPT Prepare SQL Firewall demo
PROMPT =========================================================================

BEGIN
  DBMS_SQL_FIREWALL.ENABLE;
  DBMS_OUTPUT.PUT_LINE('OK   : SQL Firewall enabled');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('INFO : SQL Firewall enable -> ' || SQLERRM);
END;
/

BEGIN
  DBMS_SQL_FIREWALL.CREATE_CAPTURE(
      username       => 'SCOTT',
      top_level_only => TRUE,
      start_capture  => TRUE);
  DBMS_OUTPUT.PUT_LINE('OK   : Capture started for SCOTT');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('INFO : Create capture for SCOTT -> ' || SQLERRM);
END;
/
EXIT