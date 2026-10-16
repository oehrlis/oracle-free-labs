--------------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
--------------------------------------------------------------------------------
--  Name......: seclab_accounts.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2026.10.15
--  Revision..: v1.0.0
--  Purpose...: seclab - weak profile, custom accounts and a small application
--              schema. Base for scenarios S03, S04, S05, S06 and S01/S02.
--  Notes.....: *** INTENTIONALLY INSECURE - lab use only ***
--              - Execute in the seclab PDB as SYSDBA (pair with require_pdb.sql).
--              - &1 password for all custom accounts (from SECLAB_USER_PWD).
--              - Idempotent: existing accounts and the profile are dropped and
--                reported first, then recreated.
--              - Run after the sqlnet.ora logon version was lowered (S03): the
--                passwords set here then carry the legacy verifiers.
--  License...: Apache License Version 2.0, January 2004 as shown
--              at http://www.apache.org/licenses/
--------------------------------------------------------------------------------

-- Fail fast in automation -----------------------------------------------------
WHENEVER SQLERROR EXIT SQL.SQLCODE

SET FEEDBACK OFF
SET VERIFY OFF
COLUMN 1 NEW_VALUE 1 NOPRINT
SELECT '' "1" FROM dual WHERE ROWNUM = 0;
DEFINE _PWD = "&1"
SET FEEDBACK ON

-- Cleanup before create -------------------------------------------------------
PROMPT - Cleanup of previous seclab accounts and profile
DECLARE
  TYPE t_list IS TABLE OF VARCHAR2(128);
  l_users t_list := t_list('APP_OWNER', 'SVC_BATCH', 'DEV_USER1', 'ANALYST1',
                           'OLD_APP', 'TEST_USER', 'LEGACY_APP');
  l_count PLS_INTEGER;
BEGIN
  IF '&&_PWD' IS NULL THEN
    RAISE_APPLICATION_ERROR(-20010, 'seclab_accounts.sql: password parameter is empty');
  END IF;
  FOR i IN 1 .. l_users.COUNT LOOP
    SELECT COUNT(*) INTO l_count FROM dba_users WHERE username = l_users(i);
    IF l_count > 0 THEN
      EXECUTE IMMEDIATE 'DROP USER ' || l_users(i) || ' CASCADE';
      dbms_output.put_line('- dropped existing user ' || l_users(i));
    END IF;
  END LOOP;
  SELECT COUNT(*) INTO l_count FROM dba_profiles WHERE profile = 'SECLAB_UNLIMITED' AND ROWNUM = 1;
  IF l_count > 0 THEN
    EXECUTE IMMEDIATE 'DROP PROFILE seclab_unlimited CASCADE';
    dbms_output.put_line('- dropped existing profile SECLAB_UNLIMITED');
  END IF;
  SELECT COUNT(*) INTO l_count FROM dba_directories WHERE directory_name = 'APP_EXPORT_DIR';
  IF l_count > 0 THEN
    EXECUTE IMMEDIATE 'DROP DIRECTORY app_export_dir';
    dbms_output.put_line('- dropped existing directory APP_EXPORT_DIR');
  END IF;
END;
/

-- S04: profile without any password or resource limit -------------------------
PROMPT - S04 create profile SECLAB_UNLIMITED (no limits, no verify function)
CREATE PROFILE seclab_unlimited LIMIT
  failed_login_attempts    UNLIMITED
  password_life_time       UNLIMITED
  password_reuse_time      UNLIMITED
  password_reuse_max       UNLIMITED
  password_lock_time       UNLIMITED
  password_grace_time      UNLIMITED
  inactive_account_time    UNLIMITED
  password_verify_function NULL
  sessions_per_user        UNLIMITED
  idle_time                UNLIMITED
  connect_time             UNLIMITED;

