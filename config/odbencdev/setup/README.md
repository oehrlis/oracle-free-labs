# odbencdev Setup Scripts

This folder contains one-time setup scripts for the `odbencdev` service - the
non-production restore-target database in the TDE restore verification test.
Scripts are executed automatically in alphabetical order on the first container
start.

## Purpose

`odbencdev` is intentionally minimal. It contains no user data PDB and no demo
schemas. Its sole purpose is to act as the independent restore target when
testing `RESTORE DATABASE AS ENCRYPTED USING KEY` (and variants) from the
`odbencprod` backup.

The service provides:

- ARCHIVELOG mode from the image default `ENABLE_ARCHIVELOG=true`
- WALLET_ROOT configured to an independent keystore directory
- A software keystore with its own master encryption key

The keystore of `odbencdev` is completely independent from `odbencprod`. Both
containers use the same container-internal path (`/opt/oracle/dbconfig/FREE/wallet`)
but the path maps to different host directories, mirroring the customer scenario
where Prod and Dev use separate keystores.

## Scripts in Use

- **00_common_db_config.sql**
  Basic instance configuration. Sets parameters that require a restart.

- **10_config_tde_odbencdev.sql**
  Configures TDE: sets WALLET_ROOT, creates software keystore, creates an
  independent master encryption key. Restarts the database twice.

## Notes

- No PDB is created here. User data PDBs will be restored from `odbencprod`
  backups during the verification test phases.
- No demo schemas, no audit policies, no Oracle directories.
- The `data/xchange` bind mount (`/opt/oracle/xchange`) provides access to
  RMAN backup sets and wallet exports from `odbencprod`.

## Why FREEPDB1 is kept

The default pluggable database is deliberately **not** dropped here, unlike in
the other services. The container entrypoint gates its readiness on
`checkPDBOpen`, which runs `SELECT DISTINCT open_mode FROM v$pdbs` and requires
at least one PDB in `READ WRITE`. A CDB with no user PDB is a case the health
check does not model, so the container would print
`DATABASE SETUP WAS NOT SUCCESSFUL` although the database is fully functional.

Keeping `FREEPDB1` costs nothing for this service: as a restore target it
receives the source control file and the source datafiles, after which its own
pluggable database is irrelevant.
