--------------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
--------------------------------------------------------------------------------
--  Name......: define_wallet_root_base.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2025.11.19
--  Revision..: v1.2.0
--  Purpose...: Define wallet_root_base variable for TDE configuration scripts.
--              Default (container layout):
--                 <diagnostic_dest>/dbconfig/<instance_name>
--              Example in FREE container:
--                 diagnostic_dest = /opt/oracle
--                 instance_name   = FREE
--                 => wallet_root_base = /opt/oracle/dbconfig/FREE
--              WALLET_ROOT will then be:
--                 /opt/oracle/dbconfig/FREE/wallet
--              when used by idenc_wroot.sql.
--  Notes.....:
--       - Argument &2 may override the automatically detected wallet_root_base.
--       - No local SPOOL; logging handled by caller (e.g. 30_config_tde_odbenc).
--       - Should be executed in CDB$ROOT.
--  License...: Apache License Version 2.0
--------------------------------------------------------------------------------

-- SQL*Plus formatting ----------------------------------------------------------
SET FEEDBACK OFF VERIFY OFF

-- Derive default wallet_root_base from diagnostic_dest and instance_name -------
--   diagnostic_dest ≈ ORACLE_BASE
--   instance_name   ≈ ORACLE_SID (FREE in the Free container)
COLUMN def_wallet_root_base NEW_VALUE def_wallet_root_base NOPRINT

SELECT
       RTRIM(value, '/') ||
       '/dbconfig/' ||
       sys_context('userenv','instance_name') AS def_wallet_root_base
FROM   v$parameter
WHERE  name = 'diagnostic_dest';

-- Optional override via &2 -----------------------------------------------------
-- Example:
--   @30_config_tde_odbenc.sql <wallet_pwd> /some/other/dbconfig/MYSID
COLUMN "2" NEW_VALUE "2" NOPRINT
SELECT '' AS "2" FROM dual WHERE ROWNUM = 0;

DEFINE wallet_root_base = &2 &def_wallet_root_base
COLUMN wallet_root_base NEW_VALUE wallet_root_base NOPRINT

SET FEEDBACK ON

PROMPT - wallet_root_base resolved to: &wallet_root_base.
PROMPT - WALLET_ROOT will be: &wallet_root_base./wallet

-- EOF -------------------------------------------------------------------------
