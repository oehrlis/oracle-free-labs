# CIS-CAT Runbook - Lite and Pro in Any Lab Container

"I want a CIS benchmark assessment of container xyz." This runbook covers the
CIS-CAT Assessor v4 with one code path: `config/common/scripts/run_ciscat.sh`
in the container, `make ciscat` / `scripts/apply_usecase.sh ciscat` on the host.

## Status

**Lite verified, Pro not verified.** Measured on 2026-10-19/20 with CIS-CAT Lite
Assessor 4.67.0 on Oracle AI Database 26ai Free 23.26.3 (Oracle Linux 8.10,
arm64, Docker Desktop), in seclab and in a plain Oracle image container. No Pro
license was available: everything marked **Pro** is an assumption from the Lite
binary, its sample configuration and the CIS documentation. In seclab,
`run_ciscat.sh` was run directly (`docker exec`); the `make ciscat` /
`apply_usecase.sh ciscat` path was run against a plain Oracle image container.
`make ciscat-seclab` (= `make ciscat CONTAINER=seclab`) has not run end to end
yet: seclab mounts the scripts of the main checkout, which has no
`run_ciscat.sh` until this change is merged.

## Where to Get It

| Edition | How | Link |
| --- | --- | --- |
| Lite | free, registration | <https://learn.cisecurity.org/cis-cat-lite> |
| Pro | CIS SecureSuite membership, CIS WorkBench (per CIS documentation, unverified) | <https://www.cisecurity.org/cybersecurity-tools/cis-cat-pro> |

Copy the zip unchanged to `config/common/data/ciscat/` (ignored by Git, see
[its README](../config/common/data/ciscat/README.md)). The scripts take the
newest zip whose name contains `CIS-CAT` or `ciscat`.

## Lite and Pro

Pro is expected to be the same binary (unverified): Lite's `Assessor-CLI.jar`
carries `Implementation-Title: CIS-CAT Pro Assessor`, and Lite ships an empty
`Assessor/license/`. `run_ciscat.sh` reports the edition from that directory
and the version from the manifest.

<!-- markdownlint-disable MD013 MD060 -->
| Topic | Lite 4.67.0 (measured) | Pro (assumption, unverified) |
| --- | --- | --- |
| Benchmarks | 5: Google Chrome Group Policy v1.1.0, Microsoft Windows 10 Enterprise v5.0.0, Microsoft Windows 10 Stand-alone v5.0.0, Microsoft Windows 11 Enterprise v5.1.0, Ubuntu Linux 24.04 LTS v2.0.0 | full CIS catalogue; a Pro benchmark is expected to cover the database (unverified) |
| Oracle Database / Oracle Linux benchmark | **none** | expected `CIS_Oracle_Database_*`, `CIS_Oracle_Linux_*` |
| Report formats | **HTML only** - JSON, CSV, TXT are ignored | HTML, JSON, CSV, TXT |
| Other benchmark | refused: "Assessor is restricted to Lite" | - |
<!-- markdownlint-restore -->

Lite proves the mechanics with the Ubuntu benchmark - on Oracle Linux that is
**not** a compliance result.

## Runtime Rules

- **Root in the target.** A local assessment must run inside the container as
  root (`docker exec -u 0`); as `oracle` the local session fails. The script
  refuses non-root (exit 116). A helper container cannot assess another one.
- **Root-owned Java 21.** The image ships JDK 11, the bundled `Assessor/jre` is
  Windows x64. Root must not run code `oracle` can change: only a JRE whose
  files all belong to root (none world-writable) is used. `make ciscat` runs
  `scripts/provide_jre.sh --owner root --min-java 21` (`/root/.cache/jre21`).
  Trade-off: unlike the persistent DBSAT JRE (`oracle`, bind mount) it is gone
  when the container is recreated and copied again (about 5 s); a bind mount
  is refused because the host can change it whatever owner it shows.
- **Integrity check.** At startup the assessor checks its own files. Only
  `*/jre/*` is left out when extracting; a JRE placed inside the assessor
  directory breaks the check.
- **Root-owned cache.** `/root/.cache/ciscat` (about 180 MB, parent mode 700)
  is reused while the zip is unchanged and every file belongs to root, else
  removed and extracted again - both reported. A work dir overlapping the zip
  or report directory, or with a writable parent such as `/tmp`, is refused.
- **Root-owned code.** `run_ciscat.sh` refuses to run as root when it, its
  libraries (`lib_java.sh`, `lib_assess.sh`) or any directory up to `/` are
  writable by a non-root user (a read-only mount counts as safe, a sticky `/tmp`
  too). `/opt/oracle` belongs to `oracle`, so a direct run from
  `/opt/oracle/common/scripts` is refused. `make ciscat` / `apply_usecase.sh
  ciscat` copy the three files root-owned to `/root/.cache/ofl-ciscat-code` and
  run them from there.

## Run It

```bash
# zip present? edition guess, Oracle benchmarks inside
make check
# edition, benchmarks, profiles, auto choice (default container: seclab)
make ciscat-list CONTAINER=free26ai
# auto: Lite stops with exit 2 and explains
make ciscat CONTAINER=free26ai
# Lite mechanics demo, score NOT meaningful on Oracle Linux
make ciscat CONTAINER=free26ai CISCAT_BENCHMARK=ubuntu CISCAT_IGNORE_PLATFORM=1
make ciscat-seclab
```

Pass `CISCAT_*` as make arguments: make exports them to the script.
`apply_usecase.sh` takes the environment first, then `.env`.

What happens:

