# Contributing

## Purpose

This repository provides a container-based lab environment for Oracle AI Database
Free (26ai). Contributions should improve the lab setup, scripts, documentation,
or tooling quality.

## Contribution Types

- Docker Compose and container configuration
- SQL setup and startup scripts
- Shell scripts and Makefile targets
- Documentation and guides
- Bug fixes and compatibility improvements

## Rules

- Keep changes focused and minimal
- Follow existing naming conventions (`00_`, `10_` prefixes for SQL scripts)
- Ensure all content is lint-compliant (`make lint`)
- Do not mix unrelated changes in one commit
- Conventional Commits: `type(scope): description`
  (types: `feat`, `fix`, `docs`, `refactor`, `chore`, `test`, `ci`)

## Shell Script Standards

- `set -euo pipefail` at the top of every script
- OraDBA header block required for new scripts (use `/bash-header` skill)
- All scripts must pass `shellcheck` without warnings

## SQL Script Conventions

- Begin with `@/opt/oracle/common/scripts/define_logging_begin.sql`
- End with `@/opt/oracle/common/scripts/define_logging_end.sql`
- Use `WHENEVER SQLERROR EXIT` for fail-fast behavior
- Numeric prefix controls execution order: `00_`, `10_`, `20_`

## Workflow

1. Create a branch (`git checkout -b fix/short-description`)
2. Make changes
3. Run `make lint` locally
4. Commit with a Conventional Commit message
5. Open a pull request against `main`
6. Address review feedback

## Secrets

Never commit credentials, passwords, or tokens. Use environment variables
in `.env` (gitignored). Secrets management via 1Password:
`op read "op://vault/item/field"`.

## Review Expectations

- Changes must be understandable without additional context
- Assumptions must be explicit
- Unclear or ambiguous changes will be rejected
