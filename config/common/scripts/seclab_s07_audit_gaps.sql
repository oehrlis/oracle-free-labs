--------------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
--------------------------------------------------------------------------------
--  Name......: seclab_s07_audit_gaps.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2026.10.15
--  Revision..: v1.0.0
--  Purpose...: seclab S07 - incomplete Unified Audit configuration: no logon
--              auditing, no policy on sensitive tables, no trail cleanup.
--  Notes.....: *** INTENTIONALLY INSECURE - lab use only ***
--              - Execute in the seclab PDB as SYSDBA (pair with require_pdb.sql).
--              - Requires create_audit_policies.sql in the same PDB.
--              - Unified Auditing itself stays on. Only the policy coverage is
--                made incomplete: a subset of the OraDBA policies is enabled,
--                every policy auditing LOGON/LOGOFF is disabled, no object
--                policy, no purge job (init_audit_config.sql is not called).
--              - Remediation class 3 (audit concept) - no FIX mode.
--  License...: Apache License Version 2.0, January 2004 as shown
--              at http://www.apache.org/licenses/
--------------------------------------------------------------------------------

-- Fail fast in automation -----------------------------------------------------
WHENEVER SQLERROR EXIT SQL.SQLCODE

PROMPT - S07 disable every enabled policy that audits LOGON or LOGOFF
-- ACTIONS ALL (standard action) audits logons as well, so it counts too.
-- audit_option = 'ALL' alone is not enough: object policies (ALL ON <object>)
-- carry the same value but do not audit logons.
DECLARE
  l_sql    VARCHAR2(512);
  l_failed PLS_INTEGER := 0;
BEGIN
  FOR r IN (SELECT DISTINCT e.policy_name, e.enabled_option, e.entity_name
              FROM audit_unified_enabled_policies e
             WHERE e.policy_name IN (SELECT p.policy_name FROM audit_unified_policies p
                                      WHERE p.audit_option IN ('LOGON', 'LOGOFF')
                                         OR (p.audit_option = 'ALL'
                                             AND p.audit_option_type = 'STANDARD ACTION'))) LOOP
    l_sql := 'NOAUDIT POLICY ' || r.policy_name;
    IF r.enabled_option = 'BY USER' AND r.entity_name <> 'ALL USERS' THEN
      l_sql := l_sql || ' BY "' || r.entity_name || '"';
    ELSIF r.enabled_option = 'BY GRANTED ROLE' THEN
      l_sql := l_sql || ' BY USERS WITH GRANTED ROLES "' || r.entity_name || '"';
    END IF;
    -- EXCEPT USER and BY USER 'ALL USERS': the plain NOAUDIT removes the enablement
    BEGIN
      EXECUTE IMMEDIATE l_sql;
      dbms_output.put_line('- ' || l_sql);
    EXCEPTION
      WHEN OTHERS THEN
        l_failed := l_failed + 1;
        dbms_output.put_line('- FAILED: ' || l_sql || ': ' || SQLERRM);
    END;
  END LOOP;
  IF l_failed > 0 THEN
    RAISE_APPLICATION_ERROR(-20015, 'S07: ' || l_failed
      || ' logon policy enablement(s) could not be removed - S07 would be incomplete');
  END IF;
END;
/

PROMPT - S07 enable only a subset of the OraDBA policies (no logon, no data access)
-- NOAUDIT first so a rerun starts from the same state, then AUDIT.
DECLARE
  TYPE t_list IS TABLE OF VARCHAR2(128);
  l_policies t_list := t_list('ORADBA_LOC_ACC_MGMT', 'ORADBA_LOC_INST_CONFIG',
                              'ORADBA_LOC_SECURE_CONFIG');
BEGIN
  FOR i IN 1 .. l_policies.COUNT LOOP
    BEGIN
      EXECUTE IMMEDIATE 'NOAUDIT POLICY ' || l_policies(i);
    EXCEPTION
      WHEN OTHERS THEN
        dbms_output.put_line('- NOAUDIT POLICY ' || l_policies(i) || ' (was not enabled: ' || SQLCODE || ')');
    END;
    EXECUTE IMMEDIATE 'AUDIT POLICY ' || l_policies(i);
    dbms_output.put_line('- AUDIT POLICY ' || l_policies(i));
  END LOOP;
END;
/

PROMPT - S07 make sure no Unified Audit purge job exists
DECLARE
  l_found BOOLEAN := FALSE;
BEGIN
  FOR r IN (SELECT job_name FROM dba_audit_mgmt_cleanup_jobs
             WHERE audit_trail LIKE 'UNIFIED%') LOOP
    sys.dbms_audit_mgmt.drop_purge_job(audit_trail_purge_name => r.job_name);
    dbms_output.put_line('- dropped purge job ' || r.job_name);
    l_found := TRUE;
  END LOOP;
  IF NOT l_found THEN
    dbms_output.put_line('- no Unified Audit purge job present');
  END IF;
END;
/

PROMPT - Enabled audit policies after this step
COL policy_name    FOR A32
COL enabled_option FOR A16
COL entity_name    FOR A20
SELECT policy_name, enabled_option, entity_name, success, failure
  FROM audit_unified_enabled_policies ORDER BY policy_name;
-- EOF -------------------------------------------------------------------------
