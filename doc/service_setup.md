# Service Setup - Walkthrough

This document describes how to configure and start the services in the environment.
It explains the role of docker-compose, environment variables, configuration and data folders, and the individual
database containers.

## First time setup (quick start)

1. Build and start a service (example: cdbfree)

   ```bash
   docker compose --profile cdbfree up -d
   ```

1. Check logs until database is ready

   ```bash
   docker logs -f cdbfree
   ```

   Look for

   ```text
   #########################
   DATABASE IS READY TO USE!
   #########################
   ```

1. Connect via SQL\*Plus

   ```bash
   sqlplus sys@localhost:1526/FREEPDB1 as sysdba
   ```

1. Access OEM Express in browser

   ```text
   http://localhost:5506/em
   ```

## Introduction

All services are orchestrated using docker-compose.

- A base service definition (x-db-service) defines common settings for Oracle database containers
  (image, memory, environment variables, ulimits, restart policy).
- Individual services extend this base and add their own bind mounts and setup scripts.
- Data and configuration are mapped into the containers using bind mounts, keeping containers stateless and reproducible.

## Environment variables (.env)

The .env file centralizes all configuration values used by docker-compose.yml.

### Main categories

- **Runtime / Image** - image name, memory limits, shared memory, timezone.
- **Ports** - listener and OEM Express ports mapped to the host.
- **Database Basics** - initial SYS password, SID, and PDB.
- **Host Paths** - base directories for persisted database files and configs.
- **Service-Specific Overrides** - each service can define its own ports.

### Example

```ini
DB_IMAGE=container-registry.oracle.com/database/free:23.8.0.0
DB_MEM=8g
DB_SHM_SIZE=1g
TZ=Europe/Zurich

ORACLE_PWD=<Password>
ORACLE_SID=FREE
ORACLE_PDB=FREEPDB1

CDBFREE_LISTENER_PORT=1526
CDBFREE_OEM_EXPRESS_PORT=5506
LABDB_LISTENER_PORT=1527
LABDB_OEM_EXPRESS_PORT=5507
ODBREPO_LISTENER_PORT=1528
ODBREPO_OEM_EXPRESS_PORT=5508
ODBSEED_LISTENER_PORT=1529
ODBSEED_OEM_EXPRESS_PORT=5509
ODBDEMO_LISTENER_PORT=1530
ODBDEMO_OEM_EXPRESS_PORT=5510
ODBENC_LISTENER_PORT=1531
ODBENC_OEM_EXPRESS_PORT=5511
```

## Folder Layout

### config

Contains SQL and shell scripts for setup and startup of each service.
Scripts are executed inside the container during first boot (setup) and subsequent starts (startup).

### data

Persistent data directories, one per service.
Includes database files (oradata), container specific configuration (dbconfig), and logs.

```text
config/
 ├── common/
 ├── labdb/{setup,startup}
 ├── odbrepo/{setup,startup}
 ├── odbseed/{setup,startup}
 └── odbdemo/{setup,startup}

data/
 ├── cdbfree/
 ├── labdb/
 ├── odbrepo/
 ├── odbseed/
 └── odbdemo/
```

## Services

Below are the main services, their purpose, specialties, and their docker-compose definitions.

### CDBFREE

Purpose: plain Oracle 23ai Free instance
Specialty: baseline container, no additional setup scripts

```yaml
cdbfree:
  <<: *db-base
  container_name: cdbfree
  profiles: ["cdbfree"]
  volumes:
    - ${ORADATA_HOST}:/opt/oracle/oradata
    - ${COMMON_DATA_HOST}:/opt/oracle/data
    - ./config/common/scripts:/opt/oracle/scripts:ro
  ports:
    - "${CDBFREE_LISTENER_PORT}:1526"
    - "${CDBFREE_OEM_EXPRESS_PORT}:5506"
```

Access

