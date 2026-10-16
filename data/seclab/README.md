# Data for seclab

This folder contains the persistent database files and configuration for the
**intentionally insecure** security baseline lab (`seclab`). See
[doc/seclab.md](../../doc/seclab.md).

## Structure

- **FREE/** - Oracle database files
- **dbconfig/** - service configuration (`sqlnet.ora` with the S03/S09 settings,
  `tnsnames.ora`, wallet)
- **logs/** - setup, startup and verification logs
- **dbsat/** - DBSAT collection and reports, written by `make dbsat-seclab`

## Notes

- This folder is mounted into the container `seclab` at startup.
- The contents are ignored in Git to avoid committing database files.
- `make reset-seclab` deletes this folder and restores only the tracked
  markers.
