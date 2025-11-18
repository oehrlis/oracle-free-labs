# Data Folder

The `data/` folder stores persistent database files and configuration that are
mounted into the containers. Each service has its own subfolder to avoid
conflicts.

## Structure

- **cdbfree/**  
  Data for the plain Oracle AI Database 26ai Free container.

- **labdb/**  
  Data for the empty lab database container.

- **odbrepo/**  
  Data for the OraDBA repository created with SQL scripts.

- **odbseed/**  
  Data for the OraDBA repository created from a PDB archive.

- **odbdemo/**  
  Data for the OraDBA repository created from `PDB$SEED`.

## Notes

- The contents of this folder are **not versioned** in Git.  
  They are ignored via `.gitignore` to prevent large binary database files from
  being committed.
- Each service folder usually contains:
  - **FREE/** - the Oracle database files
  - **dbconfig/** - service configuration such as `tnsnames.ora` or wallets
- These directories are automatically mounted into the containers based on the
  service definition in `docker-compose.yml`.
- If a folder does not exist, it will be created on first container startup.
