# Data for odbencprod

This folder contains the persistent database files and configuration for the
TDE restore verification test - Prod/source DB (TDE, encrypted tablespace).

## Structure

- **FREE/** - Oracle database files
- **dbconfig/** - service configuration (for example `tnsnames.ora`, wallets)

## Notes

- This folder is mounted into the container `odbencprod` at startup.
- The contents are ignored in Git to avoid committing database files.
- This service acts as the production source database in the TDE restore
  verification test. It holds the encrypted `USERS` tablespace whose ciphertext
  is the baseline every clone variant is compared against.
