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
- `dbsat discover` (sensitive data discovery, 2026-10-19): seclab service
  (SECPDB1) and plain Oracle image through `apply_usecase.sh dbsat-discover`,
  prompts answered through a pseudo terminal - see [Discover](#discover).

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
   A symlinked zip is followed: if it is not readable through the bind mount
   (a host symlink dangles there), a WARN says so and the zip is copied with
   `docker cp -L` to `/tmp/dbsat-zip` instead. This applies to `make dbsat
   CONTAINER=...`; `make dbsat-seclab` runs `run_dbsat.sh` directly and needs a
   real file - for a symlinked zip use `make dbsat CONTAINER=seclab`.
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
| 0 | all selected steps done (default: collection and report written) |
| 1 | error (password missing, account, collect, report or discover failed, invalid option) |
| 4 | no `dbsat*.zip` - download it |
| 5 | no Java 17+ for report or discover; a selected collection is written |

`run_dbsat.sh -m` selects the steps: `collect`, `report`, `discover` or `all`,
comma separated. Default `collect,report` - `make dbsat` and
`make dbsat-seclab` behave as before. `-m report` alone reuses an existing
`dbsat_<pdb>.json`.

## Collector Account

`create_dbsat_user.sql` follows the privilege list of the DBSAT User Guide
(collector prerequisites): `CREATE SESSION`, `SELECT_CATALOG_ROLE`,
`AUDIT_VIEWER`, `CAPTURE_ADMIN` and `SELECT` on `SYS.REGISTRY$HISTORY`,
`SYS.DBA_USERS_WITH_DEFPWD`, `AUDSYS.AUD$UNIFIED`,
`SYS.DBA_AUDIT_MGMT_CONFIG_PARAMS`. The list differs between DBSAT versions -
compare it with the guide of your version. A grant that fails is printed as
`WARN`, never skipped silently. The account is dropped and recreated on every
run (`--existing-user` keeps it). SYS, SYSTEM, PDBADMIN and every account with
`ORACLE_MAINTAINED = 'Y'` are refused (`run_dbsat.sh -u` and the SQL script),
nothing is dropped.

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

## Discover

`dbsat discover` searches column names and column comments for sensitive data
(pattern files `sensitive*.ini` of the archive) and rates it by category. It
reads only the catalog: the `DBSAT_USER` account is enough, no data is read.

### Run Discover

```bash
# seclab service, results in data/seclab/dbsat/
make dbsat-discover-seclab DBSAT_ARGS="-r 0 -S SCOTT,TVD_HR"   # DBSAT_ARGS optional

# any container - also the plain Oracle image
export DBSAT_PWD=<lab password>
make dbsat-discover CONTAINER=free26ai PDB=FREEPDB1 DBSAT_ARGS="-g -P sensitive_de.ini"
# same as: scripts/apply_usecase.sh [-p PDB] dbsat-discover <container> [-- run_dbsat.sh options]

# inside a container
run_dbsat.sh -s SECPDB1 -e SECLAB_DBSAT_PWD -m discover [-g] [-S ...] [-r N]
```

Prerequisites are the same as for the report: the archive, a password and
Java 17+ (the make targets and `apply_usecase.sh` copy the JRE 21 first).
Without Java 17+ `-m discover` stops with exit 5 before any change; with
`-m collect,discover` or `all` the collection (and the account) is done first,
then exit 5.

<!-- markdownlint-disable MD013 MD060 -->
| Option | Config key / DBSAT flag | Default | Meaning |
| --- | --- | --- | --- |
| `-P LIST` | `SENSITIVE_PATTERN_FILES` | `sensitive.ini` | pattern files, comma separated: names in `Discover/conf` of the archive (`sensitive_de.ini`, `_en`, `_es`, `_fr`, `_it`, `_nl`, `_pt`, `_el`) or absolute paths; each file name only once |
| `-S LIST` | `SCHEMA_SCOPE` | `ALL` | schemas to scan; DBSAT stops on a schema that does not exist |
| `-r N` | `MINROWS` | `1` | minimum `NUM_ROWS` of a table; `0` includes empty tables |
| `-O` | `dbsat discover -o` | off | also Oracle-maintained and sample schemas (not listed in the usage text of DBSAT 4.3, measured) |
| `-x FILE` | `EXCLUSION_LIST_FILE` | none | one `SCHEMA`, `SCHEMA.TABLE` or `SCHEMA.TABLE.COLUMN` per line |
| `-g` | - | off | gather missing optimizer statistics in scope first (changes the database) |
| `--existing-user` | - | off | use the account as it is instead of dropping and recreating it |
| `DISC_TIMEOUT` | environment | `1800` | seconds for the whole discover run; `apply_usecase.sh` passes it on |
<!-- markdownlint-restore -->

What `run_dbsat.sh -m discover` does: it checks (with `-g` gathers) the
optimizer statistics in scope, generates the config from
`Discover/conf/sample_dbsat.config` with the pattern files and the exclusion
list next to it (DBSAT resolves them relative to the config), runs `dbsat
discover -n` under a pseudo terminal and prints a summary from the JSON.

The sample config does not rate `IT Info - User Data` of the language pattern
files (DBSAT: `... is not recognized`); the script adds it as `High Risk`.

Files in the output directory (mode 600, set by the DBSAT launcher umask 077):
`dbsat_<pdb>_discover.html` (report with summary and risk levels), `.csv`,
`.json` (one object per line, empty without findings) and
`dbsat_<pdb>_discoverer.log`. Previous files of the same name are removed and
reported.

### Why a Pseudo Terminal

DBSAT discover reads username and password through `System.console()`: without
a terminal (`docker exec` without `-t`, `make`, a pipe) it prints only
`Error: Unexpected error occurred while running DBSAT Discover.`. `run_dbsat.sh`
runs it under `script` (util-linux, in the Oracle image) and sends each answer
after its prompt (120 s per prompt, `DISC_TIMEOUT` for the whole run); a prompt
after the password means rejected credentials and stops the run with exit 1.
A password-less SEPS wallet (`WALLET_LOCATION` in the config) is not
implemented.

### Statistics: Tables DBSAT Does Not See

Discover filters tables by `MINROWS` against `DBA_TABLES.NUM_ROWS`. A table
**without optimizer statistics** (`NUM_ROWS` NULL) is skipped without any
message - also with `-r 0` (measured with SCOTT.BONUS). An empty table with
statistics (`NUM_ROWS = 0`) appears only with `-r 0`.

Before every discover `gather_missing_stats.sql` names each such table
(`WARN: no optimizer statistics: SCOTT.BONUS`) and each schema in `-S` that
does not exist. `-g` gathers them as SYSDBA with `GATHER EMPTY` (only objects
without statistics; Oracle-maintained schemas are named, not gathered). The
seclab setup gathers the missing statistics of the custom schemas itself
(`seclab_apply.sh` step 10 of 11); `make dbsat-discover-seclab` passes `-g`
as a safety net. Without that step discover missed SCOTT and APP_OWNER
completely on a fresh plain image.

### Results on seclab (measured)

DBSAT 4.3 against SECPDB1, default options, after `-g` (2026-10-19, same
result 2026-10-20): 3 schemas (APP_OWNER, SCOTT, TVD_HR), 35 sensitive columns
in 9 tables plus 12 columns in 1 view (`TVD_HR.EMP_DETAILS_VIEW`), risk levels
High and Low. `APP_OWNER.CUSTOMERS` is found with `EMAIL`, `FULL_NAME` and
`IBAN`. SCOTT.BONUS is empty and appears only with `-r 0`.

### False Positives - a Teaching Point

Observed with DBSAT 4.3 on 2026-10-19. Discover matches regular expressions
against column names **and column comments** (`COL_NAME_PATTERN`,
`COL_COMMENT_PATTERN` in `sensitive.ini`). The TVD_HR schema shows both kinds
of false positive:

<!-- markdownlint-disable MD013 MD060 -->
| Column | Matched as | Why (pattern in `sensitive.ini` of DBSAT 4.3) |
| --- | --- | --- |
| `TVD_HR.DEPARTMENTS.MANAGER_ID`, `TVD_HR.EMPLOYEES.DEPARTMENT_ID` | `SPAIN NIE NUMBER` (National IDs, High Risk) | comment pattern of "Spain NIE number" contains the word `FOREIGN` (Spanish *extranjero*); the comments say "Foreign key to ..." |
| `TVD_HR.COUNTRIES.REGION_ID`, `TVD_HR.DEPARTMENTS.LOCATION_ID`, `TVD_HR.LOCATIONS.LOCATION_ID`, `TVD_HR.REGIONS.REGION_ID` | `CITY` (Address, High Risk) | name pattern of "City" matches the words `LOCATION` and `REGION` - key columns, no address data |
<!-- markdownlint-restore -->

A discover result is a candidate list, not an inventory: review it, then
exclude confirmed false positives with `-x` (`SCHEMA.TABLE.COLUMN` per line) or
fix misleading comments. Conversely discover does not look at the data itself:
a column `NOTES` holding IBANs stays invisible.

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
| discover: `Error: Unexpected error occurred while running DBSAT Discover.`, empty log | discover run without a terminal (by hand, outside `run_dbsat.sh`) | use `run_dbsat.sh -m discover` (pseudo terminal) or `docker exec -it` |
| discover: `ORA-01017: wrong username or password` or `ORA-01017-like: DBSAT prompted again after the password` | `--existing-user` with another password, or the wrong `-e VAR` | drop `--existing-user` (account is recreated) or fix the variable |
| discover: `no 'username' prompt ... within 120s` | DBSAT did not start or prompts differently (other release) | read the output above; check `Discover/conf` and the launcher of the release |
| discover: `did not finish within DISC_TIMEOUT=...s` | very large catalog or a hanging connection | rerun with a larger `DISC_TIMEOUT` (seconds) or a narrower `-S` |
| discover: `SENSITIVE_CATEGORY ... is not recognized` | a custom pattern file uses a category the sample config does not rate | add the category with a risk level to the pattern setup of the release; only `IT Info - User Data` is added by the script |
| discover: `-S ... names a schema that does not exist` (`Invalid schemas` from DBSAT) | typo or missing schema in `-S` | fix `-S`; the statistics check names the schema as `WARN` before |
| `-u SYSTEM: refused` / `ORA-20011 ... refused to drop and recreate` | SYS, SYSTEM, PDBADMIN or an Oracle-maintained account given as DBSAT account | use the default `DBSAT_USER` or another dedicated account |
| discover: table missing in the result | no optimizer statistics or fewer rows than `MINROWS` | read the statistics `WARN` lines, rerun with `-g` and/or `-r 0` |
| discover: many National ID / Address hits in an HR schema | patterns match column comments | see [False Positives](#false-positives---a-teaching-point), exclude with `-x` |
<!-- markdownlint-restore -->
