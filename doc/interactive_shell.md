# Interactive Shell Access

This guide explains how to access a shell inside a running container for interactive work,
troubleshooting, and DBA tasks. You can open a shell, run scripts, or start SQL\*Plus directly.

## Requirements

For a richer DBA experience install BasEnv first.
With BasEnv you get convenient aliases, helper scripts, and environment setup.
Without BasEnv you still have a plain Oracle environment.

See [Install BasEnv](install_basenv.md) if needed.

## Open a shell

Use a login shell so environment files are sourced (`bash -l`).

### Docker

```bash
docker exec -it <service> bash -l

# examples
docker exec -it cdbfree bash -l
docker exec -it odbdemo  bash -l
```

### Podman

```bash
podman exec -it <service> bash -l

# examples
podman exec -it cdbfree bash -l
podman exec -it odbdemo  bash -l
```

Inside the shell you can verify the environment:

```bash
echo "USER=$(id -un) HOME=$HOME ORACLE_HOME=$ORACLE_HOME ORACLE_SID=$ORACLE_SID"
which sqlplus || echo "sqlplus not found in PATH"
```

If BasEnv is installed you can also run:

```bash
. oraenv
lsdba 2>/dev/null || true
```

## Run a script directly

Run host automation quickly without opening a shell.

### Docker

```bash
# run a repo script inside the container
docker exec -it odbdemo ./setPassword.sh <PASSWORD>

# run a custom script with arguments
docker exec -it odbdemo /opt/oradba/bin/some_script.sh --flag value
```

### Podman

```bash
podman exec -it odbdemo ./setPassword.sh <PASSWORD>
podman exec -it odbdemo /opt/oradba/bin/some_script.sh --flag value
```

If your script requires a login shell environment, use `bash -lc '…'`:

```bash
docker exec -it odbdemo bash -lc '/opt/oradba/bin/some_script.sh --flag value'
```

## Run SQL\*Plus interactively

Start SQL\*Plus directly from the host into the container.

### Docker

```bash
docker exec -it odbdemo sqlplus / as sysdba
```

### Podman

```bash
podman exec -it odbdemo sqlplus / as sysdba
```

If you prefer a login shell first:

```bash
docker exec -it odbdemo bash -lc "sqlplus / as sysdba"
```

## Run a SQL script non interactively

Run built-in or custom SQL scripts in one go.

### Docker

```bash
# run Oracle's utlrp
docker exec odbdemo bash -lc "sqlplus -s / as sysdba @?/rdbms/admin/utlrp.sql"

# run a repo script mounted in /opt/oracle/scripts/setup
docker exec odbdemo bash -lc "sqlplus -s / as sysdba @/opt/oracle/common/scripts/post_clone_task_df.sql odbdemo"
```

### Podman

```bash
podman exec odbdemo bash -lc "sqlplus -s / as sysdba @?/rdbms/admin/utlrp.sql"
podman exec odbdemo bash -lc "sqlplus -s / as sysdba @/opt/oracle/common/scripts/post_clone_task_df.sql odbdemo"
```

Use `-s` (silent) to keep output concise in CI logs.

## Helpful tips

- Use `bash -l` or `bash -lc '…'` to ensure environment files are sourced.
- For multiline commands, prefer a here-doc to avoid quoting issues:

```bash
docker exec -i odbdemo bash -l <<'EOS'
set -e
echo "ORACLE_SID=$ORACLE_SID"
sqlplus -s / as sysdba <<'SQL'
set termout on
select name, open_mode from v$database;
SQL
EOS
```

- Check listener and PDB quickly:

```bash
docker exec -it odbdemo bash -lc "
  lsnrctl status || true
  sqlplus -s / as sysdba <<'SQL'
  set lines 200 pages 100
  show con_name
  select name, open_mode from v\$pdbs order by con_id;
SQL
"
```

- If you installed BasEnv, many conveniences are available:

  - `oraenv.ksh` to load environment
  - `rmanch` for RMAN
  - `sqh` for direct connect *AS SYSDBA*
  - `tnsping FREE`, and other helpers

## Troubleshooting

- If `sqlplus` is not found, ensure `ORACLE_HOME/bin` is in `PATH` or use a login shell:

```bash
docker exec -it odbdemo bash -l
echo "$PATH"
```

- If the command exits immediately, confirm the container is running:

```bash
docker ps | grep odbdemo || echo "odbdemo not running"
```

- For permission issues with scripts, ensure they are executable:

```bash
git update-index --chmod=+x setPassword.sh
```

- To capture full output for support, tee into a log:

```bash
docker exec odbdemo bash -lc "sqlplus -s / as sysdba @?/rdbms/admin/utlrp.sql" | tee utlrp_odbdemo.log
```

## Links

- [Service Setup](service_setup.md)
- [Install BasEnv](install_basenv.md)
- [SQL Access](sql_access.md)
- [Troubleshooting](troubleshooting.md)
