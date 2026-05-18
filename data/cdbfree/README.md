# Data for cdbfree

This folder contains the persistent database files and configuration for the
plain Oracle 26ai Free instance with common scripts only.

## Structure

- **FREE/** - Oracle database files
- **dbconfig/** - service configuration (for example `tnsnames.ora`, wallets)

## Notes

- This folder is mounted into the container `cdbfree` at startup.
- The contents are ignored in Git to avoid committing database files.
