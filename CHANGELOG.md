# Changelog

All notable changes to this project are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/);
versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- seclab: own SYS/SYSTEM/PDBADMIN password `SECLAB_ORACLE_PWD` (falls back to
  `ORACLE_PWD`), so seclab passwords can be rotated without touching the
  `ORACLE_PWD` shared by all services. `seclab_set_admin_pwd.sh` applies it to an
  existing database; runbook section Rotate Passwords.

### Changed

- DBSAT and CIS-CAT share their helpers instead of keeping copies: `scripts/lib_usecase.sh`
  on the host (`newest_zip`, `dangling_links`, `warn_dangling`, `provide_zip`, `copy_back`, `env_fallback`,
  `env_from_file` and the defaults `DBSAT_MIN_JAVA`, `CISCAT_MIN_JAVA`,
  `ASSESS_JRE_IMAGE_DEFAULT`, the zip globs), sourced by `apply_usecase.sh`,
  `check_requirements.sh` and `provide_jre.sh`; `config/common/scripts/lib_java.sh`
  (`java_major`, `resolve_java`, `untrusted_file`, minimum Java versions) and
  `lib_assess.sh` (`newest_zip`, `dangling_links`, `scrub_env`) in the container, sourced
  by `run_dbsat.sh` and `run_ciscat.sh` from their own directory. Output unchanged for
  seclab (dry runs of `dbsat`, `dbsat-discover`, `ciscat`, `ciscat-list` identical); on a
  plain container the DBSAT dry run now shows the `docker cp -L` it always used.
- `run_dbsat.sh` and the host zip lookup treat an unreadable zip as missing (exit 4),
  like `run_ciscat.sh`, instead of failing later in unzip or `docker cp`.
- A dangling symlink among the zips is named instead of skipped silently:
  `apply_usecase.sh` (WARN), `make check` for the DBSAT zip (WARN, CIS-CAT did it already),
  `run_dbsat.sh` in the exit 4 message (like `run_ciscat.sh`).

### Fixed

- `apply_usecase.sh dbsat|dbsat-discover`: a symlinked DBSAT zip in a bind-mounted
  `config/common/data` dangles inside the container, `run_dbsat.sh` stopped with exit 4.
  The zip is now used through the bind mount only if it is readable there, otherwise it
  is copied with `docker cp -L` to `/tmp/dbsat-zip` (reported as WARN), the way CIS-CAT
  always gets its zip.

## [1.5.0] - 2026-10-20

### Added

- `scripts/provide_jre.sh CONTAINER [DIR]`: copies a Java 21 runtime from the local image
  `ASSESS_JRE_IMAGE` (default `eclipse-temurin:21-jre`, pulled if missing) into a running
  Oracle container - `/opt/oracle/oradata/tools/jre21` for lab services (persistent as
  `data/<service>/tools/jre21`), `/tmp/jre21` for any other container. Reuses a working
  JRE and says so, checks the architecture, unpacks as `oracle` (a `chown` does not stick
  on Docker Desktop bind mounts), verifies Java 17+. Exit 0/1/2/3. An explicit target
  is validated before the root `rm -rf` (absolute, no whitespace, quotes or `..`, last
  component `jre*`), paths reach the container as arguments, never inside a command
  string; the temporary JRE container is removed on any exit. One mechanism for DBSAT
  now and CIS-CAT later.
- `run_dbsat.sh -j/--java-home DIR`; `make check` reports whether the JRE image is
  present (when a DBSAT zip is there or for seclab); `ASSESS_JRE_IMAGE` in `.env.example`
  and the Makefile.
- DBSAT discover (sensitive data discovery): `run_dbsat.sh` v1.2.0 `-m` selects
  `collect`, `report`, `discover` or `all` (default `collect,report` as before); use
  case `apply_usecase.sh dbsat-discover`, targets `make dbsat-discover` and
  `make dbsat-discover-seclab`. Options `-P`, `-S`, `-r`, `-O`, `-x`, `-g`, `--existing-user`,
  `DISC_TIMEOUT`; the prompts are answered through a pseudo terminal. Output
  `dbsat_<pdb>_discover.{html,csv,json}`, `_discoverer.log` and a summary line.
