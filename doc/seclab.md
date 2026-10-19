# seclab - Scenario Catalog

> **INTENTIONALLY INSECURE - lab use only.** `seclab` is a database with known,
> documented weaknesses for security assessment and remediation testing. Never
> expose it to a network, never reuse its passwords, never copy its settings
> into another system.

This document is the reference for every scenario: what is wrong, how it is
produced, how it is proven, which remediation class it belongs to and which
DBSAT finding is expected. The hands-on steps are in
[seclab-runbook.md](seclab-runbook.md).

## Verified Platform

All scenarios were produced and verified on:

- Oracle AI Database 26ai Free, release **23.26.3.0.0**
  (`container-registry.oracle.com/database/free:latest`, image version label 23.26.0)
- arm64 (Apple Silicon), Docker Desktop and Colima (vz, virtiofs)
- Unified Auditing in pure mode (`V$OPTION 'Unified Auditing' = TRUE`)
- Two targets: PDB `SECPDB1` of the `seclab` service and `FREEPDB1` of a plain,
  unmodified Oracle Free container (`scripts/apply_usecase.sh seclab`)

On another release the result can differ. The verification script says so per
scenario instead of assuming.

## Remediation Classes

| Class | Meaning | In this lab |
| --- | --- | --- |
| 1 - single change | One statement or one script, low risk, can be rolled back | Fix script with `FIX` / `INSECURE` mode |
| 2 - with pre-check | The change can break something; a read-only pre-check finds it first | Pre-check script, remediation described |
| 3 - measure package | Needs a concept (role model, audit concept, key management) | Playbook topic only, deliberately no SQL |

## Overview

<!-- markdownlint-disable MD013 MD060 -->
| ID | Weakness | Class | Produced by | DBSAT 4.3 finding (measured) |
| --- | --- | --- | --- | --- |
| S01 | Custom object privileges granted to PUBLIC | 1 | `seclab_s01_public_grants.sql INSECURE` | PRIV.OBJPUBLIC (Evaluate) |
| S02 | Application code uses `UTL_FILE` only through the PUBLIC grant | 2 | `seclab_s02_utl_file_dependency.sql` | PRIV.FILESYSTEMPACKAGEPUBLIC (Evaluate) |
| S03 | Low `SQLNET.ALLOWED_LOGON_VERSION_SERVER`, accounts with 11G verifier | 2 | `set_sqlnet_param.sh`, `seclab_accounts.sql` | USER.AUTHVERSION (High Risk), USER.AUTHLEGACY (Evaluate) |
| S04 | Profile without limits for personal and service accounts | 2 | `seclab_accounts.sql` | USER.NOLOCK (Medium Risk), USER.PASSWORDFUNCTION (Medium Risk), USER.NOEXPIRE (Low Risk) |
| S05 | Application owner with DBA, `SELECT ANY TABLE`, `WITH ADMIN OPTION` | 3 | `seclab_s05_overprivileged.sql` | PRIV.DBA (Evaluate), PRIV.ANYSYSTEM (Evaluate) |
| S06 | Open custom accounts that were never used | 1 | `seclab_s06_unused_accounts.sql INSECURE` | USER.NEW (Evaluate); USER.INACTIVE (Evaluate) does not name the accounts, see S06 |
| S07 | Unified Audit incomplete: no logon audit, no object policy, no cleanup | 3 | `seclab_s07_audit_gaps.sql` | AUDIT.SENSITIVEOBJS (Advisory); AUDIT.CONNECTIONS **Pass**, no cleanup rule - see note |
| S08 | Sensitive demo data unencrypted, no keystore | 3 | default state | ENCRYPT.TDE (Evaluate), ENCRYPT.WALLET (Evaluate) |
| S09 | Network encryption and integrity not enforced | 3 | `set_sqlnet_param.sh` | NET.ENCRYPTION (Advisory) |
| S10 | Static parameter `SQL92_SECURITY = FALSE` | 1 + restart | `set_static_param.sql` | CONF.SQL92SECURITY (Medium Risk) |
| S11 | Sample schema SCOTT open with its default password | 1 | `seclab_s11_default_password.sql INSECURE` | USER.DEFPASSWORD (High Risk), USER.SAMPLE (Low Risk) |
<!-- markdownlint-restore -->

