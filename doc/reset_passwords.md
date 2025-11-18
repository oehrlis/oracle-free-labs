# Reset Passwords

This guide explains how to reset Oracle database user passwords inside the container.  
You can use the helper script `setPassword.sh` for system accounts (SYS, SYSTEM, PDBADMIN) or SQL*Plus for application users such as TVD_HR.

## Default password

A default password can be set during container setup using the environment variable `ORACLE_PWD` in `.env`.

```ini
ORACLE_PWD=Oracle123
````

This initializes the SYS, SYSTEM, and PDBADMIN accounts with the same password.

Recommendation: do not rely on this default for production-like environments. Instead set passwords explicitly with `setPassword.sh` after the container is started.

## Reset SYS, SYSTEM, PDBADMIN

The script `setPassword.sh` updates all three accounts in CDB and PDB.

### Docker

```bash
docker exec -it cdbfree ./setPassword.sh NewPassword1
```

### Podman

```bash
podman exec -it cdbfree ./setPassword.sh NewPassword1
```

Output will confirm the accounts were updated. The new password can now be used to connect.

Example with SQL\*Plus:

```bash
sqlplus sys/NewPassword1@localhost:1526/FREEPDB1 as sysdba
```

## Reset application users

For other users such as TVD_HR you must use SQL\*Plus and `ALTER USER`.

### Example

```bash
docker exec -it odbdemo bash -lc "sqlplus / as sysdba"
```

Inside SQL\*Plus:

```sql
alter user tvd_hr identified by "OraDBA123";
```

Verify the change by connecting:

```bash
docker exec -it odbdemo sqlplus tvd_hr/OraDBA123@localhost:1530/ODBDEMO
```

## Tips

- Always use strong passwords, especially for SYS and SYSTEM
- If you forget the password for SYS, SYSTEM, or PDBADMIN, you can rerun `setPassword.sh` at any time
- For custom users, you can always reset with `ALTER USER` as SYSDBA
- Store updated credentials securely if you share the environment with a team

## Links

- [Service Setup](service_setup.md)
- [Interactive Shell Access](interactive_shell.md)
- [SQL Access](sql_developer.md)
- [Troubleshooting](troubleshooting.md)
