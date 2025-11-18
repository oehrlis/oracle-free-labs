# Data Pump Directory

This folder stores Oracle Data Pump exports and imports.

## Usage

- Place `.dmp` and `.log` files here
- Inside the container, this folder is available at `/opt/oracle/data/dpdump`

## Example

Export a schema from inside the container:

```sql
expdp system/password@FREEPDB1 schemas=EA_USER directory=COMMON_DATA dumpfile=ea_user%U.dmp logfile=ea_user.log
```
