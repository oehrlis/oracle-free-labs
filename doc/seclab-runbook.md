# seclab Runbook - Quick Start

> **INTENTIONALLY INSECURE - lab use only.** The database contains known
> weaknesses on purpose. Its ports are bound to `127.0.0.1`; keep it that way.

`seclab` gives security assessment and remediation tools (DBSAT, Data Safe,
own checks, AI-assisted assessments) a database with real, catalogued findings.
The scenario catalog is [seclab.md](seclab.md). No prior OraDBA knowledge is
needed for this runbook.

There are two ways to get it:

| Path | You have | Command | Time (measured, arm64) |
| --- | --- | --- | --- |
| A - lab service | this repository, built image | `make up-seclab` | about 2 min on first start |
| B - any container | a running Oracle Database Free container | `scripts/apply_usecase.sh seclab <container>` | under 20 s after the DB is open |

## Prerequisites

- macOS on Apple Silicon or Linux (amd64/arm64) with Docker Desktop or Colima;
  Podman is documented but not verified. Host preparation, VM size and the
  offline case: [container-runtime-runbook.md](container-runtime-runbook.md).
- 4 GB memory for the engine (6 GB recommended), about 20 GB free disk.
- The repository cloned **below `$HOME`** (required for Colima).

## Path A - seclab as Lab Service

### 1. Configure

```bash
cd ~/oracle-free-labs
cp .env.example .env            # skip if you already have one
```

Edit `.env`:

```bash
DB_BASE_IMAGE=container-registry.oracle.com/database/free:latest
SECLAB_USER_PWD=<your lab password>     # all demo accounts
SECLAB_SCOTT_PWD=tiger                  # the S11 default password scenario
SECLAB_DBSAT_PWD=<your lab password>    # only for DBSAT
```

Passwords live only in `.env` (ignored by Git). Use values you do not use
anywhere else.

### 2. Build the Image (Online, Once)

`make build` is **required** for the service: the named services set
`TNS_ADMIN=/opt/oracle/network/admin`, a symlink that only the extended image
contains. With the plain Oracle image use path B instead.

```bash
docker pull container-registry.oracle.com/database/free:latest
make build
```

### 3. Check and Start

```bash
make check SERVICE=seclab       # pre-flight: runtime, memory, image, .env, ports
make up-seclab                  # runs the check again, then starts the service
make logs-seclab                # follow the setup, Ctrl-C to leave
```

The setup creates PDB `SECPDB1`, applies all scenarios and ends with the
verification. The log shows `Summary: 11 PRESENT, 0 ABSENT, ...` followed by
`DATABASE IS READY TO USE!`. Measured: 2 min on Docker Desktop, 130 s on
Colima.

What the setup runs (`config/seclab/setup/`):

| Script | Does |
| --- | --- |
| `01_drop_pdb_freepdb1.sql` | drops the default `FREEPDB1` |
| `10_create_pdb_secpdb1.sql` | creates `SECPDB1` |
| `20_seclab_apply_secpdb1.sh` | `seclab_apply.sh -p SECPDB1` - all scenarios plus verification |

### 4. Verify

```bash
make verify-seclab              # exit 0 = all present, 1 = something absent
```

### 5. Connect

| Client | Connection |
| --- | --- |
| SQL*Plus in the container | `make sql-seclab`, then `ALTER SESSION SET CONTAINER=SECPDB1;` |
| SQL*Plus / SQLcl on the host | `sql app_owner@//localhost:1534/SECPDB1` |
| JDBC | `jdbc:oracle:thin:@//localhost:1534/SECPDB1` |
| Python (`python-oracledb`, thin) | see below |

```python
import os
import oracledb

conn = oracledb.connect(user="app_owner", password=os.environ["SECLAB_USER_PWD"],
                        dsn="localhost:1534/SECPDB1")
print(conn.version)
```

