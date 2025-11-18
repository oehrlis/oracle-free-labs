# Data for odbdemo

This folder contains the persistent database files and configuration for the
OraDBA demo repository created from `PDB$SEED`.

## Structure

- **FREE/** - Oracle database files
- **dbconfig/** - service configuration (for example `tnsnames.ora`, wallets)

## Notes

- This folder is mounted into the container `odbdemo` at startup.
- The contents are ignored in Git to avoid committing database files.
