# EA Demo Setup

This folder contains setup scripts that are executed once during container
initialization to prepare the environment for the EA demo repository. The
scripts must be run in the specified order.

## Scripts in Use

- **00_common_db_config.sql**  
  Basic instance configuration. Sets parameters that require a restart.  
  Must be executed in CDB$ROOT as SYSDBA.

- **01_drop_pdb_freepdb1.sql**  
  Drops the default pluggable database `FREEPDB1` if it exists.  
  This avoids conflicts before creating the EA demo PDB.

- **10_create_pdb_odbdemo.sql**  
  Creates the pluggable database `ODBDEMO` from `PDB$SEED` if it does not
  already exist.

- **11_init_audit_config_odbdemo.sql**  
  Initializes the audit environment for `ODBDEMO`. Creates a dedicated tablespace
  and reorganizes existing audit structures.

- **12_create_audit_policies_odbdemo.sql**  
  Creates custom local audit policies in `ODBDEMO`.

- **13_enable_audit_policies_odbdemo.sql**  
  Enables the custom local audit policies created in the previous step.

- **14_create_directory_odbdemo.sql**  
  Creates required Oracle directories in `ODBDEMO`.

- **15_create_ts_users_odbdemo.sql**  
  Create USERS tablespace in PDB LABPDB1 and set it as the default database tablespace.

- **20_setup_ea_baseline_odbdemo.sql**  
  Applies the PDB-scoped security baseline for the EA demo repository.

- **21_setup_ea_schema_odbdemo.sql**  
  Creates the schema for `ODBDEMO`, including users, roles, and required objects.

- **22_init_ea_schema_odbdemo.sql**  
  Initializes the schema with seed data and required structures.

- **30_clone_odbdemo_to_odbseed.sql**  
  Clone pluggable database `ODBDEMO` to `ODBSEED`.

- **31_create_pdb_archive_odbseed.sql**  
  Create a pdb archive from `ODBSEED` and drop the pdb.

## Notes

- Scripts in this folder run automatically during the first container startup.
- File names are numbered to enforce execution order.
- Additional setup scripts can be added as needed to extend or customize the
  EA demo repository environment.
