--------------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
--------------------------------------------------------------------------------
--  Name......: define_wallet_pwd.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2025.11.19
--  Revision..: v1.1.0
--  Purpose...: Define wallet_pwd variable for TDE configuration scripts.
--              Default: random 20-character string via DBMS_RANDOM.
--  Notes.....:
--       - No positional parameters (&1) are used here.
--       - No local SPOOL; logging handled by caller.
--  License...: Apache License Version 2.0
--------------------------------------------------------------------------------

SET FEEDBACK OFF VERIFY OFF

-- Generate default wallet password --------------------------------------------
COLUMN def_wallet_pwd NEW_VALUE def_wallet_pwd NOPRINT

SELECT dbms_random.string('X', 20) AS def_wallet_pwd
FROM   dual;

-- Define wallet_pwd substitution variable -------------------------------------
DEFINE wallet_pwd = &def_wallet_pwd
COLUMN wallet_pwd NEW_VALUE wallet_pwd NOPRINT

SET FEEDBACK ON

PROMPT - Wallet password has been set (value not displayed for security).

-- EOF -------------------------------------------------------------------------
