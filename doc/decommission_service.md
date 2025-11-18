# Decommission a Container

This guide explains how to stop and remove a container service and clean up its persistent data.  
Use this when you no longer need a service or want to start fresh with a clean setup.

## Overview

Each service stores persistent data under `data/<service>`.  
Decommissioning involves three steps:

- Stop the running container  
- Remove the container definition  
- Clean up the persistent data below `data/<service>`  

## Stop and remove a container

### Docker

Stop and remove the service:

```bash
docker compose --profile labdb down
````

### Podman

```bash
podman compose --profile labdb down
```

This stops the container and removes it from the runtime.
Configuration and data files remain on disk.

## Clean up persistent data

When decommissioning a service, remove the following under `data/<service>`:

- the marker file `.FREE.created`
- the marker file `FREE/.FREE.created`
- the entire contents of the `FREE/` subdirectory (database files)
- the entire contents of the `dbconfig/` subdirectory
- the entire contents of the `logs/` subdirectory

It is fine if `.gitkeep` is also removed — it only exists to keep directories under version control.
Creating a container with a different ORACLE\_SID is currently not supported. The default is always `FREE`.

### Example cleanup

For `cdbfree`:

```bash
docker compose --profile cdbfree down
rm -f ./data/cdbfree/.FREE.created
rm -f ./data/cdbfree/FREE/.FREE.created
rm -rf ./data/cdbfree/FREE/*
rm -rf ./data/cdbfree/dbconfig/*
rm -rf ./data/cdbfree/logs/*
```

For `labdb`:

```bash
docker compose --profile labdb down
rm -f ./data/labdb/.FREE.created
rm -f ./data/labdb/FREE/.FREE.created
rm -rf ./data/labdb/FREE/*
rm -rf ./data/labdb/dbconfig/*
rm -rf ./data/labdb/logs/*
```

```bash
docker compose --profile odbdemo down
rm -f ./data/odbdemo/.FREE.created
rm -f ./data/odbdemo/FREE/.FREE.created
rm -rf ./data/odbdemo/FREE/*
rm -rf ./data/odbdemo/dbconfig/*
rm -rf ./data/odbdemo/logs/*
mv config/common/data/pdbarch/pdb26ai_odbseed.pdb \
config/common/data/pdbarch/pdb26ai_odbseed.$(date '+%d%m%y-%H%M%S').pdb
```

For `odbseed`:

```bash
docker compose --profile odbseed down
rm -f ./data/odbseed/.FREE.created
rm -f ./data/odbseed/FREE/.FREE.created
rm -rf ./data/odbseed/FREE/*
rm -rf ./data/odbseed/dbconfig/*
rm -rf ./data/odbseed/logs/*
```

For `odbrepo`:

```bash
docker compose --profile odbrepo down
rm -f ./data/odbrepo/.FREE.created
rm -f ./data/odbrepo/FREE/.FREE.created
rm -rf ./data/odbrepo/FREE/*
rm -rf ./data/odbrepo/dbconfig/*
rm -rf ./data/odbrepo/logs/*
```

For `odbenc`:

```bash
docker compose --profile odbenc down
rm -f ./data/odbenc/.FREE.created
rm -f ./data/odbenc/FREE/.FREE.created
rm -rf ./data/odbenc/FREE/*
rm -rf ./data/odbenc/dbconfig/*
rm -rf ./data/odbenc/logs/*
```

## Notes

- Use caution: removing files under `data/<service>` permanently deletes the database and cannot be undone
- If you want to keep the data for later use, back up the directory first
- After cleanup you can restart the service and it will be re-created fresh
- ORACLE\_SID is fixed to FREE in this environment, and other values are not supported

## Links

- [Service Setup](service_setup.md)
- [Miscellaneous DBA Tasks](misc_dba_tasks.md)
- [Troubleshooting](troubleshooting.md)
