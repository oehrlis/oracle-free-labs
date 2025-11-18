# Data for odbseed

This folder contains the persistent database files and configuration for the
OraDBA repository created from a PDB archive.

## Structure

- **FREE/** - Oracle database files
- **dbconfig/** - service configuration (for example `tnsnames.ora`, wallets)

## Notes

- This folder is mounted into the container `odbseed` at startup.
- The contents are ignored in Git to avoid committing database files.
