# odbencdev - TDE Restore Verification Test (Dev/Target DB)

This folder contains the configuration for the `odbencdev` service - the
non-production restore-target database in the TDE restore verification test.
It provides one-time setup scripts and recurring startup scripts that are
mounted into the container when the service is started.

## Purpose

`odbencdev` simulates the non-production target database to answer the question:
does `RESTORE DATABASE AS ENCRYPTED USING KEY` re-encrypt data blocks (new
TEK material) or only re-wrap the existing TEK in the datafile header?

The service is intentionally minimal: it holds no user data PDB and no demo
schemas. Its own independent keystore and master encryption key mirror the
customer scenario where Prod and Dev use completely separate keystores.

PDBs and data are restored from `odbencprod` backups during the verification
test phases (Phase 2 onwards).

## Bind Mounts

The following paths are mounted into the container:

- **./config/common/scripts -> /opt/oracle/common/scripts**
  Shared SQL and shell helper scripts available to all services.

- **./config/odbencdev/setup -> /opt/oracle/scripts/setup**
  One-time setup scripts. Executed automatically on the first container start.

- **./config/odbencdev/startup -> /opt/oracle/scripts/startup**
  Recurring startup scripts. Executed on every container start after the
  database has been opened.

- **./data/xchange -> /opt/oracle/xchange**
  Shared read-write exchange directory (RMAN backup sets, wallet exports from
  `odbencprod`). Also mounted in `odbencprod` at the same container path.

## Notes

- Setup scripts are numbered to enforce execution order.
- No PDB is created during setup; PDBs arrive via RMAN restore in later phases.
- The independent keystore (`data/odbencdev/dbconfig/FREE/wallet`) is separate
  from `data/odbencprod/dbconfig/FREE/wallet` even though both containers use
  the same internal path `/opt/oracle/dbconfig/FREE/wallet`.
