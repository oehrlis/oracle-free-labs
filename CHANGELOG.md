# Changelog

All notable changes to this project are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/);
versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Removed

- `docker-publish.yml` GitHub Actions workflow - publishing the Oracle Free
  image is not permitted; removed to prevent accidental pushes to GHCR

### Added

- `reset-cdbfree` target (was missing from per-service targets)

### Changed

- All "EA" references (Enterprise Architect / EA Sparx) replaced with "OraDBA demo"
  throughout `README.md`, `CLAUDE.md`, `docker-compose.yml`, `Makefile`, all
  `config/*/setup/README.md` and `config/*/startup/README.md` files, and three
  SQL setup scripts in `config/odbdemo/` and `config/odbenc/`
- `make down` without `SERVICE`: stops all six services sequentially
- `make reset` without `SERVICE`: resets all six services with a single
  confirmation prompt (destructive - removes containers, volumes, and `data/`)
- Help output reorganized: each service (`cdbfree`, `labdb`, `odbrepo`,
  `odbseed`, `odbdemo`, `odbenc`) has its own labeled section

## [1.0.0] - 2026-04-15

### Added

- `Makefile` with targets for all six services (`up-*`, `down-*`, `logs-*`,
  `bash-*`, `sql-*`, `reset-*`), generic `make up SERVICE=<name>`, build,
  lint, version-bump, and release targets
- `build/Dockerfile` to extend `container-registry.oracle.com/database/free`
  with oradba tools, rlwrap and less; selectable via `DB_IMAGE` in `.env`
- `build/.dockerignore` for clean build context
- `VERSION` file (`1.0.0`)
- `CHANGELOG.md` (this file)
- `CONTRIBUTING.md`
- `scripts/bump_version.sh` for semantic version management

### Changed

- `bin/` renamed to `scripts/` for consistency with other OraDBA repos
- `ORACLE_SID` renamed to `DB_ORACLE_SID` in `.env.example` and
  `docker-compose.yml` to avoid conflict when oraenv/oradba sets
  `ORACLE_SID` in the shell environment (Docker Compose v2 gives shell
  env higher priority than `.env` file values)
- `.env.example`: reference URL corrected, `DB_IMAGE` comment extended
  with pure vs. extended image options, `ODBENC_OEM_EXPRESS_PORT` fixed
  to `5512` (was duplicate `5511`)
- `scripts/generate_pdf.sh`: hardened to `set -euo pipefail`, header updated
- `scripts/template.sh`: hardened to `set -euo pipefail`
- `README.md`: `bin/` references updated to `scripts/`, Makefile usage added,
  `build/` directory added to structure overview
- `CLAUDE.md`: `bin/` references updated to `scripts/`

### Fixed

- Stray file `docker-compose copy.yml` removed
- Empty `bin/data/odbenc/logs/` directory removed (wrongly created under `bin/`)

## [0.5.0] - 2025-11-20

### Added

- `odbenc` service: Oracle Free with TDE via SQL scripts (`csenc_master.sql`,
  `csenc_swkeystore.sql`, `encrypt_ts_users.sql`)
- Master encryption key and software keystore setup for PDB
- User scripts for table space encryption
- TDE audit and info scripts (`ssenc_info.sql`, `idenc_tde.sql`, `idenc_wroot.sql`)

### Changed

- Lab scripts adjusted for automation (setup/startup ordering)
- SQL comments updated across multiple scripts

## [0.4.0] - 2025-11-19

### Added

- `odbdemo` service: complex OraDBA demo from PDB archive
- `odbseed` service: minimal OraDBA demo from PDB archive
- Unified audit policy scripts (`create_audit_policies.sql`,
  `enable_audit_policies.sql`, `init_audit_config.sql`)
- TDE wallet scripts (`define_wallet_pwd.sql`, `define_wallet_root_base.sql`)
- Post-clone tasks for audit and datafiles

## [0.3.0] - 2025-11-18

### Added

- `odbrepo` service: OraDBA demo created via SQL scripts
- `config/common/scripts/` shared utilities:
  `create_pdb.sql`, `create_pdb_from_archive.sql`, `clone_pdb.sql`,
  `create_scott.sql`, `create_tvd_hr.sql`, `lock_all_users.sql`
- PDB archive support (`config/common/data/pdbarch/`)
- `install_oradba_init.sh` for post-start oradba/BasEnv installation
- Service-specific setup/startup script directories for all services

### Changed

- Services renamed from `tvd`-prefix to `odb`-prefix
- Docker Compose restructured with x-db-service base anchor

## [0.2.0] - 2025-11-14

### Added

- `labdb` service: empty Oracle Free DB for labs and tests
- `cdbfree` service: plain Oracle Free base instance
- Six-service Docker Compose profile structure
- `.gitignore` with rules for `data/`, `*.log`, OS and editor artifacts
- `config/common/scripts/` mount for shared SQL utilities

## [0.1.0] - 2025-11-14

### Added

- Initial project structure: `config/`, `data/`, `doc/`, `bin/`
- `docker-compose.yml` with profile-based service isolation
- `.env.example` with port mappings and database defaults
- Apache License 2.0

<!-- markdownlint-disable MD013 -->
[1.0.0]: https://github.com/oehrlis/oracle-free-labs/compare/v0.5.0...v1.0.0
[0.5.0]: https://github.com/oehrlis/oracle-free-labs/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/oehrlis/oracle-free-labs/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/oehrlis/oracle-free-labs/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/oehrlis/oracle-free-labs/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/oehrlis/oracle-free-labs/releases/tag/v0.1.0
<!-- markdownlint-enable MD013 -->
