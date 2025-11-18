# Miscellaneous DBA Tasks

This page collects smaller DBA tasks that are often needed when working with the container databases.  
Over time this will grow into a reference for common maintenance and housekeeping activities.

## Check database status

Check whether the database and PDBs are open.

```bash
docker exec -it labdb bash -lc "sqlplus -s / as sysdba <<'SQL'
set lines 200 pages 100
show con_name
select name, open_mode from v\$pdbs order by con_id;
SQL"
````

## Restart a service

Restart a container and its database instance.

### Docker

```bash
docker compose --profile labdb restart
```

### Podman

```bash
podman restart labdb
```

## Run Oracle standard scripts

### Compile invalid objects

```bash
docker exec labdb bash -lc "sqlplus -s / as sysdba @?/rdbms/admin/utlrp.sql"
```

### Gather dictionary statistics

```bash
docker exec labdb bash -lc "sqlplus -s / as sysdba @?/rdbms/admin/dbms_stats.sql"
```

## Check listener status

```bash
docker exec -it labdb bash -lc "lsnrctl status"
```

## Check alert log

The alert log is usually in `diag` under ORACLE\_BASE.

```bash
docker exec -it labdb bash -lc "tail -n 100 $ORACLE_BASE/diag/rdbms/*/*/trace/alert_$ORACLE_SID.log"
```

## Create a new user

Example: create a demo user with password and tablespace.

```bash
docker exec -it labdb bash -lc "sqlplus / as sysdba <<'SQL'
create user demo identified by Demo123
  default tablespace users
  temporary tablespace temp
  quota unlimited on users;

grant connect, resource to demo;
SQL"
```

## Links

- [Service Setup](service_setup.md)
- [Interactive Shell Access](interactive_shell.md)
- [SQL Access](sql_developer.md)
- [Reset Passwords](reset_passwords.md)
- [Troubleshooting](troubleshooting.md)
