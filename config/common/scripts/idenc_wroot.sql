--------------------------------------------------------------------------------
--  OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
--------------------------------------------------------------------------------
--  Name......: idenc_wroot.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2023.12.19
--  Revision..: v1.0.1
--  Purpose...: Initialize init.ora parameter WALLET_ROOT based on value of
--              AUDIT_FILE_DEST to setup TDE with software keystore. This
--              script should run in CDB$ROOT. A manual restart
--              of the database is mandatory to activate WALLET_ROOT.
--  Notes.....: - No local SPOOL; logging is expected to be handled by caller
--                (e.g. via define_logging_begin.sql).
--  Reference.: Requires SYS, SYSDBA or DBA privilege
--  License...: Apache License Version 2.0, January 2004 as shown
--              at http://www.apache.org/licenses/
--------------------------------------------------------------------------------

-- define default values --------------------------------------------------------
COLUMN def_admin_path NEW_VALUE def_admin_path NOPRINT

-- get the admin directory from audit_file_dest --------------------------------
SELECT SUBSTR(value, 1, INSTR(value, '/', -1, 1) - 1) AS def_admin_path
FROM   v$parameter
WHERE  name = 'audit_file_dest';

-- assign default value for parameter if argument 1 is empty --------------------
COLUMN "1" NEW_VALUE "1" NOPRINT
SELECT '' AS "1" FROM dual WHERE ROWNUM = 0;

DEFINE admin_path = &1 &def_admin_path
COLUMN admin_path NEW_VALUE admin_path NOPRINT

-- format SQL*Plus output and behavior -----------------------------------------
SET LINESIZE 160 PAGESIZE 200
SET HEADING ON
SET FEEDBACK ON

COLUMN name  FORMAT A42
COLUMN value FORMAT A60

-- create the wallet root folders ----------------------------------------------
HOST mkdir -p &admin_path/wallet
HOST mkdir -p &admin_path/wallet/tde
HOST mkdir -p &admin_path/wallet/backups
HOST mkdir -p &admin_path/wallet/tde_seps

-- list init.ora parameter for TDE information in SPFILE -----------------------
PROMPT == Current setting of WALLET_ROOT in SPFILE =============================
SELECT name, value
FROM   v$spparameter
WHERE  name IN ('wallet_root','tde_configuration','_db_discard_lost_masterkey')
ORDER  BY name;

-- set the WALLET ROOT parameter ------------------------------------------------
ALTER SYSTEM SET wallet_root='&admin_path/wallet' SCOPE=SPFILE;

-- list init.ora parameter for TDE information in SPFILE -----------------------
PROMPT == New setting of WALLET_ROOT in SPFILE =================================
SELECT name, value
FROM   v$spparameter
WHERE  name IN ('wallet_root','tde_configuration','_db_discard_lost_masterkey')
ORDER  BY name;

PROMPT =========================================================================
PROMPT == Please restart the database to apply the changes on WALLET_ROOT. =====
PROMPT =========================================================================

-- EOF -------------------------------------------------------------------------