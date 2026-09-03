--------------------------------------------------------------------------------
--  OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
--------------------------------------------------------------------------------
--  Name......: ssenc_filehdr.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2026.09.03
--  Revision..: v1.0.0
--  Purpose...: Dump the datafile headers and one chosen block through Oracle's
--              own tracing, as a second source next to the host side analysis.
--  Notes.....: - &1 = datafile path, &2 = block number to dump.
--              - The file_hdrs dump covers every datafile of the container and
--                is the authoritative view on what the header holds. The host
--                side hexdump only shows raw bytes, so the two complement each
--                other: Oracle names the fields, the hexdump proves the bytes.
--              - Writes into the session trace file, whose path is reported at
--                the end so the caller can collect it.
--              - Run as SYSDBA. Block dumps of a PDB datafile need the session
--                to be in that PDB.
--              - No local SPOOL; logging handled by caller.
--  Reference.: Requires SYSDBA. See also ssenc_keyproof.sql for the V$ view side
--  License...: Apache License Version 2.0, January 2004 as shown
--              at http://www.apache.org/licenses/
--------------------------------------------------------------------------------

SET LINESIZE 256 PAGESIZE 1000
SET FEEDBACK ON VERIFY OFF

DEFINE hdr_datafile = &1
DEFINE hdr_block    = &2

COLUMN trace_file FORMAT A100
COLUMN name       FORMAT A30
COLUMN value      FORMAT A100

PROMPT ========================================================================
PROMPT == Oracle side file header dump =========================================
PROMPT ========================================================================

PROMPT == Trace file for this session =========================================
SELECT value AS trace_file
FROM   v$diag_info
WHERE  name = 'Default Trace File';

PROMPT == Dump all datafile headers (file_hdrs, level 10) =====================
ALTER SESSION SET EVENTS 'immediate trace name file_hdrs level 10';

PROMPT == Dump block &hdr_block of &hdr_datafile
ALTER SYSTEM DUMP DATAFILE '&hdr_datafile' BLOCK &hdr_block;

PROMPT == Trace file to collect ===============================================
SELECT value AS trace_file
FROM   v$diag_info
WHERE  name = 'Default Trace File';

-- EOF -------------------------------------------------------------------------
