# odbencprod Startup Scripts

This folder contains startup scripts that are executed every time the
`odbencprod` container starts. Use these scripts for recurring configuration
tasks that must be applied after the database and the `ODBENCPROD` PDB are
opened.

## Scripts in Use

- **00_startup_config.sql**
  Basic instance startup configuration. Executed in CDB$ROOT to apply settings
  each time the database instance is started.

- **01_setup_network_wallet.sh**
  Runs the common network and wallet persistence setup. Redirects the Oracle
  wallet to the persistent bind-mounted `dbconfig/FREE/wallet/` directory and
  validates the `/opt/oracle/network/admin` symlink.

- **10_startup_config_odbencprod.sql**
  Basic instance startup configuration for the PDB `ODBENCPROD`. Executed after
  the PDB is opened to apply PDB-scoped settings.

## Notes

- Scripts in this folder run after the database instance is started and the
  PDBs are opened.
- Use this folder for configuration that must persist across restarts, such as
  grants, ACL adjustments, maintenance jobs, or health checks.
- Number files sequentially (for example `20_jobs.sql`, `30_verify.sql`) to
  control execution order.
