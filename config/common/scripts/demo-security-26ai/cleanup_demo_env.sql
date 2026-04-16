-- -----------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
-- -----------------------------------------------------------------------------
--  Name......: cleanup_demo_env.sql
--  Author....: Stefan Oehrli (oes), stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2026.03.10
--  Revision..: v1.0.0
--  Purpose...: Drop demo users and clean up schema objects created for demos.
--  Notes.....:
--  License...: Apache License Version 2.0, January 2004
--              http://www.apache.org/licenses/
-- -----------------------------------------------------------------------------

ALTER SESSION SET CONTAINER = LABPDB1;
BEGIN EXECUTE IMMEDIATE 'DROP USER demo_ro CASCADE'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP USER hr_app CASCADE'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP USER soug_test CASCADE'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
EXIT