**About the DBSAT column.** Rule ID and status as reported by DBSAT 4.3
(July 2026) against SECPDB1 of the seclab service, runs on 2026-10-16 and
2026-10-19 with identical results (all eleven scenarios `PRESENT` in
`seclab_verify.sh`; S07: see note - `seclab_verify.sh` and DBSAT disagree on
logon audit). Other releases may name or rate rules
differently. Deviations from the scenario intent:

- **S06:** `USER.INACTIVE` judges by days since the last login (threshold 35
  days) and names only the S04 accounts with unlimited `INACTIVE_ACCOUNT_TIME`.
  The never-used accounts `OLD_APP` and `TEST_USER` appear under `USER.NEW`
  ("not logged in since account creation").
- **S07:** `AUDIT.CONNECTIONS` reports **Pass**: DBSAT sees `LOGON` and `LOGOFF`
  audited for all users through the policy `ORADBA_LOC_SECURE_CONFIG`, while
  `seclab_verify.sh` counts 0 enabled logon policies. Which view is right is
  not clarified yet. The 4.3 report has no rule ID for audit trail cleanup
  (`AUDIT.CLEANUPJOBS`, listed here before, does not appear); the purge
  settings only appear in the unrated table "Audit Management Configuration Parameters".

CIS benchmark numbers are deliberately not listed - add them only with a
source.

## Verification

```bash
make verify-seclab                      # seclab service
docker exec <container> /opt/oracle/common/scripts/seclab_verify.sh -p FREEPDB1
```

`seclab_verify.sh` is read-only. It prints one line per ID
(`PRESENT` / `ABSENT` / `NOT REPRODUCIBLE`) and exits with 0 (all present),
1 (at least one absent) or 2 (the check itself could not run, or a line is
missing). Measured output on 23.26.3:

```text
S01 PRESENT - 2 custom grant(s) to PUBLIC: SELECT ON SCOTT.EMP, EXECUTE ON APP_OWNER.APP_UTIL
S02 PRESENT - PUBLIC EXECUTE on UTL_FILE=1, APP_EXPORT depends on UTL_FILE=1, direct grant to APP_OWNER=0
S03 PRESENT - ALLOWED_LOGON_VERSION_SERVER=11, LEGACY_APP password_versions=11G 12C
S04 PRESENT - SECLAB_UNLIMITED weak limits=3/3, assigned to ANALYST1,DEV_USER1,SVC_BATCH
S05 PRESENT - APP_OWNER has DBA=1, DEV_USER1 SELECT ANY TABLE=1, ANALYST1 SELECT ANY TABLE WITH ADMIN OPTION=1
S06 PRESENT - 2 open account(s) never logged in: OLD_APP,TEST_USER
S07 PRESENT - enabled logon policies=0, enabled policies on sensitive schemas=0, unified purge jobs=0
S08 PRESENT - encrypted tablespaces=0, keystore status=NOT_AVAILABLE
S09 PRESENT - SQLNET.ENCRYPTION_SERVER=ACCEPTED, SQLNET.CRYPTO_CHECKSUM_SERVER=ACCEPTED
S10 PRESENT - sql92_security=FALSE
S11 PRESENT - SCOTT open with default password=1
Summary: 11 PRESENT, 0 ABSENT, 0 NOT REPRODUCIBLE, 0 MISSING
```

## Accounts and Objects

All passwords come from `.env` (`SECLAB_USER_PWD`, `SECLAB_SCOTT_PWD`), none is
in the code. Scope: the target PDB.

<!-- markdownlint-disable MD013 MD060 -->
| Account | Role in the lab | Scenarios |
| --- | --- | --- |
| `APP_OWNER` | Application owner, table `CUSTOMERS`, package `APP_UTIL`, procedure `APP_EXPORT` | S01, S02, S05 |
| `SVC_BATCH` | Technical service account, logs in regularly | S04 |
| `DEV_USER1`, `ANALYST1` | Personal accounts | S04, S05 |
| `OLD_APP`, `TEST_USER` | Open, never used | S06 |
| `LEGACY_APP` | Legacy client account | S03 |
| `SCOTT`, `TVD_HR`, `TVD_HR_SEC` | Demo schemas (`create_scott.sql`, `create_tvd_hr.sql`) | S01, S11 |
<!-- markdownlint-restore -->

