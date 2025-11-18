# PDB Archive Directory

This folder stores PDB archive files used for restoring databases.

## Usage

- Place `.pdb` or `.zip` archives here
- Inside the container, this folder is available at `/opt/oracle/data/pdbarch`

## Example

To restore a PDB from an archive inside the container:

```sql
CREATE PLUGGABLE DATABASE ea_seed USING '/opt/oracle/data/pdbarch/pdbea23ai_seed.pdb';
ALTER PLUGGABLE DATABASE ea_seed OPEN READ WRITE;
ALTER PLUGGABLE DATABASE ea_seed SAVE STATE;
```
