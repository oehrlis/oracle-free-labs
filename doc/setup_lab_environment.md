# Setup Lab Environment

This guide explains how to set up the Oracle AI Database Free 26ai Lab Environment using Docker or Podman.  
The environment provides containerized services for Oracle AI Database Free 26ai and preconfigured OraDBA Lab repositories to support testing, training, and engineering scenarios.

## Quickstart

If you want the fast path, copy and run the following block. It clones the repo, prepares environment variables, and starts the default profile with Docker.  
For Podman, replace `docker compose` with `podman-compose` or alias `docker=podman`.

```bash
# 1) Clone
git clone https://github.com/<your-org>/oracle-free-labs.git
cd oracle-free-labs

# 2) Environment
cp .env.example .env
# edit .env to set ORACLE_PWD, ports, image tag, etc.

# 3) Place PDB archives if using ODBSEED/ODBREPO services
# host path -> config/common/data/pdbarch
# they mount inside the container at /opt/oracle/data/pdbarch
# required files:
#   pdb26ai_odbseed.pdb
#   pdb26ai_odbrepo.pdb

# 4) Start one profile, e.g. plain Oracle Free
docker compose --profile cdbfree up -d

# or start another profile
# docker compose --profile labdb up -d
# docker compose --profile odbseed up -d
# docker compose --profile odbrepo up -d
# docker compose --profile odbdemo up -d
# docker compose --profile odbenc up -d

# 5) Check containers
docker ps

# 6) Optionally set core passwords (SYS, SYSTEM, PDBADMIN)
podman exec cdbfree ./setPassword.sh <your_password>
```

## Prerequisites

- Git installed to clone the repository.
- Docker or Podman installed and configured.
- Sufficient local resources:

  - Minimum 8 GB RAM.
  - Minimum 20 GB free disk space.
- Oracle AI Database container image pulled locally
  See Oracle AI Database 26ai Free Container Image Documentation for details on Oracle‑specific configuration and scripts.
- Optional PDB archives if you want preconfigured OraDBA scripts:

  - `pdb26ai_odbseed.pdb`
  - `pdb26ai_odbrepo.pdb`
    Place these on the host under `config/common/data/pdbarch`. They are mounted into the container at `/opt/oracle/data/pdbarch/`.

## Clone the repository

```bash
git clone https://github.com/<your-org>/oracle-free-labs.git
cd oracle-free-labs
```

## Configure environment

1. Copy the example environment file.

   ```bash
   cp .env.example .env
   ```

2. Edit `.env` to adjust key settings.

  - `ORACLE_PWD` password for SYS, SYSTEM, PDBADMIN
  - `ORACLE_SID` container database SID, default `FREE`
  - `ORACLE_PDB` default PDB, e.g. `FREEDB1`, `LABPDB1`, `ODBSEED`, `ODBREPO`, `ODBDEMO`
  - `ENABLE_ARCHIVELOG` enable or disable ARCHIVELOG mode

You can also set or reset core account passwords later.

```bash
docker exec cdbfree ./setPassword.sh <your_password>
```

## Start the environment

### Using Docker Compose

```bash
docker compose --profile cdbfree up -d
```

Check logs until you see the ready message:

```text
#########################
DATABASE IS READY TO USE!
#########################
```

### Using Podman Compose

```bash
podman-compose --profile cdbfree up -d
```

Replace `cdbfree` with `labdb`, `odbseed`, `odbrepo`, `odbdemo` or `odbenc` to start other scenarios.

## Verify setup

Check running containers.

```bash
docker ps
# or
podman ps
```

## Ports

Ports are preconfigured in the `.env` file. Each service uses its own dedicated listener and OEM Express port.

| Service | Listener Port | OEM Express Port |
|---------|---------------|------------------|
| cdbfree | 1526          | 5506             |
| labdb   | 1527          | 5507             |
| odbrepo | 1528          | 5508             |
| odbseed | 1529          | 5509             |
| odbdemo | 1530          | 5510             |
| odbenc  | 1531          | 5511             |

## Requirements

- Docker Engine or Podman installed on your host
- docker-compose plugin or podman-compose
- Git client to clone the repository
- At least 8 GB RAM and 20 GB disk free
- Optional: PDB archive zip files if you want to use ODBDEMO, ODBSEED, or ODBREPO

## Steps

- Clone this repository
- Copy `.env.example` to `.env` and edit as needed
- Adjust ports if you run multiple services in parallel
- Place PDB archives in `config/common/data` if required
- Start the service profile with docker-compose
- Verify logs and connect with SQL\*Plus or SQL Developer

## Tips

- Use [Service Setup](service_setup.md) for detailed explanation of profiles and mounts
- Passwords for SYS, SYSTEM, and PDBADMIN can be set later with [Reset Passwords](reset_passwords.md)
- For GUI access, see [SQL Access](sql_developer.md)
- For shell access inside a container, see [Interactive Shell Access](interactive_shell.md)

## Links

- [Service Setup](service_setup.md)
- [Interactive Shell Access](interactive_shell.md)
- [SQL Access](sql_developer.md)
- [Reset Passwords](reset_passwords.md)
- [Troubleshooting](troubleshooting.md)