- `gather_missing_stats.sql`: names tables without optimizer statistics in a schema scope
  (DBSAT discover skips them without a message, also with MINROWS 0) and gathers them
  with `GATHER EMPTY`. `run_dbsat.sh -m discover` always reports them, `-g` gathers;
  `seclab_apply.sh` v1.1.0 gathers them as step 10 of 11.
- `doc/dbsat-runbook.md` section Discover (options, pseudo terminal, statistics, measured
  seclab result, false positives from column names and comments), troubleshooting rows;
  `doc/seclab.md` S08 links the discover result.

- CIS-CAT Lite and Pro with one code path (Lite 4.67.0 verified, Pro not verified):
  `config/common/scripts/run_ciscat.sh` runs as root in the container, extracts the zip
  without the bundled Windows JRE (cached while the zip is unchanged, reuse reported),
  checks Java 21, reports edition (license directory) and version (manifest), lists
  benchmarks and profiles from the XCCDF (one parser, multi-line tags, entities decoded)
  and selects `CISCAT_BENCHMARK=auto|<name part>|<path>` and `CISCAT_PROFILE`. Every
  assessment runs from a generated `-cfg` XML (mktemp 0600, removed on exit, INT and TERM;
  stale files of a killed run are removed and reported). `auto` with Lite stops with exit 2, the benchmark list, the
  Pro link and the mechanics demo; a platform mismatch is reported as such (exit 3, score
  0 is no result); `CISCAT_IGNORE_PLATFORM=1` forces it with a warning. Requested
  formats html/json/csv/txt, the written ones are named (Lite: HTML only). Exit codes
  4 (no zip, both links), 5 (no Java 21), 111/114/116 translated. DB mode for an
  Oracle Database benchmark (Pro, NOT VERIFIED): `CISCAT_USER` via
  `create_dbsat_user.sql`, JDBC URL and listener.ora as interactive values; a password
  with `@ / "` or whitespace is refused, the password is masked (raw and XML-escaped) in
  the log and every report file, a file that still contains it is named in a WARN.
- CIS-CAT root hardening: java runs only from a root-owned JRE (no file owned by another
  user, none world-writable), `provide_jre.sh --owner root` provides it in
  `/root/.cache/jre21` (never below a bind mount, lost on container recreate); the
  extraction cache is `/root/.cache/ciscat` (root-owned parent, mode 700), reused only
  while every file in it belongs to root, otherwise removed and extracted again; the
  work dir must not overlap the zip or report directory; `apply_usecase.sh` always copies
  the zip into the root-owned `/root/.cache/ciscat-zip`.
- `scripts/apply_usecase.sh ciscat|ciscat-list`, `make ciscat CONTAINER=x [PDB=..]
  [CISCAT_BENCHMARK=..] [CISCAT_PROFILE=..] [CISCAT_IGNORE_PLATFORM=1]`, `make ciscat-seclab`,
  `make ciscat-list [CONTAINER=..]`; reports in `data/ciscat/<container>/`. The zip is
  copied with `docker cp -L` (a host symlink works); the DB password is passed to
  `ciscat` only, never to `ciscat-list`.
- `scripts/provide_jre.sh -m/--min-java N` (default 17; CIS-CAT passes 21) and
  `-o/--owner oracle|root`.
- `make check`: CIS-CAT zip present, edition guess and whether an Oracle Database / Oracle
  Linux benchmark is inside (`unzip -Z1`, no extraction); the JRE image check also runs
  when only a CIS-CAT zip is there; a Lite zip reports one SKIP instead of two WARNs
  unless `SERVICE=seclab`.
- `doc/ciscat-runbook.md` (Lite/Pro matrix, runtime rules, exit codes, Lite evidence,
  "Pro assumptions - not verified"), `config/common/data/ciscat/README.md` (tracked, zip
  ignored), `CISCAT_*` in `.env.example` (commented out, defaults in `run_ciscat.sh`),
  `doc/seclab.md` section "Expected CIS Rule (Pro, Unverified)" with areas only.

### Changed

