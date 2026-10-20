# Common Data

Shared data artifacts used across multiple services.

## Structure

- **dpdump/**  
  Oracle Data Pump export and import files

- **pdbarch/**  
  PDB archive files used for restoring databases

- **dbsat/**  
  Place the Oracle DBSAT zip here (not shipped, Oracle license). Used by
  `make dbsat-seclab`, see [dbsat/README.md](dbsat/README.md)

- **ciscat/**  
  Place the CIS-CAT Lite or Pro zip here (not shipped, CIS license). Used by
  `make ciscat`, see [ciscat/README.md](ciscat/README.md)

## Notes

- This folder is mounted once into the container at `/opt/oracle/data`
- Avoid committing large dump or archive files to Git
