# Data for odbrepo

This folder contains the persistent database files and configuration for the
OraDBA repository created using SQL scripts.

## Structure

- **FREE/** - Oracle database files
- **dbconfig/** - service configuration (for example `tnsnames.ora`, wallets)

## Notes

- This folder is mounted into the container `odbrepo` at startup.
- The contents are ignored in Git to avoid committing database files.