`seclab_simulate_logins.sh` logs in once with every account that is "in use",
so `DBA_USERS.LAST_LOGIN` separates them from the S06 accounts. The
`CUSTOMERS` rows are fictitious (`example.com`, `XX00TEST...` account numbers).

## Scenarios

### S01 - Custom Object Privileges Granted to PUBLIC

- **Weakness:** `SELECT ON SCOTT.EMP` and `EXECUTE ON APP_OWNER.APP_UTIL` are
  granted to PUBLIC - every account of the PDB can read salaries and call the
  package.
- **Produced by:** `seclab_s01_public_grants.sql INSECURE`. The grant list
  exists only in this script, so setup, fix and rollback cannot drift apart.
- **Proof:**

  ```sql
  SELECT owner, table_name, privilege FROM dba_tab_privs
   WHERE grantee = 'PUBLIC' AND owner IN ('SCOTT', 'APP_OWNER');
  ```

- **Class 1 - remediation and rollback:**

  ```bash
  R=/opt/oracle/common/scripts/run_sql_script.sh
  docker compose exec seclab $R -p SECPDB1 seclab_s01_public_grants.sql FIX       # revoke
  docker compose exec seclab $R -p SECPDB1 seclab_s01_public_grants.sql INSECURE  # rollback
  ```

  Measured: after `FIX` the verification reports `S01 ABSENT` and exits 1,
  after `INSECURE` all eleven scenarios are present again.

### S02 - Application Code Depends on UTL_FILE Through PUBLIC

- **Weakness:** `EXECUTE ON SYS.UTL_FILE` is granted to PUBLIC (default of
  23.26 - the script only grants it if it is missing and says so).
  `APP_OWNER.APP_EXPORT` writes a CSV with `UTL_FILE` into directory
  `APP_EXPORT_DIR` (`/opt/oracle/scripts/logs`). `APP_OWNER` has no direct
  grant on `UTL_FILE` - and the DBA role does not help, because definer rights
  code ignores roles.
- **Produced by:** `seclab_s02_utl_file_dependency.sql`; the setup runs the
  procedure once (`seclab_app_export.csv` in the log directory).
- **Proof:** PUBLIC grant present, dependency in `DBA_DEPENDENCIES`, no direct
  grant to `APP_OWNER` (see verification line).
- **Class 2 - pre-check:**
  `run_sql_script.sh -p SECPDB1 precheck_revoke_public.sql UTL_FILE`.
  Measured result:

  ```text
  WOULD BREAK: APP_OWNER.APP_EXPORT (PROCEDURE, VALID) - no direct grant, works only through PUBLIC
  Result: 1 object(s) would break. Grant EXECUTE ON SYS.UTL_FILE directly to the owner(s) first, then revoke.
  ```

- **Remediation:** grant `EXECUTE ON SYS.UTL_FILE` directly to `APP_OWNER`,
  then revoke from PUBLIC, recompile and test the application. A blind revoke
  invalidates `APP_EXPORT`.

### S03 - Low Logon Version and Legacy Verifiers

- **Weakness:** `SQLNET.ALLOWED_LOGON_VERSION_SERVER = 11` in the server
  `sqlnet.ora`. Every password set while this value is in place carries the
  SHA-1 based `11G` verifier next to `12C`.
- **Produced by:** `set_sqlnet_param.sh` (before the accounts are created),
  then `seclab_accounts.sql` sets the passwords.
- **Measured on 23.26.3** - verifiers after `ALTER USER ... IDENTIFIED BY`:

  | ALLOWED_LOGON_VERSION_SERVER | PASSWORD_VERSIONS |
  | --- | --- |
  | 8, 10, 11 | `11G 12C` |
  | 12 (default, not set) | `11G 12C` |
  | 12a | `12C` |

  - The **10G verifier is not reproducible** on 23.26.3: values 8 and 10 are
    accepted in `sqlnet.ora`, but no `10G` verifier is generated. The scenario
    is therefore built on the `11G` verifier.
  - Even the default (parameter not set = 12) generates `11G` - SYS, SYSTEM
    and PDBADMIN of a fresh container carry it. Only `12a` removes it. S03
    makes the weak setting explicit; the finding itself also exists on a
    default container.
