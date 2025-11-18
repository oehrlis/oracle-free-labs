# OraDBA Demo - Basic Repository Configuration (SQL Scripts)

This folder contains the configuration for the **odbdemo** service - creates an
OraDBA repository using SQL scripts. It provides one-time setup scripts and
recurring startup scripts that are mounted into the container when the service
is started.

## Bind Mounts

The following paths are mounted into the container:

- **./config/common/scripts → /opt/oracle/common/scripts**  
  Shared SQL and shell helper scripts available to all services.  
  These scripts are not executed automatically but can be called manually or
  referenced with `@/opt/oracle/common/scripts/<script.sql>`.

- **./config/odbdemo/setup → /opt/oracle/scripts/setup**  
  One-time setup scripts for the OraDBA Demo PDB.  
  Files in this directory are executed automatically on the first startup of
  the container to configure the database.

- **./config/odbdemo/startup → /opt/oracle/scripts/startup**  
  Recurring startup scripts for the OraDBA Demo PDB.  
  Files in this directory are executed automatically on every container start
  after the database has been opened.

## Notes

- Setup scripts should be numbered (for example `00_config_db.sql`,
  `10_create_pdb_odbdemo.sql`) to enforce execution order.
- Startup scripts can be used for recurring configuration such as ACLs, jobs,
  or health checks.
- Shared logic that applies across multiple services should go into
  `config/common/scripts`.
