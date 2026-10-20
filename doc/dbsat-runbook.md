# DBSAT Runbook - Assess Any Lab Container

"I want to run a DBSAT assessment against container xyz." This runbook covers
exactly that, for the lab services of this repository and for any other
running Oracle Database Free container.

## Status

Verified on 2026-10-19 with DBSAT 4.3 (July 2026) on Oracle AI Database 26ai
Free 23.26.3 (arm64, Docker Desktop):

- seclab service: `dbsat collect` in the container as `DBSAT_USER` against
  SECPDB1, `dbsat report` in the same container with a JRE 21 copied in from
  `eclipse-temurin:21-jre`. All five files written.
- Plain Oracle image (`container-registry.oracle.com/database/free:latest`,
  no compose, no ports): `scripts/apply_usecase.sh dbsat <container>` copies
  scripts, zip and JRE, reports land in `data/dbsat/<container>/`.
- Without Java 17+ the collection runs and the script stops with exit 5 and
  the command that provides Java. Without the archive: exit 4.

Not verified: Podman, amd64 hosts, Linux Docker host, DBSAT releases other than 4.3.

## What You Need

1. **DBSAT archive** - download it with an Oracle account from
   <https://www.oracle.com/database/technologies/security/dbsat.html> and copy
   the `dbsat*.zip` unchanged to `config/common/data/dbsat/` (ignored by Git).
2. **A password for the collector account** - `DBSAT_PWD`, or `SECLAB_DBSAT_PWD`
   from `.env` for seclab. The account is created by the script.
3. **A running container** with an open PDB.
4. **The JRE image** `eclipse-temurin:21-jre` locally (`docker pull
   eclipse-temurin:21-jre`, pulled automatically if missing). Override with
   `ASSESS_JRE_IMAGE` (environment, `.env` or `make ... ASSESS_JRE_IMAGE=...`);
   any image with a Java 17+ runtime in `/opt/java/openjdk` for the host
   architecture works. `make check` reports whether it is present.

Prerequisites inside the container, checked by the script (measured on the
Oracle Free 23.26.3 image):

<!-- markdownlint-disable MD013 MD060 -->
| Component | Needed for | In the image |
| --- | --- | --- |
| Java 17+ | `dbsat report` and `dbsat discover` (DBSAT 4.x) | **no** - `$ORACLE_HOME/jdk` is JDK 11, the DBSAT launcher rejects it. A JRE 21 is copied in (see below) |
| `unzip` | extracting DBSAT | yes |
| `zip` | encrypted collector output | **no** - the script uses `-n` (unencrypted) |
| `tar` | unpacking the copied JRE as `oracle` | yes |
| `python3` | `dbsat report` of releases before 4.x only | yes, Python 3.6.8 |
<!-- markdownlint-restore -->

### Java 17+ for the Report

`scripts/provide_jre.sh <container> [dir]` copies `/opt/java/openjdk` from
the JRE image into the container: no helper container keeps running, the
temporary one is removed (also on an error or Ctrl-C). Target:

- lab services (bind-mounted `/opt/oracle/oradata`):
  `/opt/oracle/oradata/tools/jre21`, persistent as `data/<service>/tools/jre21`
  on the host (162 MB measured on arm64), reused by later runs
- any other container: `/tmp/jre21`, gone with the container

An existing JRE with Java 17+ is reused and reported; a broken or older one is
replaced; `-f` forces a fresh copy, `-n` only shows the steps. An explicit
`dir` must be absolute, without whitespace, quotes or `..`, and its last
component must start with `jre` - the script removes it as root before the
copy and refuses anything else with exit 1. The files are
unpacked as `oracle` - a `chown` does not stick on Docker Desktop bind mounts.
Exit codes: 0 ready, 1 usage or container, 2 image not available (pull failed
or wrong architecture), 3 copied JRE does not run Java 17+.

`run_dbsat.sh` sets `JAVA_HOME` to `-j DIR`, else to the first of `$JAVA_HOME`,
`/opt/oracle/oradata/tools/jre21`, `/tmp/jre21` that runs Java 17+, and reports
every candidate it skips. `make dbsat-seclab` and `apply_usecase.sh dbsat` pass
no `-j`: the default target of `provide_jre.sh` is one of these candidates.

## Run It

```bash
# seclab service (archive is bind-mounted, reports in data/seclab/dbsat/)
make dbsat-seclab

# any container - also the plain Oracle image
export DBSAT_PWD=<lab password>
make dbsat CONTAINER=free26ai               # PDB detected automatically
make dbsat CONTAINER=labdb PDB=LABPDB1      # explicit PDB
# same as: scripts/apply_usecase.sh [-p PDB] dbsat <container>
```

What happens:

1. The newest `dbsat*.zip` in `config/common/data/dbsat/` is used. Without one:
   exit 4 with the download link.
2. `config/common/scripts` and the zip are copied into the container unless they
   are bind-mounted (lab services). A previous copy is replaced and reported.
   A symlinked zip is followed.
3. A JRE 21 is provided with `provide_jre.sh` (see above). If that fails, the
   run continues with a WARN naming the exit code: the collection is still
   useful, the report step stops with exit 5. `make dbsat-seclab` stops right
   away on exit 1 (container problem).
