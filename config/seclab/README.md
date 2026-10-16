# seclab Configuration

> **INTENTIONALLY INSECURE - lab use only.** This service builds a database
> with known, catalogued weaknesses for security assessment and remediation
> testing. Its ports are bound to `127.0.0.1` only. Never expose it.

- Scenario catalog (S01-S11, proof queries, remediation classes, expected
  DBSAT rules): [doc/seclab.md](../../doc/seclab.md)
- Quick start, remediation loop, reset: [doc/seclab-runbook.md](../../doc/seclab-runbook.md)

## Scenarios

| ID | Weakness | Class |
| --- | --- | --- |
| S01 | Custom object privileges granted to PUBLIC | 1 |
| S02 | Application code uses `UTL_FILE` only through PUBLIC | 2 |
| S03 | Low `ALLOWED_LOGON_VERSION_SERVER`, 11G verifiers | 2 |
| S04 | Profile without limits for personal and service accounts | 2 |
| S05 | Application owner with DBA, `ANY` privileges, `WITH ADMIN OPTION` | 3 |
| S06 | Open, never used custom accounts | 1 |
| S07 | Unified Audit incomplete (no logon audit, no object policy, no cleanup) | 3 |
| S08 | Unencrypted sensitive data, no keystore | 3 |
| S09 | Network encryption not enforced | 3 |
| S10 | Static parameter `SQL92_SECURITY = FALSE` | 1 + restart |
| S11 | SCOTT with its default password | 1 |

## Layout

The service scripts are thin wrappers. All scenario logic lives in
`config/common/scripts/` so that the same code can be applied to any Oracle
Free container (`scripts/apply_usecase.sh seclab <container>`).

- **setup/** - runs once on the first start
  - `01_drop_pdb_freepdb1.sql` - drops the default PDB `FREEPDB1`
  - `10_create_pdb_secpdb1.sql` - creates PDB `SECPDB1`
  - `20_seclab_apply_secpdb1.sh` - runs `seclab_apply.sh -p SECPDB1`:
    all scenarios, then the verification
- **startup/** - runs on every start, never re-applies a scenario, so a
  remediation survives a restart
  - `00_startup_config.sql`, `10_startup_config_secpdb1.sql` - start markers
  - `01_setup_network_wallet.sh` - wallet persistence (`setup_network_wallet.sh`)

The Oracle image sources `*.sh` files from these folders. The wrappers run
their body in a subshell so that `set -euo pipefail` and `exit` cannot end the
image's script runner.

## Requirements

- `make build` (extended image with the `TNS_ADMIN` symlink)
- `SECLAB_USER_PWD` and `SECLAB_SCOTT_PWD` in `.env`; `SECLAB_DBSAT_PWD` for DBSAT
- Ports `SECLAB_LISTENER_PORT` (1534) and `SECLAB_OEM_EXPRESS_PORT` (5512) on
  `127.0.0.1`
