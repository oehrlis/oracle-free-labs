--------------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
--------------------------------------------------------------------------------
--  Name......: gather_missing_stats.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2026.10.20
--  Revision..: v1.0.0
--  Purpose...: Name the tables without optimizer statistics (NUM_ROWS NULL)
--              in a schema scope and optionally gather them.
--  Notes.....: - Execute in the PDB as SYSDBA (run_sql_script.sh -p PDB).
--              - &1 schema scope: ALL or a comma separated list (default ALL)
--              - &2 REPORT (default, read-only) or GATHER
--              - &3 Y to include Oracle-maintained schemas (default N)
--              - Why: DBSAT discover filters tables by MINROWS on NUM_ROWS.
--                A table without statistics is skipped without a message
--                (measured with DBSAT 4.3: SCOTT.BONUS). This script makes
--                the gap visible, it never hides a table.
--              - GATHER uses DBMS_STATS.GATHER_SCHEMA_STATS with
--                OPTIONS => 'GATHER EMPTY': only objects without statistics
--                are touched, existing statistics stay as they are.
--                Oracle-maintained schemas are never gathered here (named as
--                INFO, use DBMS_STATS.GATHER_DICTIONARY_STATS for them).
--              - Temporary, external, nested and dropped tables and IOT
--                overflow segments are not counted.
--              - A schema in a non-ALL scope that does not exist is named as
--                WARN: no "every table has statistics" for a typo.
--              - Parameters are taken with q'~...~' quoting and validated
--                (REGEXP_LIKE, fixed mode list) before they are used. This
--                is input validation for a lab script run as SYSDBA, not a
--                defence against a hostile caller.
--  Usage.....: @gather_missing_stats.sql ALL GATHER
--  License...: Apache License Version 2.0, January 2004 as shown
--              at http://www.apache.org/licenses/
--------------------------------------------------------------------------------

-- Fail fast in automation -----------------------------------------------------
WHENEVER SQLERROR EXIT SQL.SQLCODE

SET FEEDBACK OFF
SET VERIFY OFF
SET SERVEROUTPUT ON SIZE UNLIMITED
COLUMN 1 NEW_VALUE 1 NOPRINT
COLUMN 2 NEW_VALUE 2 NOPRINT
COLUMN 3 NEW_VALUE 3 NOPRINT
SELECT '' "1" FROM dual WHERE ROWNUM = 0;
SELECT '' "2" FROM dual WHERE ROWNUM = 0;
SELECT '' "3" FROM dual WHERE ROWNUM = 0;
DEFINE _SCOPE = &1 ALL
DEFINE _MODE  = &2 REPORT
DEFINE _MAINT = &3 N

DECLARE
  l_scope VARCHAR2(4000) := UPPER(REPLACE(q'~&&_SCOPE~', ' '));
  l_mode  VARCHAR2(10)   := UPPER(q'~&&_MODE~');
  l_maint VARCHAR2(1)    := UPPER(SUBSTR(q'~&&_MAINT~', 1, 1));
  l_name    VARCHAR2(128);
  l_absent  PLS_INTEGER := 0;
  l_exists  PLS_INTEGER;
  l_max   CONSTANT PLS_INTEGER := 50;
  l_count PLS_INTEGER := 0;
  l_left  PLS_INTEGER := 0;
  TYPE t_names IS TABLE OF VARCHAR2(128);
  l_owners     t_names := t_names();
  l_maintained t_names := t_names();

  -- Tables in scope without statistics; one row per table
  CURSOR c_missing IS
    SELECT t.owner, t.table_name, u.oracle_maintained
      FROM dba_tables t
      JOIN dba_users u ON u.username = t.owner
     WHERE t.num_rows IS NULL
       AND t.temporary = 'N'
       AND t.nested = 'NO'
       AND t.dropped = 'NO'
       AND (t.iot_type IS NULL OR t.iot_type = 'IOT')
       AND NOT EXISTS (SELECT 1 FROM dba_external_tables e
                        WHERE e.owner = t.owner AND e.table_name = t.table_name)
       AND (u.oracle_maintained = 'N' OR l_maint = 'Y')
       AND (l_scope = 'ALL' OR INSTR(',' || l_scope || ',', ',' || t.owner || ',') > 0)
     ORDER BY t.owner, t.table_name;

  FUNCTION count_missing RETURN PLS_INTEGER IS
    l_n PLS_INTEGER := 0;
  BEGIN
    FOR r IN c_missing LOOP
      l_n := l_n + 1;
    END LOOP;
    RETURN l_n;
  END count_missing;
