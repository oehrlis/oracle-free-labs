--------------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
--------------------------------------------------------------------------------
--  Name......: select_scott.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@trivadis.com
--  Editor....: Stefan Oehrli
--  Date......: 2025.11.19
--  Revision..:
--  Purpose...: Script to select and manipulate data in the SCOTT schema
--              for Oracle SQL Firewall Training Mode
--  Notes.....: Execute this script multiple times while SQL Firewall is in
--              TRAINING mode for user SCOTT (or the test user accessing
--              SCOTT objects).
--  Reference.: SYS (or grant manually to a DBA)
--  License...: Apache License Version 2.0, January 2004 as shown
--              at http://www.apache.org/licenses/LICENSE-2.0
--------------------------------------------------------------------------------
--  Modified..:
--  see git revision history for more information on changes/updates
--------------------------------------------------------------------------------

-- Optional: basic SQL*Plus settings
SET PAGESIZE 200
SET LINESIZE 120
SET SERVEROUTPUT ON
SET VERIFY OFF
SET FEEDBACK ON

PROMPT ============================================================
PROMPT SCOTT Workload for SQL Firewall Training Mode
PROMPT Execute this script while SQL Firewall is in TRAINING mode
PROMPT ============================================================

-- -----------------------------------------------------------------------------
-- 1. Basic SELECT Queries
-- -----------------------------------------------------------------------------

SELECT * FROM emp;
SELECT * FROM dept;
SELECT * FROM bonus;
SELECT * FROM salgrade;

SELECT empno, ename, job, sal
FROM   emp
WHERE  deptno = 10;

SELECT dname, loc
FROM   dept
WHERE  deptno = 20;

SELECT ename, comm
FROM   emp
WHERE  comm IS NOT NULL;

SELECT ename, sal
FROM   emp
WHERE  sal BETWEEN 1500 AND 3000;

-- -----------------------------------------------------------------------------
-- 2. Joins
-- -----------------------------------------------------------------------------

SELECT e.empno,
       e.ename,
       e.job,
       d.dname,
       d.loc
FROM   emp  e
       JOIN dept d
         ON e.deptno = d.deptno;

SELECT e.ename,
       e.sal,
       d.dname
FROM   emp  e
       JOIN dept d
         ON e.deptno = d.deptno
WHERE  e.sal > 2500;

SELECT e.ename,
       e.sal,
       s.grade
FROM   emp      e
       JOIN salgrade s
         ON e.sal BETWEEN s.losal AND s.hisal
ORDER  BY s.grade;

-- -----------------------------------------------------------------------------
-- 3. Grouping & Aggregations
-- -----------------------------------------------------------------------------

SELECT deptno,
       COUNT(*)               AS emp_count,
       AVG(sal)               AS avg_sal
FROM   emp
GROUP  BY deptno;

SELECT job,
       MIN(sal)               AS min_sal,
       MAX(sal)               AS max_sal
FROM   emp
GROUP  BY job;

SELECT deptno,
       SUM(sal + NVL(comm,0)) AS total_cost
FROM   emp
GROUP  BY deptno
ORDER  BY total_cost DESC;

-- -----------------------------------------------------------------------------
-- 4. Subqueries
-- -----------------------------------------------------------------------------

SELECT ename,
       sal
FROM   emp
WHERE  sal > (SELECT AVG(sal) FROM emp);

SELECT deptno,
       dname
FROM   dept
WHERE  deptno IN (SELECT DISTINCT deptno FROM emp);

SELECT ename
FROM   emp
WHERE  mgr IN (SELECT empno
               FROM   emp
               WHERE  job = 'MANAGER');

-- -----------------------------------------------------------------------------
-- 5. INSERT Statements
-- -----------------------------------------------------------------------------

INSERT INTO bonus (ename, job, sal, comm)
VALUES ('TIGER', 'ANALYST', 3000, NULL);

INSERT INTO dept (deptno, dname, loc)
VALUES (50, 'DATA', 'ZURICH');

INSERT INTO emp (empno, ename, job, mgr,
                 hiredate, sal, comm, deptno)
VALUES (8001, 'ALICE', 'CLERK', 7902,
        SYSDATE, 1200, NULL, 20);

-- -----------------------------------------------------------------------------
-- 6. UPDATE Statements
-- -----------------------------------------------------------------------------

UPDATE emp
SET    sal = sal * 1.05
WHERE  deptno = 10;

UPDATE dept
SET    loc = 'GENEVA'
WHERE  deptno = 50;

UPDATE emp
SET    comm = NVL(comm, 0) + 100
WHERE  job  = 'SALESMAN';

-- -----------------------------------------------------------------------------
-- 7. DELETE Statements
-- -----------------------------------------------------------------------------

DELETE FROM bonus
WHERE  ename = 'TIGER';

DELETE FROM emp
WHERE  empno = 8001;

DELETE FROM dept
WHERE  deptno = 50;

-- -----------------------------------------------------------------------------
-- 8. PL/SQL Anonymous Blocks
-- -----------------------------------------------------------------------------

PROMPT Running PL/SQL block 1: salary adjustments in dept 30...

BEGIN
   FOR r IN (SELECT empno
             FROM   emp
             WHERE  deptno = 30) LOOP
      UPDATE emp
      SET    sal = sal + 10
      WHERE  empno = r.empno;
   END LOOP;
END;
/
SHOW ERRORS

PROMPT Running PL/SQL block 2: count employees in dept 20...

DECLARE
   v_cnt  NUMBER;
BEGIN
   SELECT COUNT(*)
   INTO   v_cnt
   FROM   emp
   WHERE  deptno = 20;

   DBMS_OUTPUT.PUT_LINE('Employees in department 20: ' || v_cnt);
END;
/
SHOW ERRORS

PROMPT Running PL/SQL block 3: calculate additional commission...

BEGIN
   FOR r IN (SELECT empno,
                    sal
             FROM   emp
             WHERE  job = 'SALESMAN') LOOP
      UPDATE emp
      SET    comm = NVL(comm, 0) + (r.sal * 0.05)
      WHERE  empno = r.empno;
   END LOOP;
END;
/
SHOW ERRORS

-- -----------------------------------------------------------------------------
-- 9. Commit Changes
-- -----------------------------------------------------------------------------

COMMIT;

PROMPT ============================================================
PROMPT SCOTT workload finished.
PROMPT Review SQL Firewall learning data for user / policy.
PROMPT ============================================================
-- EOF -------------------------------------------------------------------------