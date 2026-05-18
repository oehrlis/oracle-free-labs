# Demo and Engineering Overlays

This guide explains how to extend the Oracle Free lab environment with demo- or
engineering-specific configuration from a **separate repository** (e.g. a talks repo)
without modifying the core lab files.

## Concept

The `oracle-free-labs` repository provides the core infrastructure: six database
services, shared scripts, and startup automation. Demo content, talks scripts,
and engineering-specific configuration belong in their own repositories and are
layered on top using Docker Compose's native **override mechanism**.

```text
oracle-free-labs/          <- core infra (this repo)
  docker-compose.yml
  docker-compose.override.yml   <- gitignored, provided by the demo/talks repo

talks/                     <- your demo/talks repo (separate)
  demos/
    nf26ai-security/
      docker-compose.override.yml   <- activates the demo overlay
      scripts/                      <- SQL and shell scripts for the demo
      README.md                     <- "run make up SERVICE=labdb, then ..."
```

## How Docker Compose Override Works

Docker Compose automatically merges `docker-compose.override.yml` with
`docker-compose.yml` when it is present in the same directory. No extra flags are needed.

Only the keys you define in the override are changed or added. Everything else
(image, ports, volumes, restart policy, environment) is inherited from the base
compose file.

```bash
# With override present, these two commands are equivalent:
docker compose --profile labdb up -d
docker compose -f docker-compose.yml -f docker-compose.override.yml --profile labdb up -d
```

## Activating an Overlay

Copy or symlink the override file from your demo repo into the `oracle-free-labs`
directory:

```bash
cd oracle-free-labs/

# Option A: symlink (preferred - changes in the talks repo apply immediately)
ln -sf ../talks/demos/nf26ai-security/docker-compose.override.yml .

# Option B: copy (isolated snapshot)
cp ../talks/demos/nf26ai-security/docker-compose.override.yml .
```

Then start the service as usual:

```bash
make up SERVICE=labdb
# or
docker compose --profile labdb up -d
```

To deactivate the overlay, remove the file:

```bash
rm docker-compose.override.yml
```

## Writing an Override File

The `docker-compose.override.yml.example` in the repo root documents all common
patterns. Below are the most useful ones.

### Pattern 1 - Mount demo scripts read-only

Makes demo scripts available inside the container at `/opt/oracle/custom`.
Scripts are **not** auto-executed; run them manually after the DB is up.

```yaml
services:
  labdb:
    volumes:
      - ../talks/demos/nf26ai-security/scripts:/opt/oracle/custom:ro
```

Run a script from inside the container:

```bash
make bash SERVICE=labdb
# inside the container:
sqlplus / as sysdba @/opt/oracle/custom/01_setup_demo.sql
```

### Pattern 2 - Custom tnsnames and sqlnet

Mount a custom tnsnames directory from the demo repo. `TNS_ADMIN` is already
set to `/opt/oracle/network/admin` for all named services; the override replaces
the target of that path.

```yaml
services:
  labdb:
    volumes:
      - ../talks/demos/nf26ai-security/tns:/opt/oracle/network/admin:ro
```

Verify inside the container:

```bash
make bash SERVICE=labdb
# inside the container:
tnsping labpdb1
```

### Pattern 3 - Extra environment variables

Pass demo-specific settings that scripts can read via shell or SQL.

```yaml
services:
  labdb:
    environment:
      - TZ=${TZ}
      - ORACLE_PWD=${ORACLE_PWD}
      - ORACLE_SID=${ORACLE_SID:-FREE}
      - ORACLE_PDB=${ORACLE_PDB}
      - TNS_ADMIN=/opt/oracle/network/admin
      - DEMO_NAME=NF26ai-Security
      - DEMO_EDITION=2026
```

> Note: when overriding `environment`, you must repeat the full base variable list
> (`TZ`, `ORACLE_PWD`, `ORACLE_SID`, `ORACLE_PDB`, `TNS_ADMIN`) because the override
> replaces the entire environment block inherited from the base anchor.

