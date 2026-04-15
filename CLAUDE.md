# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Container-based lab environment for **Oracle AI Database 26ai Free** using Docker Compose. Provides six independent services, each representing a different Oracle database configuration for labs and training. See `docker-compose.yml` and `.env.example` for full configuration.

## Service Management

Copy `.env.example` to `.env` and adjust before first use. Each service runs independently via Docker Compose profiles:

```bash
# Start a service (each binds its own ports, can run concurrently)
docker compose --profile labdb up -d
docker compose --profile odbrepo up -d

# Stop a service
docker compose --profile labdb down

# Follow logs during setup (first start runs setup scripts, may take several minutes)
docker compose --profile labdb logs -f

# Full reset of a service (destroys all data)
docker compose --profile labdb down -v && rm -rf data/labdb/
```

## Services Overview

| Service | Profile | Listener | OEM Express | Description |
|---------|---------|----------|-------------|-------------|
| `cdbfree` | `cdbfree` | 1526 | 5506 | Plain Oracle 26ai Free, common scripts only |
| `labdb` | `labdb` | 1527 | 5507 | Empty DB for labs, full setup/startup scripts |
| `odbrepo` | `odbrepo` | 1528 | 5508 | EA repository created via SQL scripts |
| `odbseed` | `odbseed` | 1529 | 5509 | EA repository from PDB archive |
| `odbdemo` | `odbdemo` | 1530 | 5511 | Complex EA demo from PDB archive |
| `odbenc` | `odbenc` | 1531 | 5511 | EA demo with TDE via SQL scripts |

## Architecture

### Script Execution Pattern

Each service (except `cdbfree`) has two script phases mounted read-only into the container:

- **Setup** (`config/<service>/setup/`) - runs once on first container start, alphabetical order
- **Startup** (`config/<service>/startup/`) - runs on every container start after DB opens

Scripts use numeric prefixes to control execution order (`00_`, `10_`, `20_`). Shared utilities live in `config/common/scripts/` (mounted to `/opt/oracle/common/scripts` in every service except `cdbfree`).

### SQL Script Conventions

- Begin/end with `@/opt/oracle/common/scripts/define_logging_begin.sql` / `define_logging_end.sql`
- Use `WHENEVER SQLERROR EXIT` for fail-fast behavior in automated runs
- Logs spool to `/opt/oracle/scripts/logs/` (writable bind mount per service at `data/<service>/logs/`)
- Call shared utilities via `@/opt/oracle/common/scripts/<script>.sql PARAM1 PARAM2`

### Key Shared Utilities (`config/common/scripts/`)

- `create_pdb.sql` - create PDB from `PPDB$SEED`
- `create_pdb_from_archive.sql` - restore PDB from `.pdb` archive
- `clone_pdb.sql` - clone an existing PDB
- `create_audit_policies.sql` - standardized audit framework
- `csenc_master.sql` / `csenc_swkeystore.sql` - TDE master key and software keystore
- `create_scott.sql` / `create_tvd_hr.sql` - demo schemas (SCOTT, HR)

### Data Persistence

All persistent Oracle files live under `data/` (gitignored). PDB archive files (`.pdb`) used by `odbseed`/`odbdemo` go in `config/common/data/pdbarch/` (tracked in git).

## Documentation

Markdown sources in `doc/`, output PDFs in `artefacts/`. Generate a PDF (requires Docker and `oehrlis/pandoc` image):

```bash
make doc docname=<docname>
# or directly:
scripts/generate_pdf.sh <docname>
# Reads:  doc/<docname>.md + doc/<docname>.yml
# Writes: artefacts/<docname>.pdf
```

## Lint

```bash
markdownlint doc/
```

## Secrets

Secrets exclusively via 1Password: `op read "op://vault/item/field"`. Never in `.env`, git, or comments.

## Rules (always active)

@.claude/rules/shell.md
@.claude/rules/markdown-lint.md

## Skills (load on demand)

- Shell scripts & headers  ->  /bash-header
- Oracle TDE               ->  /oracle-tde
- Oracle Audit             ->  /oracle-audit
- Oracle Auth              ->  /oracle-auth
- Oracle Data Safe         ->  /oracle-datasafe
