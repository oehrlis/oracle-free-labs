-- -----------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
-- -----------------------------------------------------------------------------
--  Name......: prepare_mfa_demo.sql
--  Author....: Stefan Oehrli (oes), stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2026.03.10
--  Revision..: v1.0.0
--  Purpose...: Show MFA status for demo user and current session context.
--  Notes.....:
--  License...: Apache License Version 2.0, January 2004
--              http://www.apache.org/licenses/
-- -----------------------------------------------------------------------------

SET PAGESIZE 200
SET LINESIZE 200
COL username FOR A20
COL mfa FOR A10

PROMPT =========================================================================
PROMPT MFA demo validation
PROMPT =========================================================================

SELECT username, mfa
FROM dba_users
WHERE username IN ('SCOTT');

SELECT SYS_CONTEXT(
       'USERENV',
       'MULTIFACTOR_AUTHENTICATION_METHODS') AS multifactor_authentication_methods
FROM dual;
EXIT