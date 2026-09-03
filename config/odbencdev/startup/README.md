# odbencdev Startup Scripts

This folder contains startup scripts that are executed every time the
`odbencdev` container starts. Use these scripts for recurring configuration
tasks that must be applied after the database instance is started.

## Scripts in Use

- **00_startup_config.sql**
  Basic instance startup configuration. Executed in CDB$ROOT to apply settings
  each time the database instance is started.

- **01_setup_network_wallet.sh**
  Runs the common network and wallet persistence setup. Redirects the Oracle
  wallet to the persistent bind-mounted `dbconfig/FREE/wallet/` directory and
  validates the `/opt/oracle/network/admin` symlink.

## Notes

- Scripts in this folder run after the database instance is started.
- Because `odbencdev` holds no persistent PDB on the first start (PDBs are
  restored from `odbencprod` backups during the verification test phases), there
  is no PDB-scoped startup script.
- Number files sequentially (for example `20_verify.sql`) to control execution
  order when adding test-phase scripts.
