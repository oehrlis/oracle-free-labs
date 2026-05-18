# Oracle Lab Environment Documentation

This repository provides documentation for setting up and working with the Oracle Lab Environment.
Each topic is covered in a dedicated Markdown file for modular use.

## Navigation

| Topic | Description |
|-------|-------------|
| [Setup Lab Environment](setup_lab_environment.md) | Prepare host, install prerequisites, configure environment |
| [Service Setup](service_setup.md) | Walkthrough for configuring and starting each service |
| [Demo and Engineering Overlays](demo_overlay.md) | Extend the lab with demo scripts and config from external repos |
| [Install BasEnv](install_basenv.md) | Optional installation of BasEnv for a richer DBA environment |
| [Interactive Shell Access](interactive_shell.md) | Open a shell in a container, run scripts, start SQL*Plus |
| [SQL Access](sql_developer.md) | Connect via SQL Developer or SQL*Plus, run SQL scripts |
| [Reset Passwords](reset_passwords.md) | Reset SYS, SYSTEM, PDBADMIN, and application user passwords |
| [Clone a PDB](clone_pdb.md) | Manual and scripted methods to clone a PDB |
| [Create a PDB Archive](create_pdb_archive.md) | Package a PDB into a portable archive |
| [Create a PDB from Archive](create_pdb_from_archive.md) | Create a new PDB from an existing archive |
| [Miscellaneous DBA Tasks](misc_dba_tasks.md) | Handy DBA tasks such as checking status, restarting, creating users |
| [Troubleshooting](troubleshooting.md) | Common issues and how to resolve them |
| [Decommission a Container](decommission_service.md) | Stop and remove a container service and clean up persistent data |

## Architecture Diagram

The following diagram shows how the lab services map together.

![OraDBA Lab Mapping](oracle-free-labs.png)

- [Download editable Excalidraw file](oracle-free-labs.excalidraw)

## Conventions

To keep things consistent across scripts and documentation, the following conventions are used:

- **Environment Variables**

  - Uppercase, prefixed with `ORACLE_` (e.g. `ORACLE_SID`, `ORACLE_PDB`).
  - Set in `.env` and applied via Docker/Podman Compose.

- **Folder Structure**

  - `config/<service>`: Service-specific configuration (setup/startup scripts).
  - `config/common/scripts`: Shared SQL and shell scripts.
  - `data/`: Persistent database data (mounted into containers).
  - `doc/`: Documentation (this folder).

- **Scripts**

  - SQL scripts: `.sql` (for SQL\*Plus execution).
  - Shell scripts: `.sh` (Bash scripts, with OraDBA header style).
  - Templates: prefixed with `xx_` for customization examples.

- **Logging & Spooling**

  - Scripts spool to files named `scriptname_<db>_<pdb>_<timestamp>.log`.

- **Database Users**

  - Core accounts (`SYS`, `SYSTEM`, `PDBADMIN`) default to a common password set via `bin/setPassword.sh`.
  - Application accounts (e.g. `EAUSER`) may start with *no authentication* and must be reset manually.
