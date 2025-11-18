# SQL Access

This guide explains how to connect to Oracle services with SQL Developer or SQL*Plus.  
It also shows how to execute SQL scripts inside containers.

## Requirements

- A running container with a ready database. Check logs until you see:

```text
#########################
DATABASE IS READY TO USE!
#########################
```

- The correct listener port from `.env`  
- SQL Developer installed on your host, or SQL*Plus available inside the container  

See [Service Setup](service_setup.md) for container details.

## Access with SQL Developer

1. Open SQL Developer on your host.  
2. Create a new connection with the following details.  

### Connection table

| Service | Host      | Port | Service name | User | Password  | Role   |
|---------|-----------|------|--------------|------|-----------|--------|
| cdbfree | localhost | 1526 | FREEPDB1     | sys  | Oracle123 | SYSDBA |
| labdb   | localhost | 1527 | LABPDB1      | sys  | Oracle123 | SYSDBA |
| odbrepo | localhost | 1528 | ODBREPO      | sys  | Oracle123 | SYSDBA |
| odbseed | localhost | 1529 | ODBSEED      | sys  | Oracle123 | SYSDBA |
| odbdemo | localhost | 1530 | ODBDEMO      | sys  | Oracle123 | SYSDBA |

Adjust ports and service names if you changed defaults in `.env`.  

3. Test and save the connection.  
4. Connect and start working with the database.  

### Optional: Use tnsnames.ora in SQL Developer

If you prefer to use Oracle Net aliases, you can add the following entries to your `tnsnames.ora` file on the host:

```ini
CDBFREE =
(DESCRIPTION =
  (ADDRESS = (PROTOCOL = TCP)(HOST = localhost)(PORT = 1526))
  (CONNECT_DATA = (SERVICE_NAME = FREEPDB1))
)

LABPDB1 =
(DESCRIPTION =
  (ADDRESS = (PROTOCOL = TCP)(HOST = localhost)(PORT = 1527))
  (CONNECT_DATA = (SERVICE_NAME = LABPDB1))
)

ODBREPO =
(DESCRIPTION =
  (ADDRESS = (PROTOCOL = TCP)(HOST = localhost)(PORT = 1528))
  (CONNECT_DATA = (SERVICE_NAME = ODBREPO))
)

ODBSEED =
(DESCRIPTION =
  (ADDRESS = (PROTOCOL = TCP)(HOST = localhost)(PORT = 1529))
  (CONNECT_DATA = (SERVICE_NAME = ODBSEED))
)

ODBDEMO =
(DESCRIPTION =
  (ADDRESS = (PROTOCOL = TCP)(HOST = localhost)(PORT = 1530))
  (CONNECT_DATA = (SERVICE_NAME = ODBDEMO))
)
````

Then in SQL Developer choose connection type **TNS** and select the alias.

## Access with SQL\*Plus interactively

Run SQL\*Plus inside the container.

### Docker

```bash
docker exec -it cdbfree sqlplus / as sysdba
```

Or connect to a specific PDB:

```bash
docker exec -it labdb sqlplus sys/Oracle123@localhost:1527/LABPDB1 as sysdba
```

### Podman

```bash
podman exec -it cdbfree sqlplus / as sysdba
```

If you want to load environment variables first:

```bash
docker exec -it labdb bash -lc "sqlplus / as sysdba"
```

## Import predefined connections

Instead of creating each connection manually, you can import all lab connections at once using the provided JSON file `ealab_connections.json`.

1. Download the file [ealab_connections.json](../ealab_connections.json)  
2. In SQL Developer, go to  
   **Tools > Preferences > Database > Advanced > Import Connections**  
3. Select the JSON file and confirm  
4. You will see a folder `OraDBA` in the Connections panel containing entries for each service:
   - `<service> CDB$ROOT` (connects to the CDB root as SYSDBA)  
   - `<service> <PDBNAME>` (connects to the PDB as SYSDBA)  

Example after import:

```text

OraDBA
├── cdbfree
│   ├── cdbfree CDB$ROOT
│   └── cdbfree FREEPDB1
├── labdb
│   ├── labdb CDB$ROOT
│   └── labdb FREEPDB1
├── odbdemo
│   ├── odbdemo CDB$ROOT
│   ├── odbdemo ODBDEMO
│   └── odbdemo ODBDEMO EAUSER
├── odbseed
│   ├── odbseed CDB$ROOT
│   ├── odbseed ODBSEED
│   └── odbseed EAEED EAUSER
└── odbrepo
    ├── odbrepo CDB$ROOT
    └── odbrepo ODBREPO
```

All connections use `sys` as user with role `SYSDBA`.  
By default the password is not stored (SavePassword=false). You will be prompted when connecting.

## Run SQL scripts non interactively

Execute SQL scripts inside the container in one step.

### Docker

```bash
# run Oracle's utlrp script
docker exec labdb bash -lc "sqlplus -s / as sysdba @?/rdbms/admin/utlrp.sql"

# run a repo script mounted in /opt/oracle/common/scripts
docker exec odbdemo bash -lc "sqlplus -s / as sysdba @/opt/oracle/common/scripts/post_clone_task_df.sql odbdemo"
```

### Podman

```bash
podman exec labdb bash -lc "sqlplus -s / as sysdba @?/rdbms/admin/utlrp.sql"
podman exec odbdemo bash -lc "sqlplus -s / as sysdba @/opt/oracle/common/scripts/post_clone_task_df.sql odbdemo"
```

Use `-s` (silent) to reduce output in CI logs.

## Tips

- Always confirm the listener port from `.env`
- Service name is usually the PDB name (FREEPDB1, LABPDB1, ODBDEMO)
- For long SQL scripts, use `docker exec -i` with a here-doc:

```bash
docker exec -i odbdemo bash -l <<'EOS'
sqlplus -s / as sysdba <<'SQL'
set heading on
select name, open_mode from v$pdbs order by con_id;
SQL
EOS
```

## Links

- [Service Setup](service_setup.md)  
- [Interactive Shell Access](interactive_shell.md)  
- [Install BasEnv](install_basenv.md)  
- [Troubleshooting](troubleshooting.md)  
- [Predefined Connections JSON](../ealab_connections.json)  