### Pattern 4 - Version-specific Oracle Free image

Build a specific version first, then activate it for one service only:

```bash
make build DB_BASE_IMAGE=container-registry.oracle.com/database/free:23.7.0.0
# produces: oracle-free-labs:23.7.0.0
```

Override the image in the compose override:

```yaml
services:
  labdb:
    image: oracle-free-labs:23.7.0.0
```

### Pattern 5 - Combined demo setup

Mount scripts, set extra env vars, and provide a custom tnsnames in one overlay:

```yaml
services:
  labdb:
    volumes:
      - ../talks/demos/nf26ai-security/scripts:/opt/oracle/custom:ro
      - ../talks/demos/nf26ai-security/tns:/opt/oracle/network/admin:ro
    environment:
      - TZ=${TZ}
      - ORACLE_PWD=${ORACLE_PWD}
      - ORACLE_SID=${ORACLE_SID:-FREE}
      - ORACLE_PDB=${ORACLE_PDB}
      - TNS_ADMIN=/opt/oracle/network/admin
      - DEMO_NAME=NF26ai-Security
```

## TNS_ADMIN and Network Configuration

For all named services (`labdb`, `odbrepo`, `odbseed`, `odbdemo`, `odbenc`),
the environment variable `TNS_ADMIN` is set to `/opt/oracle/network/admin`, which
resolves via a symlink to `/opt/oracle/dbconfig/FREE/`. This directory is
bind-mounted to `data/<service>/dbconfig/FREE/` on the host and persists across
container restarts.

Default files present after first start:

```text
data/<service>/dbconfig/FREE/
├── listener.ora
├── sqlnet.ora
├── tnsnames.ora
└── wallet/           <- redirected from /opt/oracle/admin/FREE/wallet
```

To inspect or edit from the host:

```bash
cat data/labdb/dbconfig/FREE/tnsnames.ora
```

## Wallet Persistence

The startup script `config/common/scripts/setup_network_wallet.sh` runs on every
container start for all named services. It redirects the Oracle wallet directory
from `/opt/oracle/admin/FREE/wallet` (not bind-mounted) to
`/opt/oracle/dbconfig/FREE/wallet` (bind-mounted, persistent).

After configuring TDE or adding a wallet, the wallet files are stored in:

```text
data/<service>/dbconfig/FREE/wallet/
```

This directory is not lost on `docker compose down` or container recreation - only
a full `make reset SERVICE=<name>` removes it.

## Suggested Talks Repo Structure

```text
talks/
└── demos/
    └── nf26ai-security/
        ├── README.md                        <- demo runbook
        ├── docker-compose.override.yml      <- symlink into oracle-free-labs/
        ├── scripts/
        │   ├── 01_setup_demo.sql
        │   ├── 02_verify_demo.sql
        │   └── 99_cleanup_demo.sql
        └── tns/
            ├── tnsnames.ora
            └── sqlnet.ora
```

The demo `README.md` should document the full workflow:

```markdown
## Setup

1. Clone and start the lab:

       cd oracle-free-labs
       ln -sf ../talks/demos/nf26ai-security/docker-compose.override.yml .
       make up SERVICE=labdb

2. Wait until the DB is ready:

       make logs SERVICE=labdb

3. Run the demo setup:

       make bash SERVICE=labdb
       # inside container:
       sqlplus / as sysdba @/opt/oracle/custom/01_setup_demo.sql

## Cleanup

       sqlplus / as sysdba @/opt/oracle/custom/99_cleanup_demo.sql
       # or full reset:
       make reset SERVICE=labdb
```

## Links

- [Setup Lab Environment](setup_lab_environment.md)
- [Service Setup](service_setup.md)
- [Interactive Shell Access](interactive_shell.md)
- [Troubleshooting](troubleshooting.md)
