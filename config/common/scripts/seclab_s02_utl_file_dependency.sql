--------------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
--------------------------------------------------------------------------------
--  Name......: seclab_s02_utl_file_dependency.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2026.10.15
--  Revision..: v1.0.0
--  Purpose...: seclab S02 - application procedure that works only through the
--              EXECUTE privilege of PUBLIC on SYS.UTL_FILE.
--  Notes.....: *** INTENTIONALLY INSECURE - lab use only ***
--              - Execute in the seclab PDB as SYSDBA (pair with require_pdb.sql).
--              - Requires seclab_accounts.sql (APP_OWNER, APP_OWNER.CUSTOMERS).
--              - APP_OWNER gets no direct grant on UTL_FILE. Definer rights
--                code ignores roles, so revoking EXECUTE from PUBLIC
--                invalidates APP_OWNER.APP_EXPORT - the pre-check
--                precheck_revoke_public.sql finds this dependency.
--              - The export writes to /opt/oracle/scripts/logs, which is the
--                writable log bind mount of the service.
--  License...: Apache License Version 2.0, January 2004 as shown
--              at http://www.apache.org/licenses/
--------------------------------------------------------------------------------

-- Fail fast in automation -----------------------------------------------------
WHENEVER SQLERROR EXIT SQL.SQLCODE

PROMPT - S02 ensure PUBLIC holds EXECUTE on SYS.UTL_FILE
DECLARE
  l_count PLS_INTEGER;
BEGIN
  SELECT COUNT(*) INTO l_count
    FROM dba_tab_privs
   WHERE grantee = 'PUBLIC' AND owner = 'SYS' AND table_name = 'UTL_FILE'
     AND privilege = 'EXECUTE';
  IF l_count > 0 THEN
    dbms_output.put_line('- PUBLIC already holds EXECUTE on SYS.UTL_FILE (default of this release)');
  ELSE
    EXECUTE IMMEDIATE 'GRANT EXECUTE ON sys.utl_file TO PUBLIC';
    dbms_output.put_line('- PUBLIC did not hold EXECUTE on SYS.UTL_FILE - granted it');
  END IF;
END;
/

PROMPT - S02 create directory APP_EXPORT_DIR and procedure APP_OWNER.APP_EXPORT
CREATE OR REPLACE DIRECTORY app_export_dir AS '/opt/oracle/scripts/logs';
GRANT READ, WRITE ON DIRECTORY app_export_dir TO app_owner;

CREATE OR REPLACE PROCEDURE app_owner.app_export AS
  l_file utl_file.file_type;
BEGIN
  l_file := utl_file.fopen('APP_EXPORT_DIR', 'seclab_app_export.csv', 'w');
  utl_file.put_line(l_file, 'customer_id;full_name;email');
  FOR r IN (SELECT customer_id, full_name, email FROM app_owner.customers ORDER BY customer_id) LOOP
    utl_file.put_line(l_file, r.customer_id || ';' || r.full_name || ';' || r.email);
  END LOOP;
  utl_file.fclose(l_file);
END app_export;
/

PROMPT - S02 run APP_OWNER.APP_EXPORT once to prove it works
EXECUTE app_owner.app_export

PROMPT - Status of APP_OWNER.APP_EXPORT and its UTL_FILE dependency
COL owner           FOR A12
COL name            FOR A12
COL referenced_name FOR A12
COL status          FOR A8
SELECT d.owner, d.name, d.referenced_owner, d.referenced_name, o.status
  FROM dba_dependencies d
  JOIN dba_objects o ON o.owner = d.owner AND o.object_name = d.name AND o.object_type = d.type
 WHERE d.owner = 'APP_OWNER' AND d.referenced_name = 'UTL_FILE';
-- EOF -------------------------------------------------------------------------
