# Data for labdb

This folder contains the persistent database files and configuration for the
empty lab database with full setup and startup scripts.

## Structure

- **FREE/** - Oracle database files
- **dbconfig/** - service configuration (for example `tnsnames.ora`, wallets)

## Notes

- This folder is mounted into the container `labdb` at startup.
- The contents are ignored in Git to avoid committing database files.
