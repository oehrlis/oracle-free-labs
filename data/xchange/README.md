# Data exchange directory

This folder is a shared read-write mount between the `odbencprod` and
`odbencdev` containers. It is mounted as `/opt/oracle/xchange` in both services.

## Purpose

Used to transfer files between the two TDE restore verification containers:

- RMAN backup sets produced on `odbencprod`
- Wallet exports (`ADMINISTER KEY MANAGEMENT EXPORT KEYS`)
- Any other artefacts needed during the restore and verification workflow

## Notes

- The contents are ignored in Git to avoid committing database backup files.
- Both containers mount this directory read-write at the same container path
  (`/opt/oracle/xchange`), so files written by one container are immediately
  visible in the other.