- **Proof:** sqlnet.ora value plus `DBA_USERS.PASSWORD_VERSIONS` of
  `LEGACY_APP`. The `LEGACY_APP` login in the setup proves that the server
  accepts it.
- **Class 2 - pre-check:** `precheck_logon_version.sql 12a` lists accounts
  that would be locked out (no `12C` verifier) and those that keep an old
  verifier. Measured: 0 lockouts, 11 accounts with `11G`.
- **Remediation order:** verifiers first, then the logon version. Accounts
  without `12C` get a password reset first, then the parameter goes to `12a`,
  then the passwords are reset again so that only `12C` remains. The reverse
  order locks accounts without `12C` out.

### S04 - Profile Without Limits, Service Account on It

- **Weakness:** profile `SECLAB_UNLIMITED` has every password and resource
  limit `UNLIMITED` and no verify function. Personal accounts (`DEV_USER1`,
  `ANALYST1`) **and** the service account `SVC_BATCH` use it.
- **Produced by:** `seclab_accounts.sql`.
- **Proof:** `DBA_PROFILES` (3 of 3 weak limits) and the assignments in
  `DBA_USERS`.
- **Class 2 - pre-check:** `precheck_profile_hardening.sql SECLAB_UNLIMITED`
  separates personal from probable service accounts (name heuristic
  `^(SVC_|APP_|BATCH)`). Measured: `SVC_BATCH` flagged as service account.
- **Remediation:** a dedicated service profile for `SVC_BATCH` (no lifetime,
  lockout aligned with the operating concept), then harden the personal
  profile. Hardening first would let the service account expire or lock.

### S05 - Over-Privileged Accounts

- **Weakness:** `APP_OWNER` has the DBA role, `DEV_USER1` has
  `SELECT ANY TABLE`, `ANALYST1` has `SELECT ANY TABLE WITH ADMIN OPTION`.
- **Produced by:** `seclab_s05_overprivileged.sql`.
- **Proof:** `DBA_ROLE_PRIVS`, `DBA_SYS_PRIVS` (verification line).
- **Class 3 - playbook topic:** least-privilege role model. Inventory the
  privileges actually used (privilege analysis), define application, developer
  and analyst roles, migrate accounts to the roles, then remove the direct
  grants. A mass revoke is not a remedy and is therefore not scripted.

### S06 - Open Accounts That Were Never Used

- **Weakness:** `OLD_APP` and `TEST_USER` are open with a password and have
  never logged in (`LAST_LOGIN` empty).
- **Produced by:** `seclab_accounts.sql`, `seclab_s06_unused_accounts.sql INSECURE`.
- **Class 1 - remediation and rollback:** lock, do not drop.

  ```bash
  docker compose exec seclab $R -p SECPDB1 seclab_s06_unused_accounts.sql FIX       # lock
  docker compose exec seclab $R -p SECPDB1 seclab_s06_unused_accounts.sql INSECURE  # unlock
  ```

- **DBSAT note (4.3, measured):** `USER.INACTIVE` judges by the time since the
  last login and does not name accounts created minutes ago. `OLD_APP` and
  `TEST_USER` are listed under `USER.NEW` (Evaluate) instead.

### S07 - Incomplete Unified Audit Configuration

- **Weakness:** Unified Auditing is on, but the coverage is incomplete:
  - every policy that audits `LOGON`/`LOGOFF` is disabled in the PDB - also
    `ACTIONS ALL` policies (standard action `ALL`), which audit logons too,
    while object policies with `ALL ON <object>` are left alone. On a fresh
    23.26.3 PDB this was `ORA_LOGIN_LOGOUT`, enabled by default. If an
    enablement cannot be removed (for example one made in `CDB$ROOT`), the
    script fails instead of reporting an incomplete S07;
  - of the OraDBA policies only `ORADBA_LOC_ACC_MGMT`, `ORADBA_LOC_INST_CONFIG`
    and `ORADBA_LOC_SECURE_CONFIG` are enabled;
  - no policy covers `SCOTT`, `TVD_HR` or `APP_OWNER` objects;
  - no Unified Audit purge job (`init_audit_config.sql` is deliberately not run).