4. `run_dbsat.sh` checks the prerequisites, extracts DBSAT to `/tmp/dbsat`
   (previous extraction removed and reported; DBSAT 4.x unpacks into a
   `dbsat/` subdirectory, older releases flat) and creates the collector
   account `DBSAT_USER` with `create_dbsat_user.sql` - not SYS.
5. `dbsat collect -n` against `//localhost:1521/<PDB>`, then `dbsat report -n`
   with `JAVA_HOME` on the JRE 21.
6. Reports land in `/opt/oracle/oradata/dbsat/` in the container; for any
   container they are copied to `data/dbsat/<container>/` on the host (with
   exit 5 the collection only), for seclab they are in `data/seclab/dbsat/`
   directly.

Files: `dbsat_<pdb>.json` (collection), `dbsat_<pdb>_report.html`, `.txt`,
`.xlsx`, `.json`.

Exit codes of `run_dbsat.sh` (passed through by `apply_usecase.sh`):

| Code | Meaning |
| --- | --- |
| 0 | collection and report written |
| 1 | error (password missing, account, collect or report failed) |
| 4 | no `dbsat*.zip` - download it |
| 5 | collection written, no Java 17+ for the report |

## Collector Account

`create_dbsat_user.sql` follows the privilege list of the DBSAT User Guide
(collector prerequisites): `CREATE SESSION`, `SELECT_CATALOG_ROLE`,
`AUDIT_VIEWER`, `CAPTURE_ADMIN` and `SELECT` on `SYS.REGISTRY$HISTORY`,
`SYS.DBA_USERS_WITH_DEFPWD`, `AUDSYS.AUD$UNIFIED`,
`SYS.DBA_AUDIT_MGMT_CONFIG_PARAMS`. The list differs between DBSAT versions -
compare it with the guide of your version. A grant that fails is printed as
`WARN`, never skipped silently. The account is dropped and recreated on every
run.

`dbsat collect` records its process environment in `dbsat_<pdb>.json`. The
container environment holds `ORACLE_PWD` and, for seclab, the `SECLAB_*_PWD`
values. `run_dbsat.sh` therefore starts DBSAT without any variable whose name
contains `PWD`, `PASSW`, `SECRET` or `TOKEN` and lists the removed names; the
collector password goes in on stdin. Collections written before this change
(2026-10-20) contain these values in clear text - delete them or treat them as
secrets.

## Compare Before and After a Change

```bash
make dbsat-seclab
cp data/seclab/dbsat/dbsat_secpdb1_report.json /tmp/before.json
docker compose exec seclab /opt/oracle/common/scripts/run_sql_script.sh \
  -p SECPDB1 seclab_s01_public_grants.sql FIX
make dbsat-seclab
# compare /tmp/before.json with data/seclab/dbsat/dbsat_secpdb1_report.json
```

The expected DBSAT rule per seclab scenario is listed in
[seclab.md](seclab.md#overview).

## Troubleshooting

<!-- markdownlint-disable MD013 MD060 -->
| Symptom | Cause | Fix |
| --- | --- | --- |
| exit 4, `no dbsat*.zip` | archive missing | download, copy to `config/common/data/dbsat/` |
| `DBSAT_PWD is not set` | no password for the collector account | export `DBSAT_PWD` or set `SECLAB_DBSAT_PWD` in `.env` |
| `several open PDBs ... pass -p PDB` | more than one user PDB is open | `make dbsat CONTAINER=x PDB=<name>` |
| `WARN: GRANT ... failed` | object or role does not exist in this release | check the DBSAT guide; the collector may report the area as not assessed |
| `dbsat collect failed` | wrong service name, password, or a DBSAT version that prompts differently | run `run_dbsat.sh` in the container by hand and read the prompt |
| exit 5, `dbsat report needs Java 17+` | no JRE 21 in the container, only the image JDK 11 | `make dbsat-seclab` / `make dbsat CONTAINER=<name>`, or `scripts/provide_jre.sh <container>` and rerun |
| `INFO: Java 11 in ... is older than 17 - skipped` | `JAVA_HOME` or `-j` points to the image JDK | let the script pick the copied JRE, or pass `-j /opt/oracle/oradata/tools/jre21` |
| `provide_jre.sh` exit 2, `cannot pull` | no registry access | `docker pull eclipse-temurin:21-jre` elsewhere and `docker save` / `docker load`, or set `ASSESS_JRE_IMAGE` to a local JRE image |
| `provide_jre.sh` exit 2, `... is amd64, container ... is arm64` | JRE image of the wrong architecture | `docker pull --platform linux/<arch> eclipse-temurin:21-jre` |
| `SP2-0606: Cannot create SPOOL file` (`run_dbsat.sh` v1.0.0) | plain image has no `/opt/oracle/scripts/logs` | fixed: `run_dbsat.sh` creates `SQL_LOG_DIR` |
| `no dbsat launcher found` | archive layout not recognised | check `unzip -l dbsat*.zip` for a file named `dbsat` at most one level deep |
<!-- markdownlint-restore -->
