# TDE Restore Verification Test Suite

Scripts to prove at the block level whether an RMAN clone of a TDE-encrypted
Oracle database re-encrypts the data (new Tablespace Encryption Key, TEK) or
merely re-wraps the existing TEK under a new Master Encryption Key (MEK).

## Background

The central question: does `RESTORE DATABASE AS ENCRYPTED USING KEY <mek>` or
`DUPLICATE ... AS ENCRYPTED` create genuinely new TEK material, or does it only
re-wrap the existing TEK in the datafile header? SQL views alone cannot answer
this - `ENCRYPTEDKEY` and `KEY_VERSION` change on both a re-wrap and a real
re-encrypt. The answer requires block-level ciphertext comparison.

See `doc/tde-restore-as-encrypted.md` for the full test protocol and results.

## Directory layout

```text
scripts/tde-verify/
├── run_all.sh            Runner: executes tests/ in order, gates, log, result table
├── tde_evidence.sh       Collect / compare evidence sets (V$ snapshots + fingerprints)
├── tde_clone.sh          Clone the prod DB into dev via variant a/b1/b2/c
├── block_fingerprint.py  Block-level SHA-256 fingerprint and compare tool
└── tests/
    ├── lib.sh             Shared library sourced by all test scripts
    ├── 00_reset_lab.sh    Reset both services to a clean state
    ├── 10_baseline.sh     Create canary tables, freeze tablespaces, collect baseline
    ├── 15_backup.sh       RMAN backup + stage source keystore
    ├── 20_variant_a.sh    Variant A: plain RESTORE with transported source keystore
    ├── 30_variant_b2.sh   Variant B2: AS ENCRYPTED without prod MEK (expected: ORA-19870)
    ├── 35_variant_b1.sh   Variant B1: AS ENCRYPTED with prod MEK (expected: ORA-00600)
    ├── 40_variant_c.sh    Variant C: DUPLICATE ... AS ENCRYPTED
    ├── 50_variant_d.sh    Variant D: AS DECRYPTED + SET KEY + OFFLINE ENCRYPT
    ├── 60_variant_f.sh    Variant F: chain-breaking path - the only way to get new TEK
    ├── 61_pdb_testbed.sh  PDB testbed: PDBCLONE + CLONE_ENC/CLONE_PLAIN + c##clone user
    ├── 62_pdb_p1_local.sh P1: local clone in same CDB (reference case)
    ├── 63_pdb_p2_archive.sh P2: unplug with ENCRYPT USING, plug into dev CDB
    ├── 64_pdb_p3_nokeys.sh P3: unplug without key export - negative test
    ├── 65_pdb_p4_remote.sh P4: remote clone via DB link + EXPORT/IMPORT KEYS
    ├── 66_pdb_p5_mekrot.sh P5: MEK rotation in target after P2 or P4
    ├── 67_pdb_p6_rekey.sh P6: ONLINE REKEY in target after P2 or P4
    ├── 68_pdb_p7_origin.sh P7: ORIGIN comparison IMPORTED vs LOCAL
    ├── 69_pdb_p8_keyver.sh P8: KEY_VERSION after plug-in to foreign CDB
    ├── 70_variant_g.sh    Variant G: ALTER TABLESPACE ENCRYPTION ONLINE REKEY
    ├── 80_positive_control.sh  Two fresh encrypted tablespaces prove method sensitivity
    └── 90_withdrawal_test.sh   Key withdrawal: remove prod MEK, read canary
```

## Step descriptions