- DBSAT report runs with Java 17+: `make dbsat-seclab` and `make dbsat` /
  `apply_usecase.sh dbsat` provide the JRE first (target chosen by `provide_jre.sh`,
  `run_dbsat.sh` finds it without `-j`; `make dbsat-seclab` stops on a container
  problem, exit 1). `run_dbsat.sh` v1.1.0 sets `JAVA_HOME`
  (`-j`, else the first of `$JAVA_HOME`, `/opt/oracle/oradata/tools/jre21`, `/tmp/jre21`
  with Java 17+) and reports each skipped candidate. Without Java 17+ it still collects,
  then stops with **exit 5** and names the command that provides Java;
  `apply_usecase.sh` copies the collection back in that case. python3 is no longer a hard
  prerequisite (DBSAT 4.x does not report with it).
- `make lint-shell` also covers `config/common/scripts/*.sh` and
  `config/*/setup|startup/*.sh`; `fmt-shell` / `fmt-shell-write` stay on `scripts/`.
- `doc/dbsat-runbook.md`: status "not verified" replaced by the measured state (DBSAT 4.3,
  2026-10-19, seclab and plain Oracle image), Java prerequisite, exit codes,
  troubleshooting. `doc/seclab.md`: DBSAT column with the rule IDs and ratings measured
  against seclab, deviations for S06 and S07 named.
- `.env.example`: `DB_BASE_IMAGE` defaults to `free:latest` (26ai); docs aligned. The
  Makefile fallback without `.env` is unchanged.

### Fixed

- Security: `dbsat collect` writes its process environment into `dbsat_<pdb>.json`,
  so `ORACLE_PWD` and the `SECLAB_*_PWD` values landed there in clear text.
  `run_dbsat.sh` now runs DBSAT with every secret-like variable removed (`env -u`)
  and names them. Collections written before this fix still contain the values.
- `run_dbsat.sh`: DBSAT 4.x extracts into a `dbsat/` subdirectory; the script took that
  directory for the launcher (`-x` is true for directories). It now searches for a file
  named `dbsat` and stops with an error if there is none.
- `run_dbsat.sh` on the plain Oracle image: `create_dbsat_user.sql` failed with
  `SP2-0606` because `/opt/oracle/scripts/logs` does not exist there; the script now
  creates `SQL_LOG_DIR` like `seclab_apply.sh`.
- Security: `create_dbsat_user.sql` dropped and recreated whatever account name it got.
  It now refuses SYS, SYSTEM, PDBADMIN and Oracle-maintained accounts (nothing dropped);
  `run_dbsat.sh -u` refuses those names before anything runs.
- `apply_usecase.sh dbsat`: a symlinked DBSAT zip was copied as a dangling link
  (`docker cp -L` now).
- shellcheck SC2164 in `00_enable_unified_audit.sh` and `01_check_unified_audit.sh`
  (`make -C` instead of an unchecked `cd`).

## [1.4.0] - 2026-10-16

### Added

- Service `seclab` (profile `seclab`, ports 1534/5512 bound to `127.0.0.1` only): an
  INTENTIONALLY INSECURE security baseline for assessment and remediation testing.
  Eleven catalogued scenarios S01-S11 (PUBLIC grants, UTL_FILE dependency, legacy
  verifiers, weak profile, over-privileged accounts, unused accounts, audit gaps, no TDE,
  no network encryption, `SQL92_SECURITY=FALSE`, SCOTT default password), each with
  proof query, remediation class and expected DBSAT rule in `doc/seclab.md`.
- `seclab_apply.sh` as single entry point for the scenarios, used by the service setup
  and by `scripts/apply_usecase.sh`, which applies a use case to **any** running Oracle
  Database Free container, also the plain Oracle image (`make apply USECASE=seclab
  CONTAINER=<name>`). Refuses seclab on containers that publish ports beyond localhost.
- Read-only verification `seclab_verify.sh` (`make verify-seclab`): PRESENT / ABSENT /
  NOT REPRODUCIBLE per scenario, exit 0/1/2. Remediation and rollback for the class 1
  scenarios (`FIX` / `INSECURE` mode), read-only pre-checks for class 2
  (`precheck_revoke_public.sql`, `precheck_logon_version.sql`,
  `precheck_profile_hardening.sql`).
