-- -----------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
-- -----------------------------------------------------------------------------
--  Name......: encrypt_ts_users.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2025.11.19
--  Revision..: v1.0.0
--  Purpose...: Online encrypt a given tablespace (default: USERS) using AES256.
--  Notes.....: - Must be executed in a PDB (not CDB$ROOT). Pair with require_pdb.sql.
--              - SQL*Plus formatting and logging should be handled by the caller.
--              - Example:
--                   @encrypt_ts_users.sql USERS
--  License...: Apache License Version 2.0, January 2004 as shown
--              at http://www.apache.org/licenses/
-- -----------------------------------------------------------------------------

-- Fail fast in automation ------------------------------------------------------
WHENEVER SQLERROR EXIT SQL.SQLCODE

-- SQL*Plus formatting (minimal; caller typically sets this) --------------------
SET LINESIZE 256 PAGESIZE 1000
SET SERVEROUTPUT ON
SET FEEDBACK OFF

-- Parameters (defaults)
--   &1 => tablespace name (default: USERS)
COLUMN 1 NEW_VALUE 1 NOPRINT
SELECT '' "1" FROM dual WHERE ROWNUM = 0;

DEFINE _TS_NAME = &1 USERS

SET FEEDBACK ON

-- Main ------------------------------------------------------------------------
DECLARE
  l_ts_name   VARCHAR2(30) := UPPER('&&_TS_NAME');
  l_encrypted VARCHAR2(3);
BEGIN
  -- Must not run in CDB$ROOT
  IF sys_context('userenv','con_name') = 'CDB$ROOT' THEN
    RAISE_APPLICATION_ERROR(
      -20001,
      'encrypt_ts_users.sql must run in a PDB (not CDB$ROOT)'
    );
  END IF;

  -- Check that the tablespace exists and get its encryption status
  BEGIN
    SELECT encrypted
      INTO l_encrypted
      FROM dba_tablespaces
     WHERE tablespace_name = l_ts_name;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(
        -20002,
        'Tablespace '||l_ts_name||' does not exist'
      );
  END;

  -- Skip if already encrypted
  IF l_encrypted = 'YES' THEN
    dbms_output.put_line(
      '- Tablespace '||l_ts_name||' is already encrypted (skipping)'
    );
    RETURN;
  END IF;

  -- Online encrypt the tablespace using AES256
  dbms_output.put_line(
    '- Encrypting tablespace '||l_ts_name||' using AES256 (online)...'
  );

  EXECUTE IMMEDIATE
    'ALTER TABLESPACE '||l_ts_name||
    ' ENCRYPTION ONLINE USING ''AES256'' ENCRYPT';

  dbms_output.put_line(
    '- Tablespace '||l_ts_name||' successfully encrypted using AES256'
  );
END;
/
-- EOF -------------------------------------------------------------------------
