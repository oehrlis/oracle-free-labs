--------------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
--------------------------------------------------------------------------------
--  Name......: seclab_s05_overprivileged.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2026.10.15
--  Revision..: v1.0.0
--  Purpose...: seclab S05 - over-privileged accounts: application owner with
--              DBA, developer with SELECT ANY TABLE, a grant WITH ADMIN OPTION.
--  Notes.....: *** INTENTIONALLY INSECURE - lab use only ***
--              - Execute in the seclab PDB as SYSDBA (pair with require_pdb.sql).
--              - Requires seclab_accounts.sql.
--              - Remediation class 3 (least-privilege role model). There is
--                deliberately no FIX mode: a mass revoke is not the remedy.
--  License...: Apache License Version 2.0, January 2004 as shown
--              at http://www.apache.org/licenses/
--------------------------------------------------------------------------------

-- Fail fast in automation -----------------------------------------------------
WHENEVER SQLERROR EXIT SQL.SQLCODE

PROMPT - S05 grant DBA to the application owner APP_OWNER
GRANT dba TO app_owner;

PROMPT - S05 grant SELECT ANY TABLE to the developer DEV_USER1
GRANT SELECT ANY TABLE TO dev_user1;

PROMPT - S05 grant SELECT ANY TABLE WITH ADMIN OPTION to ANALYST1
GRANT SELECT ANY TABLE TO analyst1 WITH ADMIN OPTION;

PROMPT - Privileges of the S05 accounts after this step
COL grantee   FOR A12
COL privilege FOR A20
COL admin_option FOR A6
SELECT grantee, granted_role AS privilege, admin_option, 'ROLE' AS kind
  FROM dba_role_privs WHERE grantee IN ('APP_OWNER', 'DEV_USER1', 'ANALYST1') AND granted_role = 'DBA'
UNION ALL
SELECT grantee, privilege, admin_option, 'SYSPRIV'
  FROM dba_sys_privs WHERE grantee IN ('APP_OWNER', 'DEV_USER1', 'ANALYST1') AND privilege LIKE '% ANY %'
 ORDER BY 1, 2;
-- EOF -------------------------------------------------------------------------