- zip copied (`docker cp -L`) to the root-owned `/root/.cache/ciscat-zip`,
  scripts copied unless bind-mounted (for `run_sql_script.sh`, runs as oracle),
  `run_ciscat.sh` and its libraries copied root-owned to
  `/root/.cache/ofl-ciscat-code`, root-owned JRE 21 provided;
- `docker exec -u 0 ... /root/.cache/ofl-ciscat-code/run_ciscat.sh`: cache, edition, selection, assessment
  from a generated `-cfg` XML (0600, removed on exit, INT and TERM);
- reports copied to `data/ciscat/<container>/` on the host (also on exit 3).

### Selection

<!-- markdownlint-disable MD013 MD060 -->
| Variable | Values |
| --- | --- |
| `CISCAT_BENCHMARK` | `auto` (default), a part of a benchmark file name (`ubuntu`), or a path to an `*-xccdf.xml` inside `Assessor/benchmarks` (a copy elsewhere makes Lite 4.67.0 fail with a `NullPointerException`) |
| `CISCAT_PROFILE` | profile title (`Level 1 - Server`) or id; empty = first profile of the benchmark |
| `CISCAT_IGNORE_PLATFORM` | `1` = assess even if the benchmark does not fit the OS |
| `CISCAT_PWD` | DB mode only (Pro): password of `CISCAT_USER`, no `@ / "` or whitespace; falls back to `DBSAT_PWD`, `SECLAB_DBSAT_PWD`; not passed to `ciscat-list` |
<!-- markdownlint-restore -->

`auto` picks the Oracle Linux benchmark of the container OS and the Oracle
Database benchmark (26ai, 23ai, 19c, any). No or several matches stop with the
list - never a silent skip. Profiles are read from the XCCDF and checked first.

### Output

`data/ciscat/<container>/ciscat_<container>_<benchmark>.html` (for example
`ciscat_seclab_ubuntu_linux_24.04_lts.html`) and `.log` with the full assessor
output. With a DB password set, it is masked (raw and XML-escaped) in the `.log`
and every report file; a file that still contains it is named in a WARN. Files
of the same name are removed first and reported.

### Exit Codes

<!-- markdownlint-disable MD013 MD060 -->
| Code | Meaning | Evidence (Lite 4.67.0, seclab, 2026-10-20) |
| --- | --- | --- |
| 0 | assessed, reports written | `ubuntu` + `CISCAT_IGNORE_PLATFORM=1`: pass 165, fail 81, score 67.07 %, HTML 9.7 MB, about 20 s |
| 1 | error (unzip, assessor, account, unsafe work dir, bad DB password) | `-w` equal to the report dir refused; password with `@` refused |
| 2 | no applicable benchmark (auto), name part matches none or several, not in Lite | `auto`: list of the 5 benchmarks with profiles, Pro link, demo command |
| 3 | assessed, **platform mismatch**: every rule Not Applicable, no valid result | `ubuntu`: "The checklist does not match the target platform", not applicable 332, score 0.00 % |
| 4 | no CIS-CAT zip | empty zip directory: both download links |
| 5 | no root-owned Java 21 | `oracle`-owned JRE refused with owner and mode named |
| 111 | invalid profile (checked up front; the assessor itself exits 1 with "invalid profile") | `Level 9 - Bogus`: four valid profiles with ids |
| 114 | benchmark file not found | - |
| 116 | not root | run as `oracle` |
<!-- markdownlint-restore -->

Both Ubuntu runs have 332 results; the platform check decides applicability.
On: all 332 Not Applicable. Off: 246 scored (165 pass + 81 fail), 74 Not
Selected (other profile), 10 Not Checked, 2 Informational. The 67 % only shows
that the assessor works, nothing about the container's hardening.

## Pro Assumptions - Not Verified

Nothing in this section has run against a Pro license. `auto` expects file
names with `Oracle_Database_26ai`, `_23ai`, `_19c` and `CIS_Oracle_Linux_<major>_`;
if the real names differ, set `CISCAT_BENCHMARK` to a part shown by
`make ciscat-list`.

DB mode, for a benchmark whose file name contains `Oracle_Database`, creates
`CISCAT_USER` with `create_dbsat_user.sql` (the DBSAT least-privilege account)
and passes the JDBC URL and `listener.ora` as interactive values in the `-cfg`
XML. Details and the unknowns are in the header of `run_ciscat.sh`; the
mechanics ran with a renamed Ubuntu XCCDF, the password was in no file
afterwards, and the account was dropped after the test.

Pro verification checklist:

- edition reported as Pro, `auto` picks an Oracle Database and the Oracle Linux benchmark
- DB mode connects as `CISCAT_USER` - missing privileges show as errors or unknowns
- JSON, CSV and TXT are written next to HTML
- report contains no password (`.log`, HTML, JSON, CSV, TXT; the script warns otherwise)
- replace the expected areas in [seclab.md](seclab.md) with measured rule IDs

## Troubleshooting

<!-- markdownlint-disable MD013 MD060 -->
| Symptom | Cause | Fix |
| --- | --- | --- |
| exit 1, `has no run_ciscat.sh` | the container bind-mounts another checkout | recreate it from this checkout, or use a container without the mount |
| `WARN: JRE ... refused` | JRE not root-owned (for example the DBSAT JRE) | `scripts/provide_jre.sh --owner root --min-java 21 <container>` |
| `NullPointerException ... VerifyBeforeStartup` | jar called with a relative path | call it with an absolute path (the script does) |
| `NullPointerException ... validateSignatureParametersSchema` | `-b` path outside `Assessor/benchmarks` | use a benchmark inside the archive |
<!-- markdownlint-restore -->
