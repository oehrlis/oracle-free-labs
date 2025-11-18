# Create a PDB Archive

This guide explains how to create a pluggable database (PDB) archive.  
A PDB archive is a portable copy of a PDB that can be stored as a zip file and later used to create new PDBs.  
This is useful to seed environments, build demos, or reset a database to a known state.

## Overview

- The archive contains metadata and datafiles of a PDB  
- Stored in a zip file in a directory accessible to the container  
- Can later be used to create a new PDB in the same or another container  
- Oracle provides `DBMS_PDB.PACKAGE_PDB` to build the archive  

## Prerequisites

- SYSDBA access to the container  
- Source PDB is closed  
- Enough disk space for the zip file  
- Target directory is writable by the Oracle user inside the container  

## Manual creation with SQL*Plus

Replace placeholders with your values:

- SRC_PDB is the PDB you want to archive  
- ARCHDIR is the Oracle directory object pointing to the host path where the zip will be stored  
- ARCHIVE_FILE is the name of the zip file  

### Connect to the CDB as SYS

```bash
docker exec -it odbdemo bash
sqlplus / as sysdba
````

### Create or reuse a directory

```sql
create or replace directory ARCHDIR as '/opt/oracle/data';
grant read, write on directory ARCHDIR to sys;
```

### Close the source PDB

```sql
alter pluggable database SRC_PDB close immediate;
```

### Package the PDB into a zip

```sql
begin
  dbms_pdb.package_pdb(
    pdb_name  => 'SRC_PDB',
    directory => 'ARCHDIR',
    filename  => 'SRC_PDB.zip');
end;
/
```

### Verify file exists

```bash
ls -lh /opt/oracle/data/SRC_PDB.zip
```

### Reopen the PDB

```sql
alter pluggable database SRC_PDB open;
```

## Automated archive with create\_pdb\_archive.sql

Use the helper script `create_pdb_archive.sql` to automate these steps.
It validates the source PDB, closes it, packages the archive, and reopens it.

### Where the script lives

- Host path: `config/common/scripts/create_pdb_archive.sql`
- Mapped inside the container as:

  * `/opt/oracle/common/scripts/create_pdb_archive.sql` for labpdb1, odbrepo, odbseed, odbdemo
  * `/opt/oracle/scripts/create_pdb_archive.sql` for cdbfree

### Usage

From a container shell:

```bash
docker exec -it odbdemo bash
sqlplus / as sysdba @/opt/oracle/common/scripts/create_pdb_archive.sql SRC_PDB ARCHDIR ARCHIVE_FILE
```

Examples:

```bash
sqlplus / as sysdba @/opt/oracle/common/scripts/create_pdb_archive.sql ODBDEMO ARCHDIR ODBDEMO.zip
sqlplus / as sysdba @/opt/oracle/common/scripts/create_pdb_archive.sql LABPDB1 ARCHDIR LABPDB1.zip
```

Notes

- ARCHDIR must be a valid Oracle directory object, usually mapped to COMMON\_DATA\_HOST
- If you omit the filename, the script can default to `<PDBNAME>.zip`
- Logs are written to `./data/<service>/logs/`

## Tips

- If you see ORA- errors about the directory, confirm it exists and is granted to SYS
- Close the PDB before packaging, otherwise the procedure fails
- After packaging, always reopen the PDB
- Store archives under `config/common/data` so they are available to other services

## Links

- [Service Setup](service_setup.md)
- [Clone a PDB](clone_pdb.md)
- [Create a PDB from Archive](create_pdb_from_archive.md)
- [Interactive Shell Access](interactive_shell.md)
- [SQL Access](sql_developer.md)
- [Troubleshooting](troubleshooting.md)
