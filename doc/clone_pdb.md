# Clone a PDB

This guide explains how to clone a pluggable database (PDB) in the same CDB.  
You can do it manually with SQL*Plus or automatically with the helper script `clone_pdb.sql`.

## Overview

- Works inside one CDB (local clone)  
- Source PDB stays intact, the target PDB is created as a copy  
- With Oracle Managed Files (OMF) you usually do not need FILE_NAME_CONVERT  
- If you store files in custom paths, use FILE_NAME_CONVERT  

## Prerequisites

- SYSDBA access to the container  
- Enough disk space for the clone  
- Source PDB is healthy  
- If TDE is enabled, make sure the keystore is open in the CDB before cloning  

## Manual clone with SQL*Plus

Replace placeholders with your names and paths:

- SRC_PDB is the source PDB name (for example ODBDEMO)  
- CLONE_PDB is the new PDB name (for example ODBSEED)  
- Adjust host ports to your service  

### Connect to the CDB as SYS

```bash
docker exec -it odbdemo bash
sqlplus / as sysdba
````

Verify where you are and list PDBs:

```sql
show con_name;
select con_id, name, open_mode from v$pdbs order by con_id;
```

### Option A: clone with OMF (no FILE\_NAME\_CONVERT)

If DB\_CREATE\_FILE\_DEST is set, file placement is automatic.

```sql
alter session set container = CDB$ROOT;

create pluggable database CLONE_PDB
  from SRC_PDB
  admin user admin identified by "AdminPassword1";

alter pluggable database CLONE_PDB open;
alter pluggable database CLONE_PDB save state;
```

### Option B: clone with FILE\_NAME\_CONVERT

If you store files in named directories, point to the new location.

```sql
alter session set container = CDB$ROOT;

create pluggable database CLONE_PDB
  from SRC_PDB
  file_name_convert=(
    '/opt/oracle/oradata/FREE/SRC_PDB',
    '/opt/oracle/oradata/FREE/CLONE_PDB'
  )
  admin user admin identified by "AdminPassword1";

alter pluggable database CLONE_PDB open;
alter pluggable database CLONE_PDB save state;
```

### Verify the clone

```sql
select name, open_mode from v$pdbs where name in ('SRC_PDB','CLONE_PDB');
select name from v$services order by 1;
```

Connect to the clone from host:

```bash
sqlplus sys/Oracle123@localhost:1527/CLONE_PDB as sysdba
```

### Clean up if needed

```sql
alter session set container = CDB$ROOT;
alter pluggable database CLONE_PDB close immediate;
drop pluggable database CLONE_PDB including datafiles;
```

## Automated clone with clone\_pdb.sql

Use the helper script to clone with one command.
It validates the source, prevents overwriting existing targets, and saves state on success.

### Where the script lives

- Host path: `config/common/scripts/clone_pdb.sql`
- Mapped inside the container as:

  - `/opt/oracle/common/scripts/clone_pdb.sql` for labpdb1, odbrepo, odbseed, odbdemo
  - `/opt/oracle/scripts/clone_pdb.sql` for cdbfree

### Usage

From a container shell:

```bash
docker exec -it odbdemo bash
sqlplus / as sysdba @/opt/oracle/common/scripts/clone_pdb.sql SRC_PDB CLONE_PDB
```

Examples:

```bash
sqlplus / as sysdba @/opt/oracle/common/scripts/clone_pdb.sql ODBDEMO ODBSEED
sqlplus / as sysdba @/opt/oracle/common/scripts/clone_pdb.sql FREEPDB1 LABPDB1
```

Notes

- With OMF the script does not need FILE\_NAME\_CONVERT
- If your environment requires explicit paths, adapt the script to accept a third argument for
  FILE\_NAME\_CONVERT or set a default base path
- Logs are written under the service logs directory (`./data/<service>/logs/`)

## Tips

- If you see ORA-65011 (PDB already exists), drop or rename the target PDB
- If the listener does not know the service, wait a few seconds or verify `select name from v$services`
- For repeatable labs, consider saving the clone as a PDB archive (see [Create a PDB Archive](create_pdb_archive.md))

## Links

- [Service Setup](service_setup.md)
- [Create a PDB Archive](create_pdb_archive.md)
- [Create a PDB from Archive](create_pdb_from_archive.md)
- [SQL Access](sql_developer.md)
- [Troubleshooting](troubleshooting.md)
