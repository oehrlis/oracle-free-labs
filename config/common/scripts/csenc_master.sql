--------------------------------------------------------------------------------
--  OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
--------------------------------------------------------------------------------
--  Name......: csenc_master.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2023.08.30
--  Revision..: v1.0.1
--  Purpose...: Create master encryption key for TDE configured keystore.
--              Works for CDB as well as PDB.
--  Notes.....: - Keystore must already be configured and open.
--              - No local SPOOL; logging handled by caller.
--  Reference.: Requires SYS, SYSDBA or SYSKM privilege
--  License...: Apache License Version 2.0, January 2004 as shown
--              at http://www.apache.org/licenses/
--------------------------------------------------------------------------------

-- format SQL*Plus output and behavior -----------------------------------------
SET LINESIZE 160 PAGESIZE 200
SET FEEDBACK ON

COLUMN wrl_type      FORMAT A8
COLUMN wrl_parameter FORMAT A75
COLUMN status        FORMAT A18
COLUMN wallet_type   FORMAT A15
COLUMN con_id        FORMAT 99999

-- set master key --------------------------------------------------------------
PROMPT == Configure the master encryption key ==================================
ADMINISTER KEY MANAGEMENT SET KEY FORCE
  KEYSTORE IDENTIFIED BY EXTERNAL STORE WITH BACKUP;

-- list wallet information -----------------------------------------------------
PROMPT == Encryption wallet information from v$encryption_wallet ===============
SELECT * FROM v$encryption_wallet;

-- EOF -------------------------------------------------------------------------
