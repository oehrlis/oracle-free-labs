# odbencprod - TDE Restore Verification Test (Prod DB)

This folder contains the configuration for the `odbencprod` service - the
production-side database in the TDE restore verification test. It provides
one-time setup scripts and recurring startup scripts that are mounted into the
container when the service is started.

## Purpose

`odbencprod` simulates a production Oracle database to answer the question:
does `RESTORE DATABASE AS ENCRYPTED USING KEY` re-encrypt data blocks (new
TEK material) or only re-wrap the existing TEK in the datafile header?

The service provides:

- ARCHIVELOG mode from the image default `ENABLE_ARCHIVELOG=true`
- PDB `ODBENCPROD` with SCOTT and TVD_HR demo schemas
- TDE with WALLET_ROOT / software keystore
- Online-encrypted `USERS` tablespace as ciphertext baseline

## Bind Mounts

The following paths are mounted into the container:

- **./config/common/scripts -> /opt/oracle/common/scripts**
  Shared SQL and shell helper scripts available to all services.

- **./config/odbencprod/setup -> /opt/oracle/scripts/setup**
  One-time setup scripts. Executed automatically on the first container start.

- **./config/odbencprod/startup -> /opt/oracle/scripts/startup**
  Recurring startup scripts. Executed on every container start after the
  database has been opened.

- **./data/xchange -> /opt/oracle/xchange**
  Shared read-write exchange directory (RMAN backup sets, wallet exports).
  Also mounted in `odbencdev` at the same container path.

## Notes

- Setup scripts are numbered to enforce execution order.
- Startup scripts handle recurring tasks such as wallet redirect and health checks.
- Shared logic for multiple services lives in `config/common/scripts`.
- The `data/xchange` mount is write-accessible from both `odbencprod` and
  `odbencdev` containers.
