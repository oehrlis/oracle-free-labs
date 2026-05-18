# Data for odbenc

This folder contains the persistent database files and configuration for the
OraDBA demo database with Transparent Data Encryption (TDE) via SQL scripts.

## Structure

- **FREE/** - Oracle database files
- **dbconfig/** - service configuration (for example `tnsnames.ora`, wallets)

## Notes

- This folder is mounted into the container `odbenc` at startup.
- The contents are ignored in Git to avoid committing database files.
