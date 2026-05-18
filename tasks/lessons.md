# Lessons Learned - Oracle Free Labs

## 2026-05-18 - Demo Overlays, TNS_ADMIN, Wallet Persistence, Versioned Builds

### docker-compose.override.yml as extension mechanism

Docker Compose merges `docker-compose.override.yml` automatically when it exists in
the same directory - no extra `-f` flag needed. This is the right pattern when a
second repo (talks, demo) needs to add mounts or env vars to a core repo's services
without touching its files. Add it to `.gitignore` in the core repo; the external
repo owns the file and symlinks or copies it in.

### YAML merge key does NOT merge lists - it replaces them

When a service uses `<<: *anchor` and also defines `environment:`, the service's
`environment:` block **replaces** the anchor's `environment:` entirely (it does not
append). Consequence: when overriding environment in a service, always repeat the full
base variable list. Design: use a named anchor (`&env-named`) for extended env sets
and reference it per service group rather than appending to the base anchor.

### Makefile ?= + export to auto-derive docker compose variables

`DB_IMAGE ?= $(BUILD_IMAGE)` combined with `export DB_IMAGE` lets Make derive the
image name from `DB_BASE_IMAGE` and pass it to docker compose via the shell
environment - no separate `DB_IMAGE` entry needed in `.env`. Docker Compose gives
shell environment higher priority than `.env`, so the exported value wins. The `?=`
only sets the variable if it is **undefined**; if `.env` sets `DB_IMAGE` explicitly,
that value is used instead (because `-include .env` sets the Make variable first).

### cdbfree vs named services: different volume layout

`cdbfree` has no explicit `dbconfig` bind mount - its tnsnames/listener files live
inside `/opt/oracle/oradata/dbconfig/FREE/` (which IS bind-mounted via oradata).
Named services have a **separate** `./data/<service>/dbconfig:/opt/oracle/dbconfig`
mount. Any script or symlink that assumes `/opt/oracle/dbconfig/FREE/` must guard
against cdbfree (check `if [[ -d "${DBCONFIG_DIR}" ]]` before acting).

### Dockerfile symlink for dangling paths

Creating a symlink in the Dockerfile that points to a path which only exists at
runtime (via bind mount) is fine. The symlink is dangling until the container starts
with the mount in place, and tools follow it transparently once resolved. Used for
`/opt/oracle/network/admin -> /opt/oracle/dbconfig/FREE`.

### Wallet not bind-mounted by default

`/opt/oracle/admin/FREE/wallet/` (Oracle's default WALLET_ROOT subdirectory) is NOT
in any bind-mounted directory. After a container reset the wallet is lost. Fix: a
startup script that replaces the real directory with a symlink pointing into the
bind-mounted dbconfig area (`/opt/oracle/dbconfig/FREE/wallet/`). Oracle follows
symlinks transparently so no DB parameter change is needed.

### markdownlint config was missing despite being referenced in rules

The CLAUDE.md rules referenced `.markdownlint.json` (line_length 120, MD033 off)
but the file did not exist in the repo. Without it, markdownlint fell back to its
defaults (line_length 80), which caused spurious failures on pre-existing lines.
Always create `.markdownlint.json` at project init; reference the CLAUDE.md rules
as the canonical config content.

### MD024 siblings_only for CHANGELOG

In CHANGELOG files it is standard to have repeated `### Added`, `### Changed`
headings across different version sections. The markdownlint setting
`"MD024": { "siblings_only": true }` allows duplicate headings as long as they are
not siblings (i.e. they appear under different parent headings).

### make -p shows unexpanded variable definitions

`make -p` (print database) outputs raw variable definitions with unexpanded
references (e.g. `BUILD_IMAGE = oracle-free-labs:$(_DB_BASE_TAG)`). The actual
expanded values are correct at recipe execution time. Use `make -n <target>` or
`make <target> --dry-run` to verify the expanded commands, not `make -p`.