- SQL\*Net: localhost:\${CDBFREE\_LISTENER\_PORT}
- OEM Express: [http://localhost:\${CDBFREE\_OEM\_EXPRESS\_PORT}/em](http://localhost:${CDBFREE_OEM_EXPRESS_PORT}/em)
- Shell: docker exec -it cdbfree bash

### LABDB

Purpose: clean Oracle DB for labs, engineering, and tests
Specialty: creates PDB LABPDB1, initializes audit config, users, tablespaces

```yaml
labdb:
  <<: *db-base
  container_name: labdb
  profiles: ["labdb"]
  volumes:
    - ./data/labdb:/opt/oracle/oradata
    - ./data/labdb/dbconfig:/opt/oracle/dbconfig
    - ./data/labdb/logs:/opt/oracle/scripts/logs
    - ${COMMON_DATA_HOST}:/opt/oracle/data
    - ./config/common/scripts:/opt/oracle/common/scripts:ro
    - ./config/labdb/setup:/opt/oracle/scripts/setup:ro
    - ./config/labdb/startup:/opt/oracle/scripts/startup:ro
  ports:
    - "${LABDB_LISTENER_PORT}:1527"
    - "${LABDB_OEM_EXPRESS_PORT}:5507"
```

### ODBREPO

Purpose: repository database for Enterprise Architect
Specialty: creates a PDB from archive, runs repository init scripts

```yaml
odbrepo:
  <<: *db-base
  container_name: odbrepo
  profiles: ["odbrepo"]
  volumes:
    - ./data/odbrepo:/opt/oracle/oradata
    - ./data/odbrepo/dbconfig:/opt/oracle/dbconfig
    - ./data/odbrepo/logs:/opt/oracle/scripts/logs
    - ${COMMON_DATA_HOST}:/opt/oracle/data
    - ./config/common/scripts:/opt/oracle/common/scripts:ro
    - ./config/odbrepo/setup:/opt/oracle/scripts/setup:ro
    - ./config/odbrepo/startup:/opt/oracle/scripts/startup:ro
  ports:
    - "${ODBREPO_LISTENER_PORT}:1528"
    - "${ODBREPO_OEM_EXPRESS_PORT}:5508"
```

### ODBSEED

Purpose: seed database created from archive
Specialty: provides baseline EA PDB archive for cloning

```yaml
odbseed:
  <<: *db-base
  container_name: odbseed
  profiles: ["odbseed"]
  volumes:
    - ./data/odbseed:/opt/oracle/oradata
    - ./data/odbseed/dbconfig:/opt/oracle/dbconfig
    - ./data/odbseed/logs:/opt/oracle/scripts/logs
    - ${COMMON_DATA_HOST}:/opt/oracle/data
    - ./config/common/scripts:/opt/oracle/common/scripts:ro
    - ./config/odbseed/setup:/opt/oracle/scripts/setup:ro
    - ./config/odbseed/startup:/opt/oracle/scripts/startup:ro
  ports:
    - "${ODBSEED_LISTENER_PORT}:1529"
    - "${ODBSEED_OEM_EXPRESS_PORT}:5509"
```

### ODBDEMO

Purpose: full-featured demo environment for Enterprise Architect
Specialty: drops FREEPDB1, creates and configures ODBDEMO PDB, loads schema and data, then clones into ODBSEED

```yaml
odbdemo:
  <<: *db-base
  container_name: odbdemo
  profiles: ["odbdemo"]
  volumes:
    - ./data/odbdemo:/opt/oracle/oradata
    - ./data/odbdemo/dbconfig:/opt/oracle/dbconfig
    - ./data/odbdemo/logs:/opt/oracle/scripts/logs
    - ${COMMON_DATA_HOST}:/opt/oracle/data
    - ./config/common/scripts:/opt/oracle/common/scripts:ro
    - ./config/odbdemo/setup:/opt/oracle/scripts/setup:ro
    - ./config/odbdemo/startup:/opt/oracle/scripts/startup:ro
  ports:
    - "${ODBDEMO_LISTENER_PORT}:1530"
    - "${ODBDEMO_OEM_EXPRESS_PORT}:5510"
```

### ODBENC

Purpose: full-featured demo environment for Enterprise Architect
Specialty: drops FREEPDB1, creates and configures ODBENC PDB, loads schema and data and configure TDE.

```yaml
odbenc:
  <<: *db-base
  container_name: odbenc
  profiles: ["odbenc"]
  volumes:
    - ./data/odbenc:/opt/oracle/oradata
    - ./data/odbenc/dbconfig:/opt/oracle/dbconfig
    - ./data/odbenc/logs:/opt/oracle/scripts/logs
    - ${COMMON_DATA_HOST}:/opt/oracle/data
    - ./config/common/scripts:/opt/oracle/common/scripts:ro
    - ./config/odbenc/setup:/opt/oracle/scripts/setup:ro
    - ./config/odbenc/startup:/opt/oracle/scripts/startup:ro
  ports:
    - "${ODBENC_LISTENER_PORT}:1531"
    - "${ODBENC_OEM_EXPRESS_PORT}:5511"
```

## Starting and verifying a service

Start a single service

```bash
docker compose --profile labdb up -d
```

Start multiple services

```bash
docker compose --profile labdb --profile odbrepo up -d
```

Check logs

```bash
docker compose --profile labdb logs -f
```

Wait until you see

```text
#########################
DATABASE IS READY TO USE!
#########################
```

Verify connectivity

- SQL\*Plus

  ```bash
  sqlplus sys@localhost:1527/LABPDB1 as sysdba
  ```

- OEM Express

  ```text
  http://localhost:5507/em
  ```

- Container shell

  ```bash
  docker exec -it labdb bash
  ```

### Example setup

For `cdbfree`:

```bash
docker compose --profile cdbfree up -d
docker compose --profile cdbfree logs -f
```

For `labdb`:

```bash
docker compose --profile labdb up -d
docker compose --profile labdb logs -f
```

For `odbdemo`:

```bash
docker compose --profile odbdemo up -d
docker compose --profile odbdemo logs -f
```

For `odbseed`:

```bash
docker compose --profile odbseed up -d
docker compose --profile odbseed logs -f
```

For `odbrepo`:

```bash
docker compose --profile odbrepo up -d
docker compose --profile odbrepo logs -f
```

For `odbenc`:

```bash
docker compose --profile odbenc up -d
docker compose --profile odbenc logs -f
```

## Links

- [Setup Lab Environment](setup_lab_environment.md)
- [Demo and Engineering Overlays](demo_overlay.md)
- [Interactive Shell Access](interactive_shell.md)
- [SQL Access](sql_developer.md)
- [Troubleshooting](troubleshooting.md)