- DBSAT integration without shipping DBSAT: `run_dbsat.sh`, `create_dbsat_user.sql`,
  `make dbsat-seclab`, `make dbsat CONTAINER=<name>`. Without the archive in
  `config/common/data/dbsat/` the run stops with exit 4 and explains where to get it.
- Generic helpers in `config/common/scripts/`: `run_sql_script.sh` (SQL as SYSDBA with
  logging, passwords by environment variable name), `set_sqlnet_param.sh`,
  `set_static_param.sql`, `restart_instance.sql`.
- Pre-flight check `scripts/check_requirements.sh` (`make check [SERVICE=...]`, run by
  `make up-seclab`): runtime, Colima mounts, memory, CPUs, compose, disk, image, `.env`
  variables, ports.
- Runbooks: `doc/container-runtime-runbook.md` (Docker Desktop and Colima verified, Podman
  documented), `doc/seclab-runbook.md`, `doc/dbsat-runbook.md`.
- `tasks/repo-audit-2026-10-16.md`: audit of redundancies and a phased plan for a
  use-case based simplification (analysis only, nothing implemented).

### Changed

- `create_ts_users.sql` v1.1.0 works without OMF: it checks for the tablespace first and
  places the datafile next to the SYSTEM datafile when `db_create_file_dest` is empty
  (FREEPDB1 of the Oracle image). With OMF the behaviour is unchanged.

## [1.3.0] - 2026-09-11

### Fixed

- The run log lived in the directory that step 00 deletes. `run_all.sh` wrote it
  to `data/xchange/evidence/`, which `--delete` clears - so the log sat inside the
  blast radius of the very first step it was meant to record. Measured
  2026-09-11: the log lost its header and all of step 00, later appends recreated
  the file, and the generated protocol then claimed 21 of 21 in its summary while
  its detail section held 20, with nothing pointing at the gap. The log now lives
  in `artefacts/`, outside the reset, where the existing `.gitignore` exception
  also makes it versionable without a copy step.
- `make_protocol.sh` could emit a self-contradicting document. It now compares the
  result table against the detail sections, warns on stderr naming the missing
  steps, and states the gap **on the protocol's own face** rather than leaving a
  reader to trust a summary the body does not support.
- `artefacts/README.md` listed two versioned log patterns; the third,
  `artefacts/run_*.log`, was missing from the table since v1.2.2.
- `tasks/e2e-facts.md` said the 2026-09-11 run logs were not versioned. They have
  been since v1.2.2, in the same commit that added the exception.

### Changed

- `doc/tde-e2e-protokoll.md` regenerated from `artefacts/run_20260911_093022.log`
  and now carries the incompleteness note for step 00 instead of hiding it.
- `tasks/prompt-autonomous-e2e.md`: brought up to the state of `run_all.sh` 0.3.0
  and `make_protocol.sh` 0.3.0. The run log is written to `artefacts/` directly, so
  the post-run copy step is gone, and the protocol consistency check is a new
  expected value. Earlier in the day it had been synced to 0.2.1 and 0.2.0, with the two checkable consequences - the protocol
  must now be generatable straight from the evidence log, and a dry run must leave
  no log behind. Corrected the step 20 expectation: `ORA-28365` should **not**
  appear, because the suite deliberately stages only `ewallet.p12`. Added
  `ORA-46655` in step 65 as an expected value with its explanation, so the central
  finding of this engagement is not reported as a malfunction. The entry prompt now
  instructs the session to read the whole file first - the expected values live in
  the file, not in the block that gets pasted.

## [1.2.3] - 2026-09-11

### Fixed

- `run_all.sh` wrote an evidence log in dry-run mode: `log_line`, the `emit`
  filter and the per-step `tee` had no `DRY_RUN` guard. A leftover
  `run_<timestamp>.log` from a dry run is indistinguishable from a real one, and
  `make_protocol.sh` would parse it into the protocol of a run that never
  happened. A dry run now writes nothing, passes output through to the terminal
  only, and says so instead of naming a log path that does not exist - the
  startup banner and the result table both claimed one.

