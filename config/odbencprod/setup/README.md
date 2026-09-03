# odbencprod Setup Scripts

This folder contains one-time setup scripts for the `odbencprod` service - the
production-side database in the TDE restore verification test. Scripts are
executed automatically in alphabetical order on the first container start.

## Purpose

`odbencprod` simulates a production Oracle database with:

- ARCHIVELOG mode, enabled by the image default `ENABLE_ARCHIVELOG=true`
  (passed to DBCA as `-enableArchive`), required for RMAN backup and
  active database duplication
- A PDB `ODBENCPROD` with SCOTT and TVD_HR demo data
- TDE configured via WALLET_ROOT / software keystore
- The `USERS` tablespace online-encrypted (ciphertext baseline for the test)

## Scripts in Use

- **00_common_db_config.sql**
  Basic instance configuration. Sets parameters that require a restart.
  Must be executed in CDB$ROOT as SYSDBA.

- **01_drop_pdb_freepdb1.sql**
  Drops the default pluggable database `FREEPDB1` if it exists.

- **10_create_pdb_odbencprod.sql**
  Creates the pluggable database `ODBENCPROD` from `PDB$SEED`.

- **11_init_audit_config_odbencprod.sql**
  Initializes the audit environment for `ODBENCPROD`.

- **12_create_audit_policies_odbencprod.sql**
  Creates custom local audit policies in `ODBENCPROD`.

- **13_enable_audit_policies_odbencprod.sql**
  Enables the custom local audit policies.

- **14_create_directory_odbencprod.sql**
  Creates required Oracle directories in `ODBENCPROD`.

- **15_create_ts_users_odbencprod.sql**
  Creates the `USERS` tablespace and sets it as the default.

- **20_setup_tvd_hr_odbencprod.sql**
  Creates the TVD_HR demo schema in `ODBENCPROD`.

- **21_setup_scott_odbencprod.sql**
  Creates the SCOTT demo schema in `ODBENCPROD`.

- **30_config_tde_odbencprod.sql**
  Configures TDE: sets WALLET_ROOT, creates software keystore, creates master
  encryption key. Restarts the database twice (after WALLET_ROOT, after MEK).

- **31_encrypt_ts_users_odbencprod.sql**
  Encrypts the `USERS` tablespace online. This establishes the ciphertext
  baseline used for comparison in the verification test.

## Notes

- Scripts run automatically on first container startup.
- ARCHIVELOG needs no script: `ENABLE_ARCHIVELOG=true` is already set in the
  image and DBCA creates the archive destination itself. An explicit script
  setting `db_recovery_file_dest` broke the setup with ORA-01261 because
  Oracle does not create that directory.
- Additional test scripts (RMAN backup, canary data, ciphertext capture) are
  added manually in Phases 1 and above.
