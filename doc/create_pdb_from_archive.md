# Create a PDB from Archive

This guide explains how to create a new pluggable database (PDB) from an existing PDB archive (zip file).  
This is the reverse step of creating an archive and allows you to quickly provision a fresh PDB from a known baseline.

## Overview

- A PDB archive is produced with `DBMS_PDB.PACKAGE_PDB`  
- To restore, Oracle unpacks the archive and creates a new PDB  
- Common use cases are seeding, demos, or fast recovery of lab databases  
- The archive is usually stored under `config/common/data` and bind-mounted into containers  

## Prerequisites

- SYSDBA access to the container  
- Archive file available in a mapped directory  
- Enough disk space for the extracted PDB files  
- Target PDB name not already in use  
- If TDE is enabled, the keystore must be open in the CDB before creating the PDB  

## Manual creation with SQL*Plus

Replace placeholders with your values:

- NEW_PDB is the target PDB name  
- ARCHDIR is the Oracle directory object pointing to the archive location  
- ARCHIVE_FILE is the zip file created earlier  

### Connect to the CDB as SYS

```bash
docker exec -it odbseed bash
sqlplus / as sysdba
````

### Ensure directory object exists

```sql
create or replace directory ARCHDIR as '/opt/oracle/data';
grant read, write on directory ARCHDIR to sys;
```

### Create the PDB from archive

```sql
alter session set container = CDB$ROOT;

create pluggable database NEW_PDB
  using '/opt/oracle/data/ARCHIVE_FILE'
  admin user admin identified by "AdminPassword1";
```

If you are not using Oracle Managed Files and need explicit paths, add FILE\_NAME\_CONVERT:

```sql
create pluggable database NEW_PDB
  using '/opt/oracle/data/ARCHIVE_FILE'
  file_name_convert=(
    '/opt/oracle/oradata/FREE/SOURCE_PDB',
    '/opt/oracle/oradata/FREE/NEW_PDB'
  )
  admin user admin identified by "AdminPassword1";
```

### Open and save state

```sql
alter pluggable database NEW_PDB open;
alter pluggable database NEW_PDB save state;
```

### Verify

```sql
select name, open_mode from v$pdbs where name = 'NEW_PDB';
```

## Automated creation with create\_pdb\_from\_archive.sql

Use the helper script `create_pdb_from_archive.sql` to automate the process.
It validates the archive, creates the PDB, and opens it for use.

### Where the script lives

- Host path: `config/common/scripts/create_pdb_from_archive.sql`
- Mapped inside the container as:

  - `/opt/oracle/common/scripts/create_pdb_from_archive.sql` for labpdb1, odbrepo, odbseed, odbdemo
  - `/opt/oracle/scripts/create_pdb_from_archive.sql` for cdbfree

### Usage

From a container shell:

```bash
docker exec -it odbseed bash
sqlplus / as sysdba @/opt/oracle/common/scripts/create_pdb_from_archive.sql NEW_PDB ARCHDIR ARCHIVE_FILE
```

Examples:

```bash
sqlplus / as sysdba @/opt/oracle/common/scripts/create_pdb_from_archive.sql ODBREPO ARCHDIR ODBREPO.zip
sqlplus / as sysdba @/opt/oracle/common/scripts/create_pdb_from_archive.sql ODBSEED ARCHDIR ODBDEMO.zip
```

Notes

- ARCHDIR must be a valid Oracle directory object mapped to the host path
- File name must match the archive zip created earlier
- Logs are stored in `./data/<service>/logs/`

## Tips

- If you see ORA-65011 (PDB already exists), drop or rename the target PDB
- If ORA- errors about missing file appear, check directory mapping and filename
- Use `select name from v$services` to confirm the new PDB service is registered
- Save the state to ensure automatic open after restarts

## Links

- [Service Setup](service_setup.md)
- [Clone a PDB](clone_pdb.md)
- [Create a PDB Archive](create_pdb_archive.md)
- [Interactive Shell Access](interactive_shell.md)
- [SQL Access](sql_developer.md)
- [Troubleshooting](troubleshooting.md)
