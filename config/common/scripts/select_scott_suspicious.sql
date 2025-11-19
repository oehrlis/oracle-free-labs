--------------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
--------------------------------------------------------------------------------
--  Name......: select_scott_suspicious.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@trivadis.com
--  Editor....: Stefan Oehrli
--  Date......: 2025.11.19
--  Revision..:
--  Purpose...: Script with suspicious SQL statements to test Oracle
--              SQL Firewall blocking / enforcement behavior
--  Notes.....: Run this script while SQL Firewall is in TRAINING mode
--              for a test phase, then switch to ENFORCEMENT and verify
--              that these statements are blocked.
--  Reference.: SYS (or grant manually to a DBA)
--  License...: Apache License Version 2.0, January 2004 as shown
--              at http://www.apache.org/licenses/LICENSE-2.0
--------------------------------------------------------------------------------
--  Modified..:
--  see git revision history for more information on changes/updates
--------------------------------------------------------------------------------

SET PAGESIZE 200
SET LINESIZE 200
SET SERVEROUTPUT ON
SET VERIFY OFF
SET FEEDBACK ON

PROMPT ============================================================
PROMPT Suspicious SCOTT / generic workload for SQL Firewall tests
PROMPT These statements should normally be BLOCKED in production
PROMPT ============================================================

-- -----------------------------------------------------------------------------
-- 1. Overly broad queries and table enumeration
-- -----------------------------------------------------------------------------

PROMPT 1.1 Full table scan with trivial predicate on EMP...

SELECT *
FROM   emp
WHERE  1 = 1;

PROMPT 1.2 Cartesian join between EMP and DEPT (no join condition)...

SELECT *
FROM   emp e,
       dept d;

PROMPT 1.3 Select with unnecessary OR predicates (typical for injection) ...

SELECT *
FROM   emp
WHERE  ename = 'KING'
   OR  'A' = 'A';

-- -----------------------------------------------------------------------------
-- 2. Metadata and schema enumeration
-- -----------------------------------------------------------------------------

PROMPT 2.1 List all tables for current user...

SELECT table_name
FROM   user_tables;

PROMPT 2.2 List all tables for SCOTT user via ALL_TABLES...

SELECT owner,
       table_name
FROM   all_tables
WHERE  owner = 'SCOTT';

PROMPT 2.3 Enumerate all columns of EMP using ALL_TAB_COLUMNS...

SELECT owner,
       table_name,
       column_name,
       data_type
FROM   all_tab_columns
WHERE  owner      = 'SCOTT'
AND    table_name = 'EMP';

PROMPT 2.4 Enumerate all users (could be sensitive)...

SELECT username,
       account_status
FROM   dba_users;

-- -----------------------------------------------------------------------------
-- 3. Access to system / data dictionary internals
--    These typically require higher privileges and should not be allowed
--    to normal application users.
-- -----------------------------------------------------------------------------

PROMPT 3.1 Access internal user$ table (highly sensitive)...

SELECT name,
       password,
       spare4
FROM   sys.user$;

PROMPT 3.2 Access sys.obj$ listing...

SELECT obj#,
       name,
       type#
FROM   sys.obj$
WHERE  rownum <= 20;

PROMPT 3.3 Access v$ views (performance / security sensitive)...

SELECT name,
       value
FROM   v$parameter
WHERE  rownum <= 20;

SELECT username,
       osuser,
       machine,
       program
FROM   v$session
WHERE  rownum <= 20;

-- -----------------------------------------------------------------------------
-- 4. Obvious SQL injection patterns in WHERE clause
--    These mimic typical application injection input.
-- -----------------------------------------------------------------------------

PROMPT 4.1 Classic OR 1=1 pattern with string concatenation style...

SELECT *
FROM   emp
WHERE  ename = 'KING'' OR ''1'' = ''1';

PROMPT 4.2 Injection-like numeric predicate...

SELECT *
FROM   emp
WHERE  empno = 7369
   OR  1 = 1;

PROMPT 4.3 Injection with comment marker...

SELECT *
FROM   emp
WHERE  ename = 'KING'' --'
   OR  'X' = 'X';

PROMPT 4.4 Injection pattern with UNION ALL...

SELECT empno,
       ename,
       job,
       sal
FROM   emp
WHERE  ename = 'KING'
UNION ALL
SELECT 1,
       'HACK',
       'INJECT',
       999999
FROM   dual;

-- -----------------------------------------------------------------------------
-- 5. Potentially dangerous DDL and privilege-related statements
--    These are often disallowed for application users.
-- -----------------------------------------------------------------------------

PROMPT 5.1 Create table copy of EMP in SCOTT schema...

CREATE TABLE emp_copy_suspicious AS
SELECT *
FROM   emp;

PROMPT 5.2 Attempt to create a user (should not be possible as SCOTT)...

CREATE USER suspicious_user IDENTIFIED BY "Welcome1";

PROMPT 5.3 Attempt to grant DBA to a user...

GRANT dba TO suspicious_user;

PROMPT 5.4 Drop table (data-destructive)...

DROP TABLE emp_copy_suspicious PURGE;

-- -----------------------------------------------------------------------------
-- 6. Misc suspicious queries combining SCOTT and data dictionary
-- -----------------------------------------------------------------------------

PROMPT 6.1 Join EMP with DBA_USERS through a crafted condition...

SELECT e.empno,
       e.ename,
       u.username,
       u.account_status
FROM   emp        e,
       dba_users  u
WHERE  e.ename = u.username;

PROMPT 6.2 Select with function calls that leak environment information...

SELECT SYS_CONTEXT('USERENV','SESSION_USER') AS session_user,
       SYS_CONTEXT('USERENV','IP_ADDRESS')    AS ip_address,
       SYS_CONTEXT('USERENV','HOST')          AS host_name
FROM   dual;

PROMPT 6.3 Dynamic-looking text that might be used to build SQL in app...

SELECT 'SELECT * FROM emp WHERE ename = ''' || ename || ''''
       AS generated_sql
FROM   emp
WHERE  deptno = 10;

-- -----------------------------------------------------------------------------
-- 7. Long and complex predicates (typical brute-force / probing patterns)
-- -----------------------------------------------------------------------------

PROMPT 7.1 Overly complex predicate with many OR branches...

SELECT *
FROM   emp
WHERE  ename = 'KING'
   OR  ename = 'JAMES'
   OR  ename = 'MILLER'
   OR  ename = 'FORD'
   OR  ename = 'SCOTT'
   OR  sal   > 5000
   OR  1     = 1;

PROMPT 7.2 Predicate mixing LIKE with wildcards...

SELECT *
FROM   emp
WHERE  ename LIKE '%A%'
   OR  job   LIKE '%MAN%'
   OR  deptno IN (10, 20, 30)
   OR  ename LIKE '%''%';

-- -----------------------------------------------------------------------------
-- 8. Clean-up / rollback
--    In most cases, the above DDL will fail for SCOTT, but if not,
--    the following ROLLBACK avoids committing changes.
-- -----------------------------------------------------------------------------

ROLLBACK;

PROMPT ============================================================
PROMPT Suspicious workload finished.
PROMPT These statements are good candidates to be BLOCKED by SQL Firewall.
PROMPT ============================================================

-- EOF -------------------------------------------------------------------------