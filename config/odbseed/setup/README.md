# EA Repository Setup

This folder contains setup scripts that are executed once during container
initialization to prepare the environment for the EA repository. The scripts
must be run in the specified order.

## Scripts in Use

- **00_common_db_config.sql**  
  Basic instance configuration. Sets parameters that require a restart.  
  Must be executed in CDB$ROOT as SYSDBA.

- **01_drop_pdb_freepdb1.sql**  
  Drops the default pluggable database `FREEPDB1` if it exists.  
  This avoids conflicts before creating the EA repository PDB.

- **10_create_pdb_from_archive.sql**  
  Creates the pluggable database `ODBSEED` from a PDB archive.  
  The archive file `pdb23ai_odbseed.pdb` must be placed in
  `config/common/data/pdbarch` before starting the container.

## Notes

- Scripts in this folder run automatically during the first container startup.
- Ensure the required archive file `pdb23ai_odbseed.pdb` is available in
  `config/common/data/pdbarch` before starting the container.
- File names are numbered to enforce execution order.
- Additional setup scripts can be added as needed to extend or customize the
  EA repository environment.
