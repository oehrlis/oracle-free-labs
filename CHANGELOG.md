# Changelog

All notable changes to this project are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/);
versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `doc/tde-clone-independence.md`: five-tier model for cryptographic independence of a
  clone, with the measured evidence and the failed paths per tier.
- `doc/tde-okv-argumentation.md`: attack surfaces split into real and hypothetical, and
  the argumentation for external key management against the two customer objections.
- `scripts/tde-verify/tests/` plus `run_all.sh`: one standalone script per test case and
  a runner that composes them with gates, `--only`, `--from`, `--to`, `--list` and
  `--dry-run`.
- `config/common/scripts/ssenc_keyproof.sql`, `csenc_canary.sql`, `ssenc_canary.sql`,
  `ssenc_filehdr.sql`: key chain evidence, canary data with its physical block range,
  read-back for the key withdrawal test, and Oracle's own file header dump.
- `scripts/tde-verify/block_fingerprint.py`: block level ciphertext fingerprinting,
  comparison, clear-text scan, hex needle search and block hexdump.
- `odbencprod` / `odbencdev` services (ports 1532 / 1533) plus
  `config/odbencprod/` and `config/odbencdev/`: two-container lab for the TDE
  restore verification test. No OEM Express port is mapped and the memory limit
  is 3g per service so both can run in parallel on an 8 GB Docker VM.
- Shared exchange mount `data/xchange` at `/opt/oracle/xchange` for RMAN backup
  sets, wallet copies and evidence sets.
- `scripts/tde-verify/block_fingerprint.py`: block level ciphertext
  fingerprinting, comparison, clear-text scan, hex needle search and block
  hexdump for datafile header analysis.
- `scripts/tde-verify/tde_evidence.sh`: collects and compares labelled evidence
  sets (V$ key chain snapshots plus per-datafile fingerprints and a manifest).
- `scripts/tde-verify/tde_clone.sh`: runs one clone variant of the test
  (plain RESTORE, RESTORE AS ENCRYPTED USING KEY with and without the source
  master key, DUPLICATE AS ENCRYPTED).
- `config/common/scripts/ssenc_keyproof.sql`: key chain evidence snapshot
  including `MASTERKEYID`, `ENCRYPTEDKEY`, `KEY_VERSION` and `ORIGIN`, which
  `ssenc_info.sql` does not report.
- `config/common/scripts/csenc_canary.sql` / `ssenc_canary.sql`: canary table
  with a known clear-text marker and its physical block range, plus the read
  back used for the master key withdrawal test.
- `config/common/scripts/ssenc_filehdr.sql`: Oracle side `file_hdrs` and block
  dump as a second source next to the host side analysis.
- `doc/tde-restore-as-encrypted.md`: test protocol.
- `doc/tde-key-architecture.md`: Mermaid diagrams of the key hierarchy, measured
  against the lab rather than drawn illustratively.

### Changed

- `doc/tde-key-architecture.md`: rewritten around the measured dependency model between
  master key, database key and tablespace key, with eight Mermaid diagrams.

### Fixed

- `config/common/scripts/csenc_swkeystore.sql`: the conditional backup of
  `wallet_pwd.txt` spanned three lines with backslash continuation, which SQL*Plus does
  not support for `HOST`. The container then reported `DATABASE SETUP WAS NOT SUCCESSFUL`
  although the keystore had been created correctly.
- `data/<service>/dbconfig/FREE/`: added the `.gitkeep` markers the image needs, so a
  fresh clone no longer aborts with DBT-60127.
- `.gitignore`: the `data/` rules are now deny by default. The previous pattern set left
  RMAN backup pieces, keystores and `wallet_pwd.txt` eligible for tracking.
- `Makefile` `reset` target: restores the whole tracked path instead of only `README.md`,
  and says so when there is nothing to restore.
- `config/odbencdev/setup/`: the default pluggable database is no longer dropped. The
  entrypoint health check requires one open user PDB, so the container reported a setup
  failure on a database that was fully functional.
- `scripts/tde-verify/tde_evidence.sh`: `--compare` pairs single-datafile evidence sets
  across a datafile rename instead of reporting nothing compared, which is what
  `ONLINE REKEY` and a rebuilt lab cause.
- `config/common/scripts/csenc_swkeystore.sql`: the conditional backup of
  `wallet_pwd.txt` was written as a `HOST` command spanning three lines with
  backslash continuation. SQL*Plus does not support that, so `/bin/sh` received a
  truncated `if` and failed, after which SQL*Plus tried to execute the remaining
  shell lines and reported SP2-0734 / SP2-0042. The container entrypoint then
  printed `DATABASE SETUP WAS NOT SUCCESSFUL` even though the keystore had been
  created correctly. Now a single line.
- `data/<service>/dbconfig/FREE/`: added `.gitkeep` files and the matching
  `.gitignore` exceptions. The image symlinks `/opt/oracle/network/admin`
  (`TNS_ADMIN`) to `/opt/oracle/dbconfig/FREE`; without that directory the bind
  mount created an empty `dbconfig`, the symlink dangled and DBCA aborted with
  DBT-60127 on a fresh clone.

## [1.1.1] - 2026-05-18

### Added

