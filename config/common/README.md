# Common Configuration

This folder contains assets that are shared across all services.

## Structure

- **scripts/**  
  Shared SQL or shell scripts mounted into all services.

- **data/**  
  Shared data artifacts such as Data Pump exports and PDB archives.

## Notes

- Use `scripts/` for helper routines or utilities that should be available in all services.
- Use `data/` for shared database artifacts.
- Avoid placing large binary files under Git. Add rules to `.gitignore` as needed.
