--------------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
--------------------------------------------------------------------------------
--  Name......: 10_config_tde_odbencdev.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2026.09.03
--  Revision..: v1.0.0
--  Purpose...: Configure TDE for ODBENCDEV using WALLET_ROOT and an independent
--              software keystore with its own master encryption key.
--              This is the non-production / restore-target database; it holds
--              NO user data PDB and NO demo schemas - only the CDB keystore.
--  Notes.....: - Must be executed as SYSDBA connected to CDB$ROOT.
--              - WALLET_ROOT resolves to /opt/oracle/dbconfig/FREE/wallet inside
--                the container - the same path pattern as odbencprod but mapped
--                to a different host directory, exactly mirroring the customer
--                scenario where Prod and Dev use separate keystores.
--              - Wallet password is generated via define_wallet_pwd.sql.
--              - The script restarts the database twice:
--                  1) After setting WALLET_ROOT
--                  2) After creating the master encryption key
--  Reference.: - define_logging_begin.sql / define_logging_end.sql
--              - require_cdb_root.sql
--              - define_wallet_root_base.sql
--              - define_wallet_pwd.sql
--              - idenc_wroot.sql
--              - csenc_swkeystore.sql
--              - csenc_master.sql
--              - ssenc_info.sql
--  License...: Apache License Version 2.0, January 2004 as shown
--              at http://www.apache.org/licenses/
--------------------------------------------------------------------------------

-- Fail fast in automation ------------------------------------------------------
WHENEVER SQLERROR EXIT SQL.SQLCODE

-- SQL*Plus formatting ----------------------------------------------------------
-- Show results + PROMPTs, but do not echo SQL text or comments.
SET LINESIZE 256 PAGESIZE 1000
SET SERVEROUTPUT ON FEEDBACK ON ECHO OFF TERMOUT ON VERIFY OFF

-- Begin logging ---------------------------------------------------------------
DEFINE LOG_PREFIX = '10_config_tde_odbencdev'
DEFINE LOG_DIR    = '/opt/oracle/scripts/logs'
@/opt/oracle/common/scripts/define_logging_begin.sql

-- Ensure we are in CDB$ROOT (not a PDB) ---------------------------------------
@/opt/oracle/common/scripts/require_cdb_root.sql

PROMPT ========================================================================
PROMPT == Configure TDE for ODBENCDEV =========================================
PROMPT ========================================================================

PROMPT == Define wallet base path and password ================================

-- Derive / define wallet_root_base (from AUDIT_FILE_DEST or &2 override)
@/opt/oracle/common/scripts/define_wallet_root_base.sql

-- Derive / define wallet_pwd (random or &1 override)
@/opt/oracle/common/scripts/define_wallet_pwd.sql

PROMPT == Configure WALLET_ROOT ===============================================

-- Configure WALLET_ROOT using the resolved wallet_root_base
@/opt/oracle/common/scripts/idenc_wroot.sql &wallet_root_base

PROMPT == Restart database to apply WALLET_ROOT ===============================
STARTUP FORCE;

PROMPT == Create and configure software keystore ==============================

-- Create software keystore in WALLET_ROOT and configure TDE_CONFIGURATION
@/opt/oracle/common/scripts/csenc_swkeystore.sql &wallet_pwd

PROMPT == Configure master encryption key =====================================

-- Create the independent master encryption key for the Dev keystore
@/opt/oracle/common/scripts/csenc_master.sql

PROMPT == Restart database to load keystore / master key ======================
STARTUP FORCE;

PROMPT == Current TDE configuration ===========================================

-- Show resulting TDE configuration
@/opt/oracle/common/scripts/ssenc_info.sql

-- End logging -----------------------------------------------------------------
@/opt/oracle/common/scripts/define_logging_end.sql
-- EOF -------------------------------------------------------------------------