The accounts and their purpose are listed in [seclab.md](seclab.md#accounts-and-objects).
`SYS`/`SYSTEM` use `ORACLE_PWD`. The host clients above were not part of the
measured runs; the in-container logins over the listener were.

### 6. Stop, Restart, Reset

```bash
make down-seclab                # stop, data stays in data/seclab/
make up-seclab                  # second start: startup scripts only, about 10 s
make reset-seclab               # DESTRUCTIVE: deletes data/seclab/, asks first
make up-seclab                  # fresh setup from scratch
```

Settings that a remediation changed (sqlnet.ora, SPFILE) survive a restart:
the scenarios are applied only by the setup, never by the startup scripts.
Only a reset brings the baseline back.

## Path B - Apply seclab to Any Container

For a container started directly from the Oracle image, without this
repository's compose file or build:

```bash
docker run -d --name free26ai -p 127.0.0.1:1521:1521 \
  -e ORACLE_PWD=<password> container-registry.oracle.com/database/free:latest

export SECLAB_USER_PWD=<lab password> SECLAB_SCOTT_PWD=tiger
scripts/apply_usecase.sh seclab free26ai
# or: make apply USECASE=seclab CONTAINER=free26ai
```

What happens:

1. Checks that the container runs an Oracle database and **refuses** if it
   publishes ports beyond `127.0.0.1` (override: `--allow-public-ports`).
2. Waits until the database is open, picks the open PDB (or `-p <PDB>`).
3. Copies `config/common/scripts` to `/opt/oracle/common/scripts` in the
   container (a previous copy is replaced and reported).
4. Runs `seclab_apply.sh`: no PDB is created or dropped; the instance is
   restarted once for S10 (`--no-restart` skips S10 and says so).
5. Prints the verification.

Measured on the plain image (Docker Desktop and Colima): 18 s from
`docker run` to `11 PRESENT`. Rerunning is safe: accounts are recreated,
existing demo schemas and audit policies are kept and reported.

Verify later:

```bash
docker exec free26ai /opt/oracle/common/scripts/seclab_verify.sh -p FREEPDB1
```

## Remediation Test Loop

The point of the lab: change something, assess again, see the finding go.
Class 1 scenarios have a fix and a rollback:

```bash
R=/opt/oracle/common/scripts/run_sql_script.sh
docker compose exec seclab $R -p SECPDB1 seclab_s01_public_grants.sql FIX
make verify-seclab              # S01 ABSENT, exit 1 - the fix worked
make dbsat-seclab               # optional: DBSAT finding PRIV.OBJPUBLIC should be gone
docker compose exec seclab $R -p SECPDB1 seclab_s01_public_grants.sql INSECURE
make verify-seclab              # S01 PRESENT again, exit 0
```

Measured on 23.26.3: exactly this sequence. The same pattern works for S06
(`seclab_s06_unused_accounts.sql FIX|INSECURE`), S11
(`seclab_s11_default_password.sql FIX`) and S10
(`set_static_param.sql sql92_security TRUE`, restarts the instance).

Class 2 scenarios have a read-only pre-check:

```bash
docker compose exec seclab $R -p SECPDB1 precheck_revoke_public.sql UTL_FILE
docker compose exec seclab $R -p SECPDB1 precheck_logon_version.sql 12a
docker compose exec seclab $R -p SECPDB1 precheck_profile_hardening.sql SECLAB_UNLIMITED
```

On path B replace `docker compose exec seclab` with `docker exec <container>`
and `SECPDB1` with the PDB name.

## DBSAT

```bash
make dbsat-seclab # service
make dbsat CONTAINER=free26ai # any container
make dbsat-discover-seclab # sensitive data discovery, service
make dbsat-discover CONTAINER=free26ai # sensitive data discovery, any container
```

DBSAT is not shipped. Without the zip these commands stop with exit 4 and
explain where to get it. They copy a JRE 21 from `eclipse-temurin:21-jre`
into the container first, because DBSAT 4.x needs Java 17+ for report and
discover. Details: [dbsat-runbook.md](dbsat-runbook.md).

## Troubleshooting

<!-- markdownlint-disable MD013 MD060 -->
| Symptom | Cause | Fix |
| --- | --- | --- |
| `FAIL SECLAB_USER_PWD not set` | `.env` from an older version | add the `SECLAB_*` lines from `.env.example` |
| `ERROR: SECLAB_USER_PWD is not set or empty` in the setup log | container created without the variables | add them to `.env`, then `make reset-seclab` and `make up-seclab` |
| `DBT-60127 ... TNS_ADMIN` and restart loop | repository outside the VM mounts (Colima/Podman), or plain image used for the service | clone below `$HOME`; `make build`; or use path B |
| `Summary: ... ABSENT` after a fix | expected - that is the remediation loop | `INSECURE` mode or `make reset-seclab` restores the baseline |
| `ERROR: ... publishes ports beyond localhost` | path B on a container started with `-p 1521:1521` | recreate with `-p 127.0.0.1:1521:1521` |
| `seclab apply stopped in step N/11` | a step failed, the output above names the statement | fix the cause, rerun - all steps are rerunnable |
| `make verify-seclab` exit 2 | the check itself could not run (container down, PDB closed) | `make up-seclab`, `make logs-seclab` |
<!-- markdownlint-restore -->

Logs of every SQL step: `data/seclab/logs/` on the host
(`/opt/oracle/scripts/logs` in the container).
