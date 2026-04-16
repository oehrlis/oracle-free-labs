-- -----------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
-- -----------------------------------------------------------------------------
--  Name......: cleanup_sql_firewall.sql
--  Author....: Stefan Oehrli (oes), stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2026.03.10
--  Revision..: v1.0.0
--  Purpose...: Disable SQL Firewall allow-list and stop capture for demo user.
--  Notes.....:
--  License...: Apache License Version 2.0, January 2004
--              http://www.apache.org/licenses/
-- -----------------------------------------------------------------------------

ALTER SESSION SET CONTAINER = LABPDB1;
BEGIN
  DBMS_SQL_FIREWALL.DISABLE_ALLOW_LIST('SCOTT');
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

BEGIN
  DBMS_SQL_FIREWALL.STOP_CAPTURE('SCOTT');
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT