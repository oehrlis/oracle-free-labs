--------------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
--------------------------------------------------------------------------------
--  Name......: 30_config_tde_odbenc.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2025.11.19
--  Revision..: v1.2.0
--  Purpose...: Configure TDE for ODBENC using WALLET_ROOT and software
--              keystore, including master key creation.
--  Notes.....: - Must be executed as SYSDBA connected to CDB$ROOT.
--              - WALLET_ROOT is configured via:
--                  define_wallet_root_base.sql  -> wallet_root_base
--                  idenc_wroot.sql &wallet_root_base
--              - Wallet password is generated via define_wallet_pwd.sql.
--              - The script restarts the database:
--                  1) After setting WALLET_ROOT
--                  2) After configuring the master encryption key
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
DEFINE LOG_PREFIX = '30_config_tde_odbenc'
DEFINE LOG_DIR    = '/opt/oracle/scripts/logs'
@/opt/oracle/common/scripts/define_logging_begin.sql

-- Ensure we are in CDB$ROOT (not a PDB) ---------------------------------------
@/opt/oracle/common/scripts/require_cdb_root.sql

PROMPT ========================================================================
PROMPT == Configure TDE for ODBENC ============================================
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

-- Create / set the master encryption key using the external store
@/opt/oracle/common/scripts/csenc_master.sql

PROMPT == Restart database to load keystore / master key ======================
STARTUP FORCE;

PROMPT == Current TDE configuration ===========================================

-- Show resulting TDE configuration and encrypted objects
@/opt/oracle/common/scripts/ssenc_info.sql

-- End logging -----------------------------------------------------------------
@/opt/oracle/common/scripts/define_logging_end.sql
-- EOF -------------------------------------------------------------------------