BEGIN
  IF l_mode NOT IN ('REPORT', 'GATHER') THEN
    RAISE_APPLICATION_ERROR(-20010, 'gather_missing_stats.sql: mode must be REPORT or GATHER, not ' || l_mode);
  END IF;
  IF l_scope IS NULL OR NOT REGEXP_LIKE(l_scope, '^[A-Z0-9_$#,]+$') THEN
    RAISE_APPLICATION_ERROR(-20011, 'gather_missing_stats.sql: invalid schema scope ' || l_scope);
  END IF;

  -- a schema that does not exist has no tables: name it, do not report green
  IF l_scope <> 'ALL' THEN
    FOR i IN 1 .. REGEXP_COUNT(l_scope, '[^,]+') LOOP
      l_name := REGEXP_SUBSTR(l_scope, '[^,]+', 1, i);
      SELECT COUNT(*) INTO l_exists FROM dba_users WHERE username = l_name;
      IF l_exists = 0 THEN
        l_absent := l_absent + 1;
        dbms_output.put_line('WARN: schema ' || l_name || ' in scope does not exist');
      END IF;
    END LOOP;
  END IF;

  FOR r IN c_missing LOOP
    l_count := l_count + 1;
    IF l_owners.COUNT = 0 OR l_owners(l_owners.LAST) <> r.owner THEN
      l_owners.EXTEND;
      l_owners(l_owners.LAST) := r.owner;
      l_maintained.EXTEND;
      l_maintained(l_maintained.LAST) := r.oracle_maintained;
    END IF;
    IF l_count <= l_max THEN
      dbms_output.put_line('WARN: no optimizer statistics: ' || r.owner || '.' || r.table_name);
    END IF;
  END LOOP;
  IF l_count > l_max THEN
    dbms_output.put_line('WARN: ... and ' || (l_count - l_max) || ' more tables without statistics');
  END IF;
  IF l_count = 0 THEN
    IF l_absent = 0 THEN
      dbms_output.put_line('INFO: every table in scope ' || l_scope || ' has optimizer statistics');
    ELSE
      dbms_output.put_line('WARN: ' || l_absent || ' schema(s) in scope ' || l_scope
        || ' do not exist - only the existing ones have optimizer statistics');
    END IF;
    RETURN;
  END IF;

  IF l_mode = 'REPORT' THEN
    dbms_output.put_line('WARN: ' || l_count || ' table(s) in scope ' || l_scope
      || ' without statistics - DBSAT discover skips them (MINROWS)');
    dbms_output.put_line('WARN: fix: EXEC DBMS_STATS.GATHER_SCHEMA_STATS(''<SCHEMA>'', options => ''GATHER EMPTY'')'
      || ' or run_dbsat.sh -m discover -g');
    RETURN;
  END IF;

  FOR i IN 1 .. l_owners.COUNT LOOP
    IF l_maintained(i) = 'Y' THEN
      dbms_output.put_line('INFO: ' || l_owners(i) || ' is Oracle-maintained - not gathered here'
        || ' (DBMS_STATS.GATHER_DICTIONARY_STATS)');
    ELSE
      DBMS_STATS.GATHER_SCHEMA_STATS(ownname => l_owners(i), options => 'GATHER EMPTY');
      dbms_output.put_line('INFO: gathered missing statistics for schema ' || l_owners(i));
    END IF;
  END LOOP;

  l_left := count_missing;
  IF l_left = 0 THEN
    dbms_output.put_line('INFO: all ' || l_count || ' table(s) without statistics are gathered now');
  ELSE
    dbms_output.put_line('WARN: ' || l_left || ' of ' || l_count
      || ' table(s) still without statistics - DBSAT discover skips them (MINROWS)');
  END IF;
END;
/
-- EOF -------------------------------------------------------------------------
