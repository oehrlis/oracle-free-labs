--------------------------------------------------------------------------------
--  OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
--------------------------------------------------------------------------------
--  Name......: csenc_canary.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2026.09.03
--  Revision..: v1.0.0
--  Purpose...: Create a canary table with a known clear-text marker in a given
--              tablespace and report the physical location of its blocks.
--  Notes.....: - &1 = owner, &2 = tablespace, &3 = marker, &4 = number of rows,
--                &5 = table name.
--              - The table name is a parameter so the same canary can be built
--                twice: once in the encrypted tablespace and once in a plain
--                one. The plain copy is the control group that makes the
--                clear-text scan falsifiable - if the marker is not found
--                there either, the scan itself is broken.
--              - The marker is stored in every row, so a plain-text scan of the
--                datafile either finds it in many blocks (tablespace not
--                encrypted) or in none (encrypted). That makes the scan itself
--                falsifiable instead of relying on a single row.
--              - Reported RELATIVE_FNO and BLOCK_NUMBER map a row to a byte
--                offset in the datafile: offset = block_number * block_size.
--              - Run inside the PDB that owns the tablespace.
--              - No local SPOOL; logging handled by caller.
--  Reference.: Requires CREATE TABLE on the target schema
--  License...: Apache License Version 2.0, January 2004 as shown
--              at http://www.apache.org/licenses/
--------------------------------------------------------------------------------

SET LINESIZE 256 PAGESIZE 1000
SET SERVEROUTPUT ON FEEDBACK ON VERIFY OFF

DEFINE canary_owner = &1
DEFINE canary_ts    = &2
DEFINE canary_mark  = &3
DEFINE canary_rows  = &4
DEFINE canary_tab   = &5

COLUMN owner        FORMAT A20
COLUMN table_name   FORMAT A20
COLUMN ts_name      FORMAT A20
COLUMN file_name    FORMAT A70
COLUMN marker       FORMAT A40

PROMPT ========================================================================
PROMPT == Create canary table &canary_owner..&canary_tab in &canary_ts
PROMPT ========================================================================

-- drop a leftover from a previous run ------------------------------------------
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE &canary_owner..&canary_tab PURGE';
    dbms_output.put_line('dropped existing &canary_owner..&canary_tab');
EXCEPTION
    WHEN OTHERS THEN
        IF sqlcode = -942 THEN
            dbms_output.put_line('no existing &canary_owner..&canary_tab to drop');
        ELSE
            RAISE;
        END IF;
END;
/

CREATE TABLE &canary_owner..&canary_tab (
    id       NUMBER          NOT NULL,
    marker   VARCHAR2(64)    NOT NULL,
    payload  VARCHAR2(400)   NOT NULL,
    CONSTRAINT &canary_tab._pk PRIMARY KEY (id)
)
TABLESPACE &canary_ts;

-- The payload is deterministic, not random: a later run must be able to produce
-- byte identical content, otherwise a block comparison across runs is worthless.
INSERT INTO &canary_owner..&canary_tab (id, marker, payload)
SELECT LEVEL,
       '&canary_mark',
       RPAD('CANARY-'||TO_CHAR(LEVEL, 'FM0000000')||'-', 400, 'X')
FROM   dual
CONNECT BY LEVEL <= &canary_rows;

COMMIT;

PROMPT == Row count and segment size ==========================================
SELECT COUNT(*) AS canary_rows FROM &canary_owner..&canary_tab;

SELECT owner,
       segment_name AS table_name,
       tablespace_name AS ts_name,
       blocks,
       bytes
FROM   dba_segments
WHERE  owner = UPPER('&canary_owner')
AND    segment_name = UPPER('&canary_tab');

PROMPT == Physical block range of the canary rows =============================
-- offset in the datafile = block_number * block_size
SELECT dbms_rowid.rowid_relative_fno(rowid)        AS relative_fno,
       MIN(dbms_rowid.rowid_block_number(rowid))   AS min_block,
       MAX(dbms_rowid.rowid_block_number(rowid))   AS max_block,
       COUNT(DISTINCT dbms_rowid.rowid_block_number(rowid)) AS distinct_blocks,
       COUNT(*)                                    AS rows_total
FROM   &canary_owner..&canary_tab
GROUP  BY dbms_rowid.rowid_relative_fno(rowid)
ORDER  BY relative_fno;

PROMPT == Datafile holding the canary ==========================================
SELECT df.relative_fno,
       df.file_name,
       ts.block_size,
       df.blocks,
       df.bytes
FROM   dba_data_files  df,
       dba_tablespaces ts
WHERE  df.tablespace_name = ts.tablespace_name
AND    df.tablespace_name = UPPER('&canary_ts')
ORDER  BY df.relative_fno;

PROMPT == Marker for the host side plain-text scan ============================
SELECT '&canary_mark' AS marker FROM dual;

-- EOF -------------------------------------------------------------------------
