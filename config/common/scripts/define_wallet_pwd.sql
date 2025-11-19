--------------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
--------------------------------------------------------------------------------
--  Name......: define_wallet_pwd.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2025.11.18
--  Revision..: v1.0.0
--  Purpose...: Define wallet_pwd variable (optionally overridden by argument).
--  Notes.....:
--       - Argument &1 may override the generated password.
--       - If &1 is empty, a random password is generated.
--       - The password value is NOT printed for security reasons.
--  License...: Apache License Version 2.0
--------------------------------------------------------------------------------

-- SQL*Plus formatting ----------------------------------------------------------
SET FEEDBACK OFF VERIFY OFF

-- Create a random default password -------------------------------------------
COLUMN def_wallet_pwd NEW_VALUE def_wallet_pwd NOPRINT
SELECT dbms_random.string('X', 20) AS def_wallet_pwd FROM dual;

-- Normalize argument &1 --------------------------------------------------------
COLUMN "1" NEW_VALUE "1" NOPRINT
SELECT '' AS "1" FROM dual WHERE ROWNUM = 0;

-- Assign final password value --------------------------------------------------
DEFINE wallet_pwd = &1 &def_wallet_pwd
COLUMN wallet_pwd NEW_VALUE wallet_pwd NOPRINT

-- Restore SQL*Plus feedback ----------------------------------------------------
SET FEEDBACK ON

PROMPT - Wallet password has been set.

-- EOF -------------------------------------------------------------------------
