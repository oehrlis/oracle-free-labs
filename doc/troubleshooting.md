# Troubleshooting

This document provides guidance for common issues when working with the Oracle database containers.  
Check here if a service fails to start, keeps restarting, or you cannot connect.

## Container keeps restarting

- *Symptom**  
Container exits and Docker keeps restarting it.

- *Possible causes**  
- Insufficient memory or shared memory (DB_MEM, DB_SHM_SIZE) in `.env`  
- Database files corrupted or incompatible with current image  
- Wrong bind mount paths in docker-compose.yml  

- *Solution**  
- Increase memory limits in `.env`  

   ```ini
   DB_MEM=8g
   DB_SHM_SIZE=1g
   ```

- Remove and re-create the data directory for the service (this wipes data)

  ```bash
  rm -rf ./data/labdb/*
  docker compose --profile labdb up -d
  ```

## Database never reaches ready state

-*Symptom**
Logs show startup but never display the ready message:

```text
#########################
DATABASE IS READY TO USE!
#########################
```

-*Possible causes**

- Custom setup script failed with an error
- Wrong SQL syntax or missing privileges in `config/.../setup/`
- Corrupted or partial PDB archive

-*Solution**

- Inspect logs

  ```bash
  docker logs <container_name>
  ```

- Check last executed script in `./data/<service>/logs/`
- Fix script or re-import archive, then restart container

## ORA errors in logs

-*Symptom**
Startup logs contain Oracle errors and setup stops.

-*Common cases**

- ORA-65011: pluggable database already exists
- ORA-01017: invalid username or password
- ORA-12514: TNS listener does not currently know of service

-*Solution**

- Adjust setup scripts to clean up before creating new PDBs
- Ensure `.env` password matches actual SYS password
- Use `select name from v$services;` to verify service registration

## Cannot connect from host

-*Symptom**
SQL\*Plus or client cannot connect to service.

-*Checklist**

- Port mapping correct in `.env`
- Firewall not blocking port on host
- Listener running inside container

-*Solution**

- Verify port mappings

  ```bash
  docker ps --format "table {{.Names}}\t{{.Ports}}"
  ```

- Connect locally inside container

  ```bash
  docker exec -it labdb sqlplus / as sysdba
  ```

- If local works but host fails, check firewall or wrong mapped port

## Resetting the SYS password

-*Symptom**
Forgot the SYS password or mismatch with `.env`.

-*Solution**

- Enter container shell

  ```bash
  docker exec -it labdb bash
  ```

- Connect as OS user

  ```bash
  sqlplus / as sysdba
  ```

- Reset password

  ```sql
  alter user sys identified by NewPassword;
  ```

- Update `.env` with new password

## PDB archives fail

-*Symptom**
Errors when creating or restoring PDB from archive.

-*Possible causes**

- Missing archive file in `config/common/data/`
- Wrong path mapping for `${COMMON_DATA_HOST}`
- Archive corrupted or incompatible

-*Solution**

- Ensure archive file exists under `config/common/data/`
- Confirm `${COMMON_DATA_HOST}` is set in `.env`
- Recreate archive from a working instance if needed

## Useful commands

- Show all running containers and ports

  ```bash
  docker ps
  ```

- Restart a service

  ```bash
  docker compose --profile labdb restart
  ```

- Remove a service with its data

  ```bash
  docker compose --profile labdb down
  rm -rf ./data/labdb/*
  ```

## Still stuck

- Re-check logs in `./data/<service>/logs/`
- Compare `.env` against a known working copy
- Test with `cdbfree` first (minimal setup)
- As last resort remove all `data/` subdirectories and reinitialize

## Links

- [Service Setup](service_setup.md)
- [Interactive Shell Access](interactive_shell.md)
- [SQL Access](sql_developer.md)
- [Reset Passwords](reset_passwords.md)
- [Miscellaneous DBA Tasks](misc_dba_tasks.md)
