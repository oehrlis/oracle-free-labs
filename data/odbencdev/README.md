# Data for odbencdev

This folder contains the persistent database files and configuration for the
TDE restore verification test - Dev/target DB (own keystore, own master key).

## Structure

- **FREE/** - Oracle database files
- **dbconfig/** - service configuration (for example `tnsnames.ora`, wallets)

## Notes

- This folder is mounted into the container `odbencdev` at startup.
- The contents are ignored in Git to avoid committing database files.
- This service acts as the non-production target database in the TDE restore
  verification test. It holds its own independent keystore and master key,
  mirroring the customer scenario where Prod and Dev use separate keystores.
