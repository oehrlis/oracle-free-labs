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
| 70 | `70_variant_g.sh` | ONLINE REKEY on clone - new TEK, different ciphertext | step 15 |
| 80 | `80_positive_control.sh` | Two fresh encrypted tablespaces prove method detects TEK difference | none |
| 90 | `90_withdrawal_test.sh` | Remove prod MEK from dev keystore, restart, read canary | none |

## Gates

The runner verifies a state condition before each gated step. If the condition
is not met, it stops and shows the command to resume:

- Steps 15, 20, 30, 35, 40, 50, 60, 70: require `BACKUP_READY=TRUE` in the state
  file (written by step 15). Missing: run step 15 first.
- Steps 20-70 also require `SOURCE_DBID` (written by step 10).

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