## [1.2.2] - 2026-09-11

### Fixed

- `scripts/tde-verify/run_all.sh`: the `STEP nn:` banners and the closing result
  table went to stdout only, so the evidence log under `data/xchange/evidence/`
  carried neither. A new `emit` helper copies both into the log, which makes the
  evidence log self-sufficient as a protocol source again.
- `scripts/tde-verify/make_protocol.sh`: a log with neither step headers nor a
  result table produced a 17-line protocol stating "Der Lauf hat keine
  Ergebnistabelle geschrieben - er wurde abgebrochen" - for a run that passed 21
  of 21, and well-formed enough to pass markdownlint. It now exits 2 with an
  error naming the likely cause and the fix, and writes nothing. A run that is
  genuinely cut off (steps present, table missing) still produces a partial
  protocol, now with a warning on stderr.
- `scripts/tde-verify/make_protocol.sh`: `main > "${OUT_FILE}"` truncated the
  target before the parser ran, so a parser failure destroyed the previous
  protocol and left nothing. Output now goes through a temp file and is moved
  into place only on success.

### Added

- `tasks/e2e-facts.md`: measured values of the end-to-end run
  `run_20260911_080723` from 2026-09-11, 21 of 21 steps passed, in a section of
  its own. Confirms every structural result of the 2026-09-06 run. New in-suite
  finding: `ORA-46655` on key import after the remote PDB clone, because the
  clone carries the master key into the target by itself.

## [1.2.1] - 2026-09-11

### Fixed

- `artefacts/README.md` claimed the folder is not versioned in Git. Two named
  log patterns are, deliberately, because documentation cites them as evidence.
  The README now states which, why, and how to check a log for secrets before
  adding it.

## [1.2.0] - 2026-09-11

### Added

- `doc/tde-restore-runbook.md`, section "Einstiegspunkte": dependency graph of the test
  steps plus a recipe table that names the exact step sequence per test case, so a single
  path can be driven without the full run. The PDB series (61 to 69, 71) needs no RMAN
  backup - only steps 00 and 61.
- `doc/tde-restore-runbook.md`: every phase now opens with a Ziel / Frage / Erwartung block,
  so it is visible before the commands what the phase measures and what result is expected.
- Test step 71 `71_pdb_p4b_nokeyimport.sh`: remote PDB clone with neither `EXPORT KEYS` nor
  `IMPORT KEYS`. It measures whether the target ever needs the source master key, and it
  hard-checks beforehand that the source key is absent from the target keystore - otherwise
  the run would prove nothing.
- Finding, measured by hand on 2026-09-10 outside the suite: a remote clone transports the
  source master key into the target keystore all by itself, where it reports `ORIGIN = LOCAL`.
  The clone re-wraps the tablespace key but does not rotate the master key. Documented as a
  four-step procedure in runbook phase 6b - clone, set the tablespace `READ WRITE`, rotate,
  verify that nothing references the source key any more - with the trap that a read-only
  tablespace is not re-wrapped, so a first `SET KEY` succeeds and changes nothing. Evidence:
  `artefacts/p4b-experiment-20260910_171555.log`,
  `artefacts/p4b-setkey-20260910_185928.log`; values in `tasks/e2e-facts.md` in a section of
  their own, kept apart from the 2026-09-06 end-to-end run.
- Third-party reference in phase 6b, marked as not our measurement: a former Oracle
  product manager for TDE and Key Vault, describes publicly that a cloned PDB carries a master
  key tagged with the source PDB's tag and has no key of its own, so cloning that clone again
  fails with a missing-key error. The remedy is the same rotation, with a speaking tag. The
  operational consequence: the rotation is not only a security step - without it the copy
  cannot be cloned again.
- Steps 20 and 40 now capture the DBID of the clone, so a later step can tell a genuine
  foreign CDB from a restore of the source.
- End-to-end verification run: one uninterrupted pass over all 21 steps, 27 minutes,
  21 of 21 passed. Raw log `artefacts/tde-e2e-run-20260906.log`, protocol
  `doc/tde-e2e-protokoll.md`, measured values `tasks/e2e-facts.md`.