- `data/cdbfree/README.md`, `data/labdb/README.md`, `data/odbenc/README.md`: added
  missing per-service README files explaining folder purpose and structure

### Fixed

- `data/odbseed/README.md`, `data/odbrepo/README.md`, `data/odbdemo/README.md`:
  restored accidentally deleted per-service README files
- `Makefile` `reset` target: now restores `README.md` via `git restore` after
  wiping `data/<service>/` so README files survive a full or per-service reset

## [1.1.0] - 2026-05-18

### Added

- `docker-compose.override.yml.example`: template for demo- and engineering-specific
  configuration without modifying core compose files; documents patterns for custom
  script mounts, tnsnames, wallet redirect, and version-specific images
- `config/common/scripts/setup_network_wallet.sh`: idempotent startup script that
  redirects the Oracle wallet to `dbconfig/FREE/wallet/` (bind-mounted, persistent)
  and validates the `network/admin` symlink; skips silently for `cdbfree`
- `config/<service>/startup/01_setup_network_wallet.sh` for all five named services
  (`labdb`, `odbrepo`, `odbseed`, `odbdemo`, `odbenc`): wrapper that calls the common
  setup script on every container start

### Documentation

- `doc/demo_overlay.md`: new guide for the demo/engineering overlay workflow;
  covers the docker-compose.override.yml mechanism, five override patterns
  (script mount, custom tnsnames, extra env vars, version-specific image, combined),
  TNS_ADMIN and wallet persistence context, and a suggested talks repo structure
  with demo runbook template
- `doc/README.md`, `doc/service_setup.md`, `README.md`: linked to new guide;
  fixed pre-existing lint issues in service_setup.md
- `.markdownlint.json`: added project lint config (line_length 120, MD024
  siblings_only, MD033 and MD060 disabled)

### Changed

- `build/Dockerfile`: creates `/opt/oracle/network/admin -> /opt/oracle/dbconfig/FREE`
  symlink so `TNS_ADMIN` resolves correctly for named services without manual setup
- `docker-compose.yml`: adds `x-env-named` YAML anchor with `TNS_ADMIN=/opt/oracle/network/admin`;
  all five named services use this anchor; `cdbfree` retains Oracle default network paths;
  compose image uses `${DB_IMAGE:-oracle-free-labs:latest}` as fallback for direct use
- `Makefile`: introduces `DB_BASE_IMAGE` as the single variable controlling the Oracle
  Free base version; `BUILD_IMAGE` (e.g. `oracle-free-labs:23.9.0.0`) and `DB_IMAGE`
  are auto-derived; `DB_IMAGE` is exported so docker compose picks up the correct image
  when invoked via make - no need to set `DB_IMAGE` separately in `.env`
- `.env.example`: replaced explicit `DB_IMAGE` with `DB_BASE_IMAGE`; `DB_IMAGE` is
  now auto-derived from `DB_BASE_IMAGE` via make, eliminating the redundant version entry
- `.gitignore`: `docker-compose.override.yml` added to local overrides section

## [1.0.2] - 2026-04-16

### Changed

- `Makefile`: consolidated `make help` lab services section - replaced six
  per-service sections (36 lines) with a single compact service table;
  per-service shortcut targets (`up-<svc>`, `down-<svc>`, etc.) remain for
  shell autocomplete but no longer clutter the help output

## [1.0.1] - 2026-04-16

### Added

- `config/common/scripts/demo-security-26ai/` - new demo scripts for Oracle
  AI Database 26ai security labs (SQL Firewall, MFA, environment
  check/cleanup/prepare scripts)
- `doc/DOAG2025-Oracle-Container-Labs_Manuskript_v1.0.md` and matching
  `.yml` metadata - DOAG 2025 conference manuscript source
- `artefacts/DOAG2025-Oracle-Container-Labs_Manuskript_v1.0.pdf` - generated
  PDF artefact for DOAG 2025

### Changed

- `build/Dockerfile`: default `DB_IMAGE` changed from `latest-lite` to
  `latest`; switched package manager from `microdnf` to `dnf`; added
  `oracle-epel-release-el8` and OCI region mirror fix for offline builds;
  added `/opt/oracle/local` directory creation; oradba tools now installed
  via `oradba_install.sh --update-profile`
- `Makefile`: `make bash` now opens a login shell (`bash -l`) so `.bash_profile`
  is sourced and oradba/BasEnv tools are available

### Removed

- `docker-publish.yml` GitHub Actions workflow - publishing the Oracle Free
  image is not permitted; removed to prevent accidental pushes to GHCR

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
[1.1.0]: https://github.com/oehrlis/oracle-free-labs/compare/v1.0.2...v1.1.0
[1.0.2]: https://github.com/oehrlis/oracle-free-labs/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/oehrlis/oracle-free-labs/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/oehrlis/oracle-free-labs/compare/v0.5.0...v1.0.0
[0.5.0]: https://github.com/oehrlis/oracle-free-labs/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/oehrlis/oracle-free-labs/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/oehrlis/oracle-free-labs/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/oehrlis/oracle-free-labs/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/oehrlis/oracle-free-labs/releases/tag/v0.1.0
<!-- markdownlint-enable MD013 -->
