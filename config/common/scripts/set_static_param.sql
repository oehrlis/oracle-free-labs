--------------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
--------------------------------------------------------------------------------
--  Name......: set_static_param.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2026.10.15
--  Revision..: v1.0.0
--  Purpose...: Set a static instance parameter in the SPFILE and restart the
--              instance, but only if the running value differs.
--  Notes.....: - Execute in CDB$ROOT as SYSDBA (pair with require_cdb_root.sql).
--              - Logging and SQL*Plus formatting are the caller's responsibility.
--              - &1 parameter name, &2 value. Supported: boolean and integer
--                parameters (e.g. sql92_security FALSE). String values with
--                quotes and size suffixes (10M) are not supported: the value
--                is compared literally with V$PARAMETER.VALUE.
--              - The restart is done by restart_instance.sql in the same
--                directory (/opt/oracle/common/scripts). It closes all PDBs;
--                PDBs with a saved state reopen.
--  Usage.....: @set_static_param.sql sql92_security TRUE
--  License...: Apache License Version 2.0, January 2004 as shown
--              at http://www.apache.org/licenses/
--------------------------------------------------------------------------------

-- Fail fast in automation -----------------------------------------------------
WHENEVER SQLERROR EXIT SQL.SQLCODE

SET FEEDBACK OFF
SET VERIFY OFF
SET SERVEROUTPUT ON

-- Parameters ------------------------------------------------------------------
COLUMN 1 NEW_VALUE 1 NOPRINT
COLUMN 2 NEW_VALUE 2 NOPRINT
SELECT '' "1" FROM dual WHERE ROWNUM = 0;
SELECT '' "2" FROM dual WHERE ROWNUM = 0;

DEFINE _PARAM_NAME  = '&1'
DEFINE _PARAM_VALUE = '&2'
DEFINE _COMMON_DIR  = '/opt/oracle/common/scripts'

-- Unknown parameter: stop before the restart decision -------------------------
-- Without a V$PARAMETER row the NEW_VALUE below would stay undefined and
-- SQL*Plus would prompt for it, eating the caller's stdin.
DECLARE
  l_count PLS_INTEGER;
BEGIN
  SELECT COUNT(*) INTO l_count FROM v$parameter WHERE name = LOWER('&_PARAM_NAME');
  IF l_count = 0 THEN
    RAISE_APPLICATION_ERROR(-20014, 'set_static_param.sql: unknown parameter &_PARAM_NAME');
  END IF;
END;
/

-- Decide whether a change and a restart are needed ----------------------------
-- SQL*Plus resolves a command name before substitution, so a variable cannot
-- hold SHUTDOWN or STARTUP. The choice is made between two script names.
COLUMN c_restart NEW_VALUE _RESTART_SCRIPT NOPRINT
SELECT CASE WHEN UPPER(p.value) = UPPER(TRIM(BOTH CHR(39) FROM '&_PARAM_VALUE'))
             AND UPPER(NVL(s.value, p.value)) = UPPER(TRIM(BOTH CHR(39) FROM '&_PARAM_VALUE'))
            THEN 'require_cdb_root.sql'
            ELSE 'restart_instance.sql' END AS c_restart
  FROM v$parameter p
  LEFT JOIN v$spparameter s ON s.name = p.name AND s.sid = '*'
 WHERE p.name = LOWER('&_PARAM_NAME');

SET FEEDBACK ON
PROMPT - Static parameter &_PARAM_NAME, requested value &_PARAM_VALUE
COL name  FOR A30
COL value FOR A30
SELECT name, value, isdefault FROM v$parameter WHERE name = LOWER('&_PARAM_NAME');

BEGIN
  IF '&_RESTART_SCRIPT' = 'restart_instance.sql' THEN
    EXECUTE IMMEDIATE 'ALTER SYSTEM SET &_PARAM_NAME = &_PARAM_VALUE SCOPE = SPFILE';
    dbms_output.put_line('- SPFILE: &_PARAM_NAME = &_PARAM_VALUE, restart follows');
  ELSE
    dbms_output.put_line('- &_PARAM_NAME is already &_PARAM_VALUE - no change, no restart');
  END IF;
END;
/

-- restart_instance.sql, or the harmless CDB$ROOT check when nothing changed
@&_COMMON_DIR./&_RESTART_SCRIPT

PROMPT - Value after this step
SELECT name, value, isdefault FROM v$parameter WHERE name = LOWER('&_PARAM_NAME');
-- EOF -------------------------------------------------------------------------
