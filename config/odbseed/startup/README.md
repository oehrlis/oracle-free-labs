# OraDBA Demo Startup

This folder contains startup scripts that are executed every time the container
starts. Use these scripts for recurring configuration tasks that must be applied
after the database and the `ODBSEED` PDB are opened.

## Scripts in Use

- **00_startup_config.sql**  
  Basic instance startup configuration. Executed in CDB$ROOT to apply settings
  each time the database instance is started.

- **10_startup_config_odbseed.sql**  
  Basic instance startup configuration for the PDB `ODBSEED`. Executed after the
  PDB is opened to apply PDB-scoped settings.

## Notes

- Scripts in this folder run after the database instance is started and the PDBs
  are opened.
- Use this folder for configuration that must persist across restarts, such as
  grants, ACL adjustments, maintenance jobs, or health checks.
- Number files sequentially (for example `20_jobs.sql`, `30_verify.sql`) to
  control execution order.
- Additional startup scripts can be added as needed to extend the OraDBA demo
  environment.
