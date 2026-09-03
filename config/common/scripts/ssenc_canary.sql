--------------------------------------------------------------------------------
--  OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
--------------------------------------------------------------------------------
--  Name......: ssenc_canary.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2026.09.03
--  Revision..: v1.0.0
--  Purpose...: Read back the canary table after a clone or a key removal and
--              report whether the encrypted data is still accessible.
--  Notes.....: - &1 = owner, &2 = expected marker, &3 = table name.
--              - Used for the key withdrawal test: after removing the source
--                master key from the target keystore, this either returns the
--                rows (target is independent of the source key) or fails with
--                ORA-28365 / ORA-28374 (target still depends on it).
--              - Deliberately does not use WHENEVER SQLERROR EXIT: the error is
--                the result here and must be captured in the log, not abort it.
--              - No local SPOOL; logging handled by caller.
--  Reference.: Requires SELECT on the canary table
--  License...: Apache License Version 2.0, January 2004 as shown
--              at http://www.apache.org/licenses/
--------------------------------------------------------------------------------

SET LINESIZE 256 PAGESIZE 1000
SET SERVEROUTPUT ON FEEDBACK ON VERIFY OFF

DEFINE canary_owner = &1
DEFINE canary_mark  = &2
DEFINE canary_tab   = &3

COLUMN container    FORMAT A20
COLUMN marker       FORMAT A40
COLUMN payload_head FORMAT A24
COLUMN verdict      FORMAT A60

PROMPT ========================================================================
PROMPT == Read canary &canary_owner..&canary_tab
PROMPT ========================================================================

SELECT sys_context('userenv','con_name') AS container FROM dual;

PROMPT == Row count and marker match ==========================================
SELECT COUNT(*)                                                  AS rows_total,
       COUNT(CASE WHEN marker = '&canary_mark' THEN 1 END)        AS marker_match,
       MIN(id)                                                    AS min_id,
       MAX(id)                                                    AS max_id
FROM   &canary_owner..&canary_tab;

PROMPT == Sample rows =========================================================
SELECT id,
       marker,
       SUBSTR(payload, 1, 20) AS payload_head
FROM   &canary_owner..&canary_tab
WHERE  id <= 3
ORDER  BY id;

PROMPT == Verdict =============================================================
SELECT CASE
           WHEN COUNT(*) = 0
               THEN 'NO ROWS - table empty or not restored'
           WHEN COUNT(*) = COUNT(CASE WHEN marker = '&canary_mark' THEN 1 END)
               THEN 'READABLE - all rows decrypt with the keys present here'
           ELSE 'PARTIAL - row count and marker match disagree'
       END AS verdict
FROM   &canary_owner..&canary_tab;

-- EOF -------------------------------------------------------------------------
