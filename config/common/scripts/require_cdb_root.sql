-- -----------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
-- -----------------------------------------------------------------------------
--  Name......: require_cdb_root.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2025.11.18
--  Revision..: v1.0.0
--  Purpose...: Generic snippet to validate execution in CDB$ROOT.
--  Notes.....: To be called at the beginning of scripts that must run
--              in the container database root.
--  Reference.: --
--  License...: Apache License Version 2.0, January 2004 as shown
--              at http://www.apache.org/licenses/
-- -----------------------------------------------------------------------------
-- SQL*Plus formatting ---------------------------------------------------------
SET LINESIZE 256 PAGESIZE 1000
SET SERVEROUTPUT ON

-- Validate we are in CDB$ROOT
PROMPT - Validate we are in CDB$ROOT
DECLARE
  v_con VARCHAR2(30) := sys_context('userenv','con_name');
BEGIN
  IF v_con <> 'CDB$ROOT' THEN
    RAISE_APPLICATION_ERROR(-20000,
      'This script must run in CDB$ROOT as SYSDBA. Current: '||v_con);
  END IF;
END;
/

PROMPT - OK, running in CDB$ROOT
-- EOF -- ----------------------------------------------------------------------