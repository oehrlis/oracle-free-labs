# Common Data

Shared data artifacts used across multiple services.

## Structure

- **dpdump/**  
  Oracle Data Pump export and import files

- **pdbarch/**  
  PDB archive files used for restoring databases

## Notes

- This folder is mounted once into the container at `/opt/oracle/data`
- Avoid committing large dump or archive files to Git