-- Application owner (S05: gets DBA, owns the S01/S02 objects) ----------------
PROMPT - Create application owner APP_OWNER
CREATE USER app_owner IDENTIFIED BY "&&_PWD"
  DEFAULT TABLESPACE users QUOTA UNLIMITED ON users;
GRANT CREATE SESSION, CREATE TABLE, CREATE PROCEDURE, CREATE VIEW TO app_owner;

-- Service account on the personal-account profile (S04) ----------------------
PROMPT - Create service account SVC_BATCH on profile SECLAB_UNLIMITED
CREATE USER svc_batch IDENTIFIED BY "&&_PWD" PROFILE seclab_unlimited;
GRANT CREATE SESSION TO svc_batch;

-- Personal accounts on the weak profile (S04, S05) ----------------------------
PROMPT - Create personal accounts DEV_USER1 and ANALYST1 on profile SECLAB_UNLIMITED
CREATE USER dev_user1 IDENTIFIED BY "&&_PWD" PROFILE seclab_unlimited;
CREATE USER analyst1  IDENTIFIED BY "&&_PWD" PROFILE seclab_unlimited;
GRANT CREATE SESSION TO dev_user1, analyst1;

-- Open accounts that are never used (S06) -------------------------------------
PROMPT - Create unused accounts OLD_APP and TEST_USER (open, never logged in)
CREATE USER old_app   IDENTIFIED BY "&&_PWD";
CREATE USER test_user IDENTIFIED BY "&&_PWD";
GRANT CREATE SESSION TO old_app, test_user;

-- Account for the legacy verifier scenario (S03) ------------------------------
PROMPT - Create LEGACY_APP (password set under the lowered logon version)
CREATE USER legacy_app IDENTIFIED BY "&&_PWD";
GRANT CREATE SESSION TO legacy_app;

-- Small application schema -----------------------------------------------------
PROMPT - Create application objects in APP_OWNER
CREATE TABLE app_owner.customers (
  customer_id NUMBER        CONSTRAINT customers_pk PRIMARY KEY,
  full_name   VARCHAR2(100) NOT NULL,
  email       VARCHAR2(100),
  iban        VARCHAR2(34),
  created_at  DATE          DEFAULT SYSDATE
);
INSERT INTO app_owner.customers (customer_id, full_name, email, iban)
  VALUES (1, 'Demo Customer One', 'one@example.com', 'XX00TEST0000000000000001');
INSERT INTO app_owner.customers (customer_id, full_name, email, iban)
  VALUES (2, 'Demo Customer Two', 'two@example.com', 'XX00TEST0000000000000002');
INSERT INTO app_owner.customers (customer_id, full_name, email, iban)
  VALUES (3, 'Demo Customer Three', 'three@example.com', 'XX00TEST0000000000000003');
COMMIT;

CREATE OR REPLACE PACKAGE app_owner.app_util AS
  FUNCTION version RETURN VARCHAR2;
  FUNCTION customer_count RETURN NUMBER;
END app_util;
/
CREATE OR REPLACE PACKAGE BODY app_owner.app_util AS
  FUNCTION version RETURN VARCHAR2 IS
  BEGIN
    RETURN 'seclab app 1.0';
  END version;
  FUNCTION customer_count RETURN NUMBER IS
    l_count NUMBER;
  BEGIN
    SELECT COUNT(*) INTO l_count FROM app_owner.customers;
    RETURN l_count;
  END customer_count;
END app_util;
/

-- Verification ------------------------------------------------------------------
PROMPT - Accounts created by seclab_accounts.sql
COL username       FOR A16
COL profile        FOR A20
COL account_status FOR A16
COL password_versions FOR A20
SELECT username, profile, account_status, password_versions
  FROM dba_users
 WHERE username IN ('APP_OWNER', 'SVC_BATCH', 'DEV_USER1', 'ANALYST1',
                    'OLD_APP', 'TEST_USER', 'LEGACY_APP')
 ORDER BY username;
-- EOF -------------------------------------------------------------------------
