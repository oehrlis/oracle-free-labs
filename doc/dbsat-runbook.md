# DBSAT Runbook - Assess Any Lab Container

"I want to run a DBSAT assessment against container xyz." This runbook covers
exactly that, for the lab services of this repository and for any other
running Oracle Database Free container.

## Status

The automation is in place, but a real DBSAT run was **not verified** in this
repository: DBSAT is not shipped and no DBSAT archive was available when the
scripts were written. Verified are the prerequisite checks and the path
without a DBSAT archive (clear message, exit code 4). Treat the first real
run as a test and report deviations.

## What You Need

1. **DBSAT archive** - download it with an Oracle account from
   <https://www.oracle.com/database/technologies/security/dbsat.html> and copy
   the `dbsat*.zip` unchanged to `config/common/data/dbsat/` (ignored by Git).
2. **A password for the collector account** - `DBSAT_PWD`, or `SECLAB_DBSAT_PWD`
   from `.env` for seclab. The account is created by the script.
3. **A running container** with an open PDB.

Prerequisites inside the container, checked by the script (measured on the
Oracle Free 23.26.3 image):

| Component | Needed for | In the image |
| --- | --- | --- |
| `python3` | `dbsat report` | yes, `/usr/bin/python3` |
| `unzip` | extracting DBSAT | yes |
| `zip` | encrypted collector output | **no** - the script uses `-n` (unencrypted) |
| Java | `dbsat discover` only | `$ORACLE_HOME/jdk/bin/java` |

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
3. `run_dbsat.sh` checks the prerequisites, extracts DBSAT to `/tmp/dbsat`
   (previous extraction removed and reported) and creates the collector account
   `DBSAT_USER` with `create_dbsat_user.sql` - not SYS.
4. `dbsat collect -n` against `//localhost:1521/<PDB>`, then `dbsat report -n`.
5. Reports land in `/opt/oracle/oradata/dbsat/` in the container; for any
   container they are copied to `data/dbsat/<container>/` on the host, for
   seclab they are in `data/seclab/dbsat/` directly.

Files: `dbsat_<pdb>.json` (collection), `dbsat_<pdb>_report.html`, `.txt`,
`.xlsx`, `.json`.

## Collector Account

`create_dbsat_user.sql` follows the privilege list of the DBSAT User Guide
(collector prerequisites): `CREATE SESSION`, `SELECT_CATALOG_ROLE`,
`AUDIT_VIEWER`, `CAPTURE_ADMIN` and `SELECT` on `SYS.REGISTRY$HISTORY`,
`SYS.DBA_USERS_WITH_DEFPWD`, `AUDSYS.AUD$UNIFIED`,
`SYS.DBA_AUDIT_MGMT_CONFIG_PARAMS`. The list differs between DBSAT versions -
compare it with the guide of your version. A grant that fails is printed as
`WARN`, never skipped silently. The account is dropped and recreated on every
run.

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
<!-- markdownlint-restore -->
