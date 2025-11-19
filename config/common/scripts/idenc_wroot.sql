--------------------------------------------------------------------------------
--  OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
--------------------------------------------------------------------------------
--  Name......: idenc_wroot.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2025.11.19
--  Revision..: v1.2.0
--  Purpose...: Initialize init.ora parameter WALLET_ROOT based on a provided
--              base path to set up TDE with software keystore.
--  Notes.....: - Argument &1 is expected to be the wallet_root_base, typically
--                defined by define_wallet_root_base.sql.
--              - WALLET_ROOT will be set to:
--                  &1 || '/wallet'
--              - A database restart is required after changing WALLET_ROOT.
--              - No local SPOOL; logging handled by caller.
--  Reference.: Requires SYS, SYSDBA or DBA privilege
--  License...: Apache License Version 2.0, January 2004 as shown
--              at http://www.apache.org/licenses/
--------------------------------------------------------------------------------

SET LINESIZE 160 PAGESIZE 200
SET HEADING ON
SET FEEDBACK ON
SET VERIFY OFF

COLUMN name  FORMAT A42
COLUMN value FORMAT A60

PROMPT == Configure WALLET_ROOT based on base path =============================
PROMPT    Base path (wallet_root_base) : &1
PROMPT    WALLET_ROOT                  : &1/wallet

-- create the wallet root folders ----------------------------------------------
HOST mkdir -p &1/wallet
HOST mkdir -p &1/wallet/tde
HOST mkdir -p &1/wallet/backups
HOST mkdir -p &1/wallet/tde_seps

-- list current SPFILE settings -------------------------------------------------
PROMPT == Current setting of WALLET_ROOT in SPFILE =============================
SELECT name, value
FROM   v$spparameter
WHERE  name IN ('wallet_root','tde_configuration','_db_discard_lost_masterkey')
ORDER  BY name;

-- set WALLET_ROOT in SPFILE ----------------------------------------------------
ALTER SYSTEM SET wallet_root='&1/wallet' SCOPE=SPFILE;

-- list new SPFILE settings -----------------------------------------------------
PROMPT == New setting of WALLET_ROOT in SPFILE =================================
SELECT name, value
FROM   v$spparameter
WHERE  name IN ('wallet_root','tde_configuration','_db_discard_lost_masterkey')
ORDER  BY name;

PROMPT =========================================================================
PROMPT == Please restart the database to apply the changes on WALLET_ROOT. =====
PROMPT =========================================================================

-- EOF -------------------------------------------------------------------------