- `scripts/tde-verify/make_protocol.sh`: generates the test protocol from a run log, so
  it can be regenerated from the same evidence at any time.
- PDB transport cases as steps 61 to 69: testbed, local clone, archive transport,
  keyless unplug, remote clone over a DB link, key provenance, KEY_VERSION, MEK
  rotation in both tablespace states, and ONLINE REKEY in the PDB.
- `doc/tde-restore-runbook.md`: phases 4a, 5a, 5.10 and 6a - every automated step now
  has a manual counterpart.

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

- The verdicts now rest on the canary ciphertext instead of the stored key value.
  `V$ENCRYPTED_TABLESPACES.ENCRYPTEDKEY` changes on a pure re-wrap as well, so it
  cannot tell a re-wrap apart from new key material.
- Documentation brought onto the measured values, and three claims corrected: variant C
  was listed as not measured; `ONLINE REKEY` as the only way to new key material holds
  for a tablespace in place, not for the way via a copy - the PDB clone produces new
  material with a single supported command; the documented `KEY_VERSION` reset after a
  plug-in was not observed in the lab.
- `ODBENCPROD_DB_MEM` and `ODBENCDEV_DB_MEM` lowered from 3g to 2g after the OOM killer
  took out a sqlplus process mid-run. Oracle Free caps the SGA at 2g anyway.

- `doc/tde-key-architecture.md`: rewritten around the measured dependency model between
  master key, database key and tablespace key, with eight Mermaid diagrams.

### Fixed

- Six corrections to `doc/tde-restore-runbook.md`, all found by running it by hand:
  the fingerprint line count counts data lines, not `wc -l` output; host datafile paths carry
  the PDB GUID and have no `oradata` segment; the RMAN `FORMAT` clause belongs on the channel,
  not on `BACKUP DATABASE PLUS ARCHIVELOG`, otherwise the datafile pieces land outside the
  exchange mount; a new step reopens the keystore after the PDB opens, without which the next
  statement fails with `ORA-28365`; the control file is restored from the explicitly named
  source piece, because `FROM AUTOBACKUP` picks the target's own once the DBID is shared; and
  the `CATALOG START WITH` step is dropped because it makes the target's incarnation current.
- Variant F: encrypted undo survives the decryption of the data and breaks the discard
  path with `ORA-28304` on the undo datafile, while `V$ENCRYPTED_TABLESPACES` correctly
  reports zero rows. The undo tablespace is now replaced before the discard.
- The withdrawal test handled only a failing query, not a database that never opens.
  Without the source master key the target stops at `MOUNTED` with `ORA-28374`.
- The positive control counted heading lines instead of blocks and reported
  "1 differing / 1 total" while the comparison found 1140 of 2561 - in the one step
  that licenses every "identical" result elsewhere.
- SQL*Plus failures were swallowed by the pipe into `grep`, so a failed statement
  looked like success and `set -e` never fired.

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
[1.3.0]: https://github.com/oehrlis/oracle-free-labs/compare/v1.2.3...v1.3.0
[1.2.3]: https://github.com/oehrlis/oracle-free-labs/compare/v1.2.2...v1.2.3
[1.2.2]: https://github.com/oehrlis/oracle-free-labs/compare/v1.2.1...v1.2.2
[1.2.1]: https://github.com/oehrlis/oracle-free-labs/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/oehrlis/oracle-free-labs/compare/v1.1.1...v1.2.0
[1.1.0]: https://github.com/oehrlis/oracle-free-labs/compare/v1.0.2...v1.1.0
[1.0.2]: https://github.com/oehrlis/oracle-free-labs/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/oehrlis/oracle-free-labs/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/oehrlis/oracle-free-labs/compare/v0.5.0...v1.0.0
[0.5.0]: https://github.com/oehrlis/oracle-free-labs/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/oehrlis/oracle-free-labs/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/oehrlis/oracle-free-labs/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/oehrlis/oracle-free-labs/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/oehrlis/oracle-free-labs/releases/tag/v0.1.0
<!-- markdownlint-restore -->