| NR | Script | Purpose | Gate |
|----|--------|---------|------|
| 00 | `00_reset_lab.sh` | Reset both services, wait for DB ready, verify clean logs | none |
| 10 | `10_baseline.sh` | Create canary in USERS (encrypted) and CANARY_PLAIN, set READ ONLY, collect evidence | none |
| 15 | `15_backup.sh` | RMAN backup + stage `ewallet.p12` (not `cwallet.sso`) to `xchange/wallet_prod` | step 10 |
| 20 | `20_variant_a.sh` | RESTORE with transported prod keystore - expects identical ciphertext (dependent on prod MEK) | step 15 |
| 30 | `30_variant_b2.sh` | AS ENCRYPTED without prod MEK - expects ORA-19870/ORA-28374 | step 15 |
| 35 | `35_variant_b1.sh` | AS ENCRYPTED with prod MEK + dev MEK - expects ORA-00600 on encrypted datafile | step 15 |
| 40 | `40_variant_c.sh` | DUPLICATE ... AS ENCRYPTED - must run on pristine Auxiliary (step resets dev first) | step 15 |
| 50 | `50_variant_d.sh` | RESTORE AS DECRYPTED FORCE + SET KEY + OFFLINE ENCRYPT - TEK survives (identical ciphertext) | step 15 |
| 60 | `60_variant_f.sh` | RESTORE + OFFLINE DECRYPT + fresh keystore + discard lost MEK handles + SET KEY + ENCRYPT - new TEK | step 15 |
| 61 | `61_pdb_testbed.sh` | Create PDBCLONE with CLONE_ENC (AES256) and CLONE_PLAIN, canary rows, c##clone user | none |
| 62 | `62_pdb_p1_local.sh` | Local clone PDBCLONE_P1 in same CDB - reference: TEK identical, ORIGIN=LOCAL | step 61 |
| 63 | `63_pdb_p2_archive.sh` | Unplug PDBCLONE with ENCRYPT USING, plug PDBCLONE_P2 into dev - expect TEK preserved, ORIGIN=IMPORTED | step 61 |
| 64 | `64_pdb_p3_nokeys.sh` | Unplug without key export, plug PDBCLONE_P3 into dev - negative test, expect ORA-28374 | step 61 |
| 65 | `65_pdb_p4_remote.sh` | Remote clone PDBCLONE_P4 via DB link (c##clone) + EXPORT/IMPORT KEYS - ORIGIN=IMPORTED | step 61 |
| 66 | `66_pdb_p5_mekrot.sh` | MEK rotation in target PDB - expect re-wrap only (blocks identical) | step 63 or 65 |
| 67 | `67_pdb_p6_rekey.sh` | ONLINE REKEY in target PDB - expect new TEK, blocks differ | step 63 or 65 |
| 68 | `68_pdb_p7_origin.sh` | ORIGIN comparison: IMPORTED (formal import) vs LOCAL (copied keystore) | step 63 or 65 |
| 69 | `69_pdb_p8_keyver.sh` | KEY_VERSION after plug-in to foreign CDB (doc: resets to 0) | step 63 or 65 |
| 70 | `70_variant_g.sh` | ONLINE REKEY on clone - new TEK, different ciphertext | step 15 |
| 80 | `80_positive_control.sh` | Two fresh encrypted tablespaces prove method detects TEK difference | none |
| 90 | `90_withdrawal_test.sh` | Remove prod MEK from dev keystore, restart, read canary | none |

## Gates

The runner verifies a state condition before each gated step. If the condition
is not met, it stops and shows the command to resume:

- Steps 15, 20, 30, 35, 40, 50, 60, 70: require `BACKUP_READY=TRUE` in the state
  file (written by step 15). Missing: run step 15 first.
- Steps 20-70 also require `SOURCE_DBID` (written by step 10).
- Steps 62-65 (PDB P1-P4): require `PDBCLONE_READY=TRUE` (written by step 61).
  These steps can run independently of the RMAN series; both odbencprod and
  odbencdev must be running and healthy.
- Steps 66-69 (PDB P5-P8): require `PDB_TARGET_READY=TRUE` (written by step 63
  or step 65). Run step 63 (P2) or step 65 (P4) before these steps.

State file: `data/xchange/evidence/lab_state.env`.

## Running the full suite

```bash
# Preview all steps and gates without touching anything
scripts/tde-verify/run_all.sh --list
scripts/tde-verify/run_all.sh --dry-run

# Full run (both services must be running or reset first)
scripts/tde-verify/run_all.sh --yes

# Resume from step 50 after a failure at step 50
scripts/tde-verify/run_all.sh --from 50 --yes

# Run only one step
scripts/tde-verify/run_all.sh --only 60 --yes

# Run from step 20 to step 50
scripts/tde-verify/run_all.sh --from 20 --to 50 --yes
```

## Running a single step

Every test script is standalone. It checks its own prerequisites before running:

```bash
# Dry-run a single step
scripts/tde-verify/tests/20_variant_a.sh --dry-run

# Run with auto-confirm
scripts/tde-verify/tests/20_variant_a.sh --yes

# Run with verbose output
scripts/tde-verify/tests/60_variant_f.sh --yes --verbose
```

## Key falltraps embedded in the scripts

- **Servicename**: Oracle registers `FREE.oradba.ch`, not `FREE`. `tnsping` on the
  wrong service name reports OK but the connection fails with ORA-12514.
- **Online redo log collision**: after restoring the source controlfile, the target's
  existing redo log files collide (ORA-19698). The scripts quarantine them via
  `xchange/stale_redo_<service>/` before recovery.
- **SET UNTIL SEQUENCE**: RMAN requires `SET UNTIL SEQUENCE <last+1> THREAD 1` to
  avoid RMAN-06054 when the backup does not include the current online log.
- **LOCAL auto-login keystore**: `cwallet.sso` is host-bound. After transport to
  another host it stays CLOSED with ORA-28365. Only `ewallet.p12` travels; the
  clone recreates auto-login locally. A foreign `cwallet.sso` also blocks
  `CREATE LOCAL AUTO_LOGIN KEYSTORE` with ORA-46630.
- **RESTORE AS DECRYPTED needs FORCE**: without `FORCE`, the restore optimisation
  skips already-present datafiles and the run looks successful without decrypting.
- **`_db_discard_lost_masterkey` must be set in the PDB**: `SCOPE=MEMORY` at CDB
  level fails with ORA-28355. `SCOPE=SPFILE` + restart silently has no effect.
  Only `ALTER SYSTEM SET "_db_discard_lost_masterkey"=TRUE SCOPE=MEMORY` executed
  inside the PDB works.
- **DUPLICATE requires a pristine Auxiliary**: step 40 always resets odbencdev before
  calling RMAN DUPLICATE.

## Evidence layout

Each step writes evidence to `data/xchange/evidence/<label>/`:

```text
data/xchange/evidence/
├── lab_state.env               Key-value state shared between steps
├── baseline/                   Step 10: source key chain + fingerprints
│   ├── keyproof_cdb.log        ssenc_keyproof.sql from CDB$ROOT
│   ├── keyproof_pdb.log        ssenc_keyproof.sql from the PDB
│   ├── <datafile>.fp           Block fingerprints
│   ├── plaintext_<df>.log      Plaintext scan (marker absent = encrypted)
│   └── manifest.txt
├── baseline_plain/             Step 10: control tablespace
├── variant_a/                  Step 20
├── variant_c/                  Step 40
├── variant_d/                  Step 50
├── variant_f/                  Step 60
├── pdb_baseline/               Step 61: PDBCLONE/CLONE_ENC key chain + fingerprints
├── pdb_p1_local/               Step 62: PDBCLONE_P1 in prod
├── pdb_p2_archive/             Step 63: PDBCLONE_P2 in dev (archive plug-in)
├── pdb_p3_nokeys/              Step 64: negative test evidence
├── pdb_p4_remote/              Step 65: PDBCLONE_P4 in dev (remote clone)
├── pdb_p5_mekrot/              Step 66: after MEK rotation
├── pdb_p6_rekey/               Step 67: after ONLINE REKEY
├── variant_g/                  Step 70
├── ctrl_enc_a/                 Step 80: positive control tablespace A
├── ctrl_enc_b/                 Step 80: positive control tablespace B
└── run_<timestamp>.log         Runner log
```

## Interpreting block comparison results

<!-- markdownlint-disable MD013 -->
| Differing blocks | Interpretation |
|---|---|
| Only blocks 0-1 (header) differ | Re-wrap: TEK unchanged, only wrapped under a new MEK |
| Majority of allocated blocks differ | Re-encrypt: new TEK, blocks genuinely rewritten |
| 0 blocks differ | Identical ciphertext: same TEK and same data |
<!-- markdownlint-restore -->

Measured results from the Gruene-Wiese-Lauf (2026-09-03):

| Variant | Canary blocks identical | TEK | Key chain |
|---|---|---|---|
| A: plain RESTORE | 313/313 | unchanged | dependent on prod MEK |
| B1: AS ENCRYPTED + prod MEK | RMAN ORA-00600 | n/a | n/a |
| B2: AS ENCRYPTED, no prod MEK | RMAN ORA-19870 | n/a | n/a |
| C: DUPLICATE AS ENCRYPTED | 313/313 | unchanged | dependent on prod MEK |
| D: AS DECRYPTED + SET KEY + ENCRYPT | 313/313 | unchanged | MEK rotated, TEK survives |
| F: chain-breaking path | 0/313 identical | NEW TEK | independent |
| G: ONLINE REKEY | 2560/2561 differ | NEW TEK | independent |
| Positive control | 367/501 differ | different | confirms method sensitivity |

## PDB clone test series (steps 61-69)

The PDB clone series answers a different question than the RMAN restore variants: what
happens to TDE key provenance when a PDB moves between CDBs via cloning or archive
transport?

### Variants

<!-- markdownlint-disable MD013 -->
| Variant | Step | Transport method | Key transport | Expected ORIGIN |
|---|---|---|---|---|
| Testbed | 61 | n/a | n/a | LOCAL (native) |
| P1 | 62 | Local clone (same CDB) | Shared keystore | LOCAL |
| P2 | 63 | Archive plug-in (ENCRYPT USING) | Bundled in archive | IMPORTED |
| P3 | 64 | Archive plug-in (plain) | None | n/a - negative test |
| P4 | 65 | Remote clone via DB link | Explicit EXPORT/IMPORT | IMPORTED |
| P5 | 66 | MEK rotation in target | n/a | IMPORTED (unchanged) |
| P6 | 67 | ONLINE REKEY in target | n/a | IMPORTED (new TEK) |
| P7 | 68 | ORIGIN comparison | n/a | informational |
| P8 | 69 | KEY_VERSION after plug-in | n/a | informational |
<!-- markdownlint-restore -->

### Key findings

- **P1 (local clone)**: the clone shares the CDB keystore, so `v$encryption_keys.ORIGIN`
  stays `LOCAL` and the ENCRYPTEDKEY (wrapped TEK) is identical to the source.
- **P2 (archive with key transport)**: `UNPLUG INTO ... ENCRYPT USING '<secret>'` bundles
  the key. After `CREATE PLUGGABLE DATABASE ... USING ... DECRYPT USING '<secret>'`,
  `ORIGIN=IMPORTED` - the key provenance is visible in the data dictionary.
- **P3 (archive without key transport)**: the PDB plugs in but the encrypted tablespace
  is inaccessible. Expected errors: ORA-28374 (key missing), ORA-28365, or ORA-65025.
  This step exits 0 - the error is the result.
- **P4 (remote clone via DB link)**: `CREATE PLUGGABLE DATABASE ... FROM pdb@db_link`
  creates the PDB; a subsequent explicit `EXPORT KEYS / IMPORT KEYS` moves the key.
  Result: `ORIGIN=IMPORTED`, same as P2 but using a different transport path.
- **P5 (MEK rotation)**: `ADMINISTER KEY MANAGEMENT SET KEY` re-wraps the TEK under a
  new MEK. MASTERKEYID changes, ENCRYPTEDKEY changes, but block ciphertext is unchanged.
- **P6 (ONLINE REKEY)**: `ALTER TABLESPACE ... ENCRYPTION ONLINE REKEY` creates a new TEK
  and rewrites all data blocks in a new datafile. KEY_VERSION increases; block ciphertext
  differs from pdb_baseline (genuine re-encryption).
- **Transported LOCAL keystore**: a `cwallet.sso` carried over from another host is bound
  to that host's identity. It opens read-only but blocks `CREATE LOCAL AUTO_LOGIN KEYSTORE`
  with ORA-46630. The fix is to move the foreign `.sso` aside and regenerate auto-login
  at the target.
- **KEY_VERSION after plug-in**: Oracle documentation states KEY_VERSION may reset to 0
  after a PDB is plugged into a different CDB. Step 69 measures the actual value.

### Service name

The service name for `tnsping`, SQL\*Net connections, and DB link targets is
`FREE.oradba.ch`, not `FREE`. `tnsping FREE` succeeds even when the full service name
is wrong - do not use it as a connectivity proof.

### c##clone user

The remote clone (P4) uses a dedicated common user `c##clone` with
`CREATE SESSION` and `CREATE PLUGGABLE DATABASE ... CONTAINER=ALL`. This user is
created in step 61 and dropped/recreated idempotently on each testbed run.