- **Produced by:** `create_audit_policies.sql`, then `seclab_s07_audit_gaps.sql`
  (NOAUDIT first, then AUDIT for the subset, so a rerun starts from the same
  state).
- **Scope:** local to the PDB. In `CDB$ROOT` `ORA_LOGIN_LOGOUT` stays enabled.
- **Proof:** `AUDIT_UNIFIED_ENABLED_POLICIES` joined with
  `AUDIT_UNIFIED_POLICIES`, `DBA_AUDIT_MGMT_CLEANUP_JOBS`.
- **Class 3 - playbook topic:** audit concept - which events (logon, privileged
  activity, access to sensitive data), retention, trail management
  (`DBMS_AUDIT_MGMT` partitioning and purge), forwarding to a central store.
  The enabled policies of the `labdb` service show one target state.

### S08 - Unencrypted Sensitive Data, No Keystore

- **Weakness:** `TVD_HR`, `SCOTT` and `APP_OWNER.CUSTOMERS` live in the
  unencrypted `USERS` tablespace; there is no keystore (`WALLET_ROOT` and
  `TDE_CONFIGURATION` empty, `V$ENCRYPTION_WALLET` = `NOT_AVAILABLE`,
  `TABLESPACE_ENCRYPTION = MANUAL_ENABLE`).
- **Produced by:** nothing - this is the default of the image. The scenario
  only makes sure no TDE setup runs.
- **Class 3 - playbook topic:** key management and TDE rollout (keystore type
  and location, united vs isolated mode, backup of the keystore, online or
  offline encryption, impact on backup and cloning). The `odbenc*` services
  of this repository show one implementation.

### S09 - Network Encryption Not Enforced

- **Weakness:** `SQLNET.ENCRYPTION_SERVER = ACCEPTED` and
  `SQLNET.CRYPTO_CHECKSUM_SERVER = ACCEPTED`: the server encrypts only if a
  client asks for it. Default clients do not.
- **Produced by:** `set_sqlnet_param.sh` (explicit values instead of the
  silent default, so the intent is visible).
- **Class 3 - playbook topic:** client compatibility (JDBC thin, old drivers,
  tools), choice between native network encryption and TLS, rollout via
  `REQUESTED` before `REQUIRED`.

### S10 - Static Security Parameter Weakened

- **Weakness:** `SQL92_SECURITY = FALSE`: a user with UPDATE or DELETE on a
  table can infer column values through the WHERE clause without SELECT.
  Default is `TRUE`; the parameter is static (`ISSYS_MODIFIABLE = FALSE`).
- **Produced by:** `set_static_param.sql sql92_security FALSE` in `CDB$ROOT`
  (SPFILE, restart only when the value differs - measured: a second run
  reports "no change, no restart").
- **Class 1 with restart:**

  ```bash
  docker compose exec seclab $R set_static_param.sql sql92_security TRUE    # fix, restarts
  docker compose exec seclab $R set_static_param.sql sql92_security FALSE   # rollback, restarts
  ```

  A run plan must show the restart. PDBs with a saved state reopen;
  `restart_instance.sql` lists the open modes afterwards.

### S11 - Sample Schema With Default Password

- **Weakness:** `SCOTT` is open with its well-known default password and is
  listed in `DBA_USERS_WITH_DEFPWD`.
- **Produced by:** `create_scott.sql`, then
  `seclab_s11_default_password.sql INSECURE <password>` - the password comes
  from `SECLAB_SCOTT_PWD`.
- **Class 1 - remediation:** `seclab_s11_default_password.sql FIX` sets a
  random password and locks the account; `INSECURE` restores the scenario.

## Not in the Lab

- No operating system weaknesses, no open network listener, no changes to
  the container itself. The ports are bound to `127.0.0.1`, and
  `scripts/apply_usecase.sh` refuses to apply seclab to a container that
  publishes ports beyond localhost.
- No remediation SQL for class 3 - these are concepts, not statements.
