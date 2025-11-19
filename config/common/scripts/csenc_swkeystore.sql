--------------------------------------------------------------------------------
--  OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
--------------------------------------------------------------------------------
--  Name......: csenc_swkeystore.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2025.11.19
--  Revision..: v1.2.0
--  Purpose...: Create TDE software keystore in WALLET_ROOT.
--  Notes.....: - Argument &1 = wallet password (required).
--              - WALLET_ROOT must already be set and database restarted.
--              - No local SPOOL; logging handled by caller.
--  Reference.: Requires SYS, SYSDBA or SYSKM privilege
--  License...: Apache License Version 2.0, January 2004 as shown
--              at http://www.apache.org/licenses/
--------------------------------------------------------------------------------

SET LINESIZE 160 PAGESIZE 200
SET FEEDBACK ON
SET VERIFY OFF

COLUMN wrl_type      FORMAT A8
COLUMN wrl_parameter FORMAT A75
COLUMN status        FORMAT A18
COLUMN wallet_type   FORMAT A15
COLUMN con_id        FORMAT 99999

-- derive wallet_root from current WALLET_ROOT ----------------------------------
COLUMN wallet_root NEW_VALUE wallet_root NOPRINT

SELECT TRIM(TRAILING '/' FROM value
            ||'/'
            ||NVL((SELECT RAWTOHEX(guid)
                   FROM   v$pdbs
                   WHERE  con_id = sys_context('userenv','con_id')),
                  '')) AS wallet_root
FROM   v$parameter
WHERE  name = 'wallet_root';

PROMPT == Configure software keystore in WALLET_ROOT ===========================
PROMPT    WALLET_ROOT path : &wallet_root
PROMPT    Wallet password  : **** (hidden)

-- create the wallet folder ----------------------------------------------------
HOST mkdir -p &wallet_root
HOST mkdir -p &wallet_root/tde_seps

-- store wallet password (with backup if file exists) --------------------------
PROMPT == Store the wallet password in &wallet_root/wallet_pwd.txt
HOST if [ -e &wallet_root/wallet_pwd.txt ]; then \
  cp &wallet_root/wallet_pwd.txt &wallet_root/wallet_pwd_$(date +%Y%m%d%H%M).bck; \
  fi
HOST echo &1 > &wallet_root/wallet_pwd.txt
HOST chmod 600 &wallet_root/wallet_pwd.txt

PROMPT == Configure the software keystore ======================================

-- configure TDE_CONFIGURATION for file-based keystore -------------------------
ALTER SYSTEM SET TDE_CONFIGURATION='KEYSTORE_CONFIGURATION=FILE' SCOPE=BOTH;

-- create software keystore in WALLET_ROOT -------------------------------------
ADMINISTER KEY MANAGEMENT CREATE KEYSTORE IDENTIFIED BY "&1";

-- create an external keystore password store in WALLET_ROOT -------------------
ADMINISTER KEY MANAGEMENT ADD SECRET '&1'
  FOR CLIENT 'TDE_WALLET'
  TO LOCAL AUTO_LOGIN KEYSTORE '&wallet_root/tde_seps';

-- open the software keystore using external store -----------------------------
ADMINISTER KEY MANAGEMENT SET KEYSTORE OPEN FORCE
  KEYSTORE IDENTIFIED BY EXTERNAL STORE;

-- create local auto-login keystore from software keystore ---------------------
ADMINISTER KEY MANAGEMENT CREATE LOCAL AUTO_LOGIN KEYSTORE
  FROM KEYSTORE '&wallet_root/tde'
  IDENTIFIED BY "&1";

-- list wallet information -----------------------------------------------------
PROMPT == Encryption wallet information from v$encryption_wallet ===============
SELECT * FROM v$encryption_wallet;

-- EOF -------------------------------------------------------------------------
