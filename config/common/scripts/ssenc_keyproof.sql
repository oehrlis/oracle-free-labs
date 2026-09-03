--------------------------------------------------------------------------------
--  OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
--------------------------------------------------------------------------------
--  Name......: ssenc_keyproof.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2026.09.03
--  Revision..: v1.0.0
--  Purpose...: Evidence snapshot of the TDE key chain, for before/after
--              comparison of an RMAN clone. Shows which master key wraps which
--              tablespace key, plus the wrapped tablespace key itself.
--  Notes.....: - Complements ssenc_info.sql, which does not report MASTERKEYID,
--                ENCRYPTEDKEY or KEY_VERSION.
--              - Run in CDB$ROOT and again in the PDB; the encrypted tablespace
--                rows live in the PDB container.
--              - No V$ view exposes the tablespace key itself, only the version
--                wrapped under the master key. ENCRYPTEDKEY therefore changes on
--                a master key re-wrap as well as on a real tablespace rekey - it
--                proves the key chain, not that the data was re-encrypted. For
--                the latter compare the datafile blocks (block_fingerprint.py).
--              - No local SPOOL; logging handled by caller.
--  Reference.: Requires SYS, SYSDBA or SYSKM privilege
--  License...: Apache License Version 2.0, January 2004 as shown
--              at http://www.apache.org/licenses/
--------------------------------------------------------------------------------

-- format SQL*Plus output and behavior -----------------------------------------
SET LINESIZE 256 PAGESIZE 1000
SET HEADING ON FEEDBACK ON VERIFY OFF

COLUMN container            FORMAT A20
COLUMN db_name              FORMAT A12
COLUMN db_unique_name       FORMAT A16
COLUMN wrl_type             FORMAT A8
COLUMN wrl_parameter        FORMAT A70
COLUMN status               FORMAT A18
COLUMN wallet_type          FORMAT A15
COLUMN key_id               FORMAT A56
COLUMN key_use              FORMAT A10
COLUMN keystore_type        FORMAT A14
COLUMN origin               FORMAT A10
COLUMN backed_up            FORMAT A9
COLUMN creation_time        FORMAT A22
COLUMN activation_time      FORMAT A22
COLUMN ts_name              FORMAT A20
COLUMN encryptionalg        FORMAT A8
COLUMN encryptedts          FORMAT A3
COLUMN masterkeyid_hex      FORMAT A34
COLUMN encryptedkey_hex     FORMAT A66
COLUMN file_name            FORMAT A70
COLUMN con_id               FORMAT 99999

ALTER SESSION SET nls_timestamp_tz_format = 'DD.MM.YYYY HH24:MI:SS';

PROMPT ========================================================================
PROMPT == TDE key chain evidence snapshot =====================================
PROMPT ========================================================================

PROMPT == Identity of this database ===========================================
SELECT sys_context('userenv','con_name') AS container,
       name                              AS db_name,
       db_unique_name,
       dbid,
       created,
       log_mode,
       open_mode
FROM   v$database;

PROMPT == Keystore state from v$encryption_wallet =============================
SELECT wrl_type, wrl_parameter, status, wallet_type, keystore_mode, con_id
FROM   v$encryption_wallet
ORDER  BY con_id;

PROMPT == Master encryption keys from v$encryption_keys =======================
-- ORIGIN distinguishes a key created here (LOCAL) from one brought in from
-- another database (IMPORTED) - central for the prod/non-prod separation claim.
SELECT key_id,
       key_use,
       keystore_type,
       origin,
       backed_up,
       creation_time,
       activation_time,
       creator_pdbname,
       activating_pdbname,
       con_id
FROM   v$encryption_keys
ORDER  BY creation_time;

PROMPT == Tablespace key chain from v$encrypted_tablespaces ===================
-- MASTERKEYID  : which master key wraps this tablespace key
-- ENCRYPTEDKEY : the tablespace key, wrapped under that master key
-- KEY_VERSION  : increments on encrypt/decrypt/rekey, resets to 0 after a
--                plug-in into a foreign database or a control file recreation
SELECT t.name                     AS ts_name,
       et.ts#,
       et.encryptionalg,
       et.encryptedts,
       RAWTOHEX(et.masterkeyid)   AS masterkeyid_hex,
       et.key_version,
       et.status,
       RAWTOHEX(et.encryptedkey)  AS encryptedkey_hex,
       et.blocks_encrypted,
       et.blocks_decrypted,
       et.con_id
FROM   v$encrypted_tablespaces et,
       v$tablespace            t
WHERE  et.ts# = t.ts#
AND    et.con_id = t.con_id
ORDER  BY t.name;

PROMPT == Full v$encrypted_tablespaces row (version specific columns) =========
-- Kept as SELECT * on purpose: CIPHERMODE (CFB vs XTS) only exists from 23ai on
-- and must not break this script on an older release.
SELECT * FROM v$encrypted_tablespaces;

PROMPT == Implicit database key for SYSTEM / UNDO / TEMP ======================
SELECT * FROM v$database_key_info;

PROMPT == Datafiles of encrypted tablespaces ==================================
-- RELATIVE_FNO and BLOCK_SIZE are needed to map a rowid to a byte offset in the
-- datafile on the host, which is where the block level comparison happens.
SELECT df.tablespace_name  AS ts_name,
       df.relative_fno,
       df.file_name,
       df.blocks,
       ts.block_size,
       df.bytes
FROM   dba_data_files  df,
       dba_tablespaces ts
WHERE  df.tablespace_name = ts.tablespace_name
AND    ts.encrypted       = 'YES'
ORDER  BY df.tablespace_name, df.relative_fno;

-- EOF -------------------------------------------------------------------------
