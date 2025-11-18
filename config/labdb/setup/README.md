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

- **10_create_pdb_labpdb1.sql**  
  Creates the pluggable database `LABPDB1` from `PDB$SEED` if it does not
  already exist.

- **11_init_audit_config_labpdb1.sql**  
  Initializes the audit environment for `LABPDB1`. Creates a dedicated tablespace
  and reorganizes existing audit structures.

- **12_create_audit_policies_labpdb1.sql**  
  Creates custom local audit policies in `LABPDB1`.

- **13_enable_audit_policies_labpdb1.sql**  
  Enables the custom local audit policies created in the previous step.

- **14_create_directory_labpdb1.sql**  
  Creates required Oracle directories in `LABPDB1`.

- **15_create_ts_users_labpdb1.sql**  
  Create USERS tablespace in PDB LABPDB1 and set it as the default database tablespace.

## Notes

- Scripts in this folder run automatically during the first container startup.
- File names are numbered to enforce execution order.
- Additional setup scripts can be added as needed to extend or customize the
  EA demo repository environment.
