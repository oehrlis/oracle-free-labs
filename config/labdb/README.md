# Lab DB Configuration

This folder contains the configuration for the **labdb** service.  
It provides one-time setup scripts and recurring startup scripts that are
mounted into the container when the service is started.

## Bind Mounts

The following paths are mounted into the container:

- **./config/common/scripts → /opt/oracle/common/scripts**  
  Shared SQL and shell helper scripts available to all services.  
  These scripts are not executed automatically but can be called manually or
  referenced with `@/opt/oracle/common/scripts/<script.sql>`.

- **./config/labdb/setup → /opt/oracle/scripts/setup**  
  One-time setup scripts for the LabDB PDB.  
  Files in this directory are executed automatically on the first startup of
  the container to configure the database.

- **./config/labdb/startup → /opt/oracle/scripts/startup**  
  Recurring startup scripts for the LabDB PDB.  
  Files in this directory are executed automatically on every container start
  after the database has been opened.

## Notes

- Setup scripts should be numbered (for example `00_config_db.sql`,
  `10_baseline_labpdb1.sql`) to enforce execution order.
- Startup scripts can be used for recurring configuration such as ACLs, jobs,
  or health checks.
- Shared logic that applies across multiple services should go into
  `config/common/scripts`.
