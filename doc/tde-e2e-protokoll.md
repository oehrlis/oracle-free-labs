# TDE Verifikationslauf - Testprotokoll

Erzeugt: 2026-09-06 07:49  
Quelle: `tde-e2e-run-20260906.log`

Dieses Protokoll ist aus dem Lauf-Log abgeleitet und laesst sich jederzeit
aus demselben Log neu erzeugen. Die Zahlen stammen nicht aus einer
Nacherzaehlung, sondern aus den Messzeilen des Laufs.

## Ergebnis

21 von 21 Schritten bestanden.

| Nr | Ergebnis | Dauer | Schritt |
|----|----------|-------|---------|
| 00 | PASS | 293s | Reset both services and verify clean startup |
| 10 | PASS | 6s | Create canary tables, READ ONLY, collect baseline evidence |
| 15 | PASS | 11s | RMAN backup + stage source keystore |
| 20 | PASS | 153s | Variant A: plain RESTORE with transported source keystore |
| 30 | PASS | 138s | Variant B2: AS ENCRYPTED USING KEY without prod MEK |
| 35 | PASS | 127s | Variant B1: AS ENCRYPTED USING KEY with prod MEK |
| 40 | PASS | 154s | Variant C: DUPLICATE ... AS ENCRYPTED |
| 50 | PASS | 159s | Variant D: RESTORE AS DECRYPTED + SET KEY + OFFLINE ENCRYPT |
| 60 | PASS | 175s | Variant F: chain-breaking path (new TEK) |
| 61 | PASS | 10s | PDB testbed: create PDBCLONE with canary tables and c##clone user |
| 62 | PASS | 8s | PDB P1: local clone in same CDB (reference case) |
| 63 | PASS | 154s | PDB P2: unplug with key export, plug into dev CDB |
| 64 | PASS | 3s | PDB P3: unplug without key export - negative test |
| 65 | PASS | 17s | PDB P4: remote clone via DB link as c##clone |
| 66 | PASS | 2s | PDB P7: ORIGIN of the transported key in the target |
| 67 | PASS | 2s | PDB P8: KEY_VERSION after plug-in to foreign CDB |
| 68 | PASS | 12s | PDB P5: MEK rotation in target after P2 or P4 |
| 69 | PASS | 10s | PDB P6: ONLINE REKEY in target after P2 or P4 |
| 70 | PASS | 158s | Variant G: ALTER TABLESPACE ENCRYPTION ONLINE REKEY |
| 80 | PASS | 6s | Positive control: two tablespaces prove method sensitivity |
| 90 | PASS | 2s | Key withdrawal test: verify cryptographic independence |

## Schritte im Detail

### Schritt 00 - Reset both services and verify clean startup

Ergebnis: **PASS**, Dauer 293s

Verdict:

```text
both services are up, healthy, and clean
```

### Schritt 10 - Create canary tables, READ ONLY, collect baseline evidence

Ergebnis: **PASS**, Dauer 6s

Verdict:

```text
baseline collected, MASTERKEYID and TEK saved to state
```

Gemessene Schluesselwerte:

- MASTERKEYID `EC574AF166934D45AB5AC1F2267A297A`
- ENCRYPTEDKEY `059EFEB1BB6D72140B68FD768F80105B37BB912E84E6273E82227A027FD830F3`

Beobachtete Fehlercodes: `ORA-01646`, `ORA-00959`

### Schritt 15 - RMAN backup + stage source keystore

Ergebnis: **PASS**, Dauer 11s

Verdict:

```text
RMAN backup complete, source keystore staged
```

### Schritt 20 - Variant A: plain RESTORE with transported source keystore

Ergebnis: **PASS**, Dauer 153s

Verdict:

```text
TEK IDENTICAL and canary ciphertext IDENTICAL (identical 313 differing 0 total 313) - pure re-wrap, no new TEK
(expected for variant A)
```

Canary-Blockvergleich:

- `identical 313 differing 0 total 313`

Blockvergleich gesamt: `blocks compared 2561, identical 1271, differing 1290`

Gemessene Schluesselwerte:

- MASTERKEYID `EC574AF166934D45AB5AC1F2267A297A`
- ENCRYPTEDKEY `059EFEB1BB6D72140B68FD768F80105B37BB912E84E6273E82227A027FD830F3`

Beobachtete Fehlercodes: `ORA-19912`

### Schritt 30 - Variant B2: AS ENCRYPTED USING KEY without prod MEK

Ergebnis: **PASS**, Dauer 138s

Verdict:

```text
RMAN failed as expected (exit 1): ORA-19870/ORA-28374 without prod MEK
```

Beobachtete Fehlercodes: `ORA-19912`, `RMAN-00571`, `RMAN-00569`, `RMAN-03002`, `ORA-19870`, `ORA-28374`

### Schritt 35 - Variant B1: AS ENCRYPTED USING KEY with prod MEK

Ergebnis: **PASS**, Dauer 127s

Verdict:

```text
RMAN failed as expected (exit 1): ORA-00600 on encrypted source datafile
```

### Schritt 40 - Variant C: DUPLICATE ... AS ENCRYPTED

Ergebnis: **PASS**, Dauer 154s

Verdict:

```text
TEK IDENTICAL and canary ciphertext IDENTICAL (identical 313 differing 0 total 313) - DUPLICATE preserved the
existing TEK, no new TEK for encrypted source
```

Canary-Blockvergleich:

- `identical 313 differing 0 total 313`

Blockvergleich gesamt: `blocks compared 2561, identical 1272, differing 1289`

Gemessene Schluesselwerte:

- MASTERKEYID `EC574AF166934D45AB5AC1F2267A297A`
- ENCRYPTEDKEY `059EFEB1BB6D72140B68FD768F80105B37BB912E84E6273E82227A027FD830F3`

Beobachtete Fehlercodes: `RMAN-05158`

### Schritt 50 - Variant D: RESTORE AS DECRYPTED + SET KEY + OFFLINE ENCRYPT

Ergebnis: **PASS**, Dauer 159s

Verdict:

```text
canary ciphertext IDENTICAL (identical 313 differing 0 total 313) - the OFFLINE DECRYPT/ENCRYPT cycle
reproduces the source ciphertext, so the tablespace key material is unchanged; the differing wrapped TEK is
the re-wrap under the new dev MEK
```

Canary-Blockvergleich:

- `identical 313 differing 0 total 313`

Blockvergleich gesamt: `blocks compared 2561, identical 1406, differing 1155`

Gemessene Schluesselwerte:

- MASTERKEYID `DC68C44C673F402CB782CFF2D329ADC4`
- MASTERKEYID `EC574AF166934D45AB5AC1F2267A297A`
- ENCRYPTEDKEY `74D071CF0CC7E0A5B8F313C995484943EB7D84DE8B01BAEFC02F5FE56457C926`
- ENCRYPTEDKEY `059EFEB1BB6D72140B68FD768F80105B37BB912E84E6273E82227A027FD830F3`

Beobachtete Fehlercodes: `ORA-19912`

### Schritt 60 - Variant F: chain-breaking path (new TEK)

Ergebnis: **PASS**, Dauer 175s

Verdict:

```text
TEK DIFFERS and the canary ciphertext changed with it (identical 0 differing 313 total 313) - new key
material, chain broken. Same OFFLINE ENCRYPT as variant D, which reproduced the ciphertext: the difference is
the renewed Database Key
```

Canary-Blockvergleich:

- `identical 0 differing 313 total 313`

Blockvergleich gesamt: `blocks compared 2561, identical 0, differing 2561`

Gemessene Schluesselwerte:

- MASTERKEYID `C7A38A0C0653495F882671BF2ED974A3`
- MASTERKEYID `EC574AF166934D45AB5AC1F2267A297A`
- ENCRYPTEDKEY `A0BB56AF4790B1C12B2F21D8263CBBE470EA04CDCBE7DCE5A062F6C177D8E2AC`
- ENCRYPTEDKEY `059EFEB1BB6D72140B68FD768F80105B37BB912E84E6273E82227A027FD830F3`

Beobachtete Fehlercodes: `ORA-19912`

### Schritt 61 - PDB testbed: create PDBCLONE with canary tables and c##clone user

Ergebnis: **PASS**, Dauer 10s

Verdict:

```text
PDB testbed ready: PDBCLONE with canary tables and c##clone
```

Gemessene Schluesselwerte:

- MASTERKEYID `A7D954A5F5B9423D8C4EF9084DAE347D`
- ENCRYPTEDKEY `FC11003A257C8515095D64B4E961E7328964A6DE12A90D729147009A85E38760`

Beobachtete Fehlercodes: `ORA-65011`, `ORA-00959`, `ORA-01918`

### Schritt 62 - PDB P1: local clone in same CDB (reference case)

Ergebnis: **PASS**, Dauer 8s

Verdict:

```text
P1 local clone: NEW tablespace key material. The MASTERKEYID is unchanged, so the differing wrapped key cannot
be a re-wrap, and the ciphertext changed with it (identical 0 differing 313 total 313). A PDB clone
re-encrypts - unlike every RMAN path measured
```

Canary-Blockvergleich:

- `identical 0 differing 313 total 313`

Blockvergleich gesamt: `blocks compared 6401, identical 1, differing 6400`

Gemessene Schluesselwerte:

- MASTERKEYID `A7D954A5F5B9423D8C4EF9084DAE347D`
- ENCRYPTEDKEY `A341ABA714216D48A156995247C13AC058D67B07E62CA9812642E6C7382FA239`
- ENCRYPTEDKEY `FC11003A257C8515095D64B4E961E7328964A6DE12A90D729147009A85E38760`

Beobachtete Fehlercodes: `ORA-65011`

### Schritt 63 - PDB P2: unplug with key export, plug into dev CDB

Ergebnis: **PASS**, Dauer 154s

Verdict:

```text
P2: the archive transport preserved both the wrapped key and the ciphertext (identical 313 differing 0 total
313) into a foreign CDB, ORIGIN=LOCAL, KEY_VERSION=0. The opposite of the clone in P1/P4, which renews the key
```

Canary-Blockvergleich:

- `identical 313 differing 0 total 313`

Blockvergleich gesamt: `blocks compared 6401, identical 6400, differing 1`

Gemessene Schluesselwerte:

- MASTERKEYID `A7D954A5F5B9423D8C4EF9084DAE347D`
- ENCRYPTEDKEY `FC11003A257C8515095D64B4E961E7328964A6DE12A90D729147009A85E38760`

Beobachtete Fehlercodes: `ORA-65011`

### Schritt 64 - PDB P3: unplug without key export - negative test

Ergebnis: **PASS**, Dauer 3s

Verdict:

```text
P3: Oracle refuses the keyless unplug outright (ORA-46680, PDB master keys must be exported). No archive is
written, so an encrypted PDB cannot be carried off without the keys at all - the block sits earlier than the
test assumed
```

Beobachtete Fehlercodes: `ORA-46680`

### Schritt 65 - PDB P4: remote clone via DB link as c##clone

Ergebnis: **PASS**, Dauer 17s

Verdict:

```text
P4: remote clone produced NEW tablespace key material (identical 0 differing 313 total 313), ORIGIN=LOCAL. The
MASTERKEYID matches the source, so the differing wrapped key is not a re-wrap. Same behaviour as the local
clone in P1, and the opposite of the archive transport in P2
```

Canary-Blockvergleich:

- `identical 0 differing 313 total 313`

Blockvergleich gesamt: `blocks compared 6401, identical 1, differing 6400`

Gemessene Schluesselwerte:

- MASTERKEYID `A7D954A5F5B9423D8C4EF9084DAE347D`
- ENCRYPTEDKEY `F19A97984D1DA8EBFEEE076E9C11D365B6AFE027EA3C8172630A4368BC4FE608`
- ENCRYPTEDKEY `FC11003A257C8515095D64B4E961E7328964A6DE12A90D729147009A85E38760`

Beobachtete Fehlercodes: `ORA-02024`, `ORA-65011`, `ORA-46655`

### Schritt 66 - PDB P7: ORIGIN of the transported key in the target

Ergebnis: **PASS**, Dauer 2s

Verdict:

```text
P7: the key A7D954A5F5B9423D8C4EF9084DAE347D was transported out of production by EXPORT/IMPORT KEYS, yet the
target reports ORIGIN=LOCAL. Nothing in v$encryption_keys distinguishes a transported production key from one
generated on the spot - the provenance question cannot be answered from the database
```

### Schritt 67 - PDB P8: KEY_VERSION after plug-in to foreign CDB

Ergebnis: **PASS**, Dauer 2s

Verdict:

```text
P8 informational: KEY_VERSION unchanged (0) - doc reset to 0 not observed here
```

### Schritt 68 - PDB P5: MEK rotation in target after P2 or P4

Ergebnis: **PASS**, Dauer 12s

Verdict:

```text
P5: rotating the PDB master key (A7D954A5F5B9423D8C4EF9084DAE347D -> CC4889CC11A0474FAD3431DA9675FB1D ->
EFDFB56CEFC94900AD4D5A6D836EDC5F) left the ciphertext byte-identical in both phases (A: identical 313
differing 0 total 313, B: identical 313 differing 0 total 313). While READ ONLY the tablespace could not be
re-wrapped and kept pointing at the old key A7D954A5F5B9423D8C4EF9084DAE347D; only after READ WRITE did it
follow to EFDFB56CEFC94900AD4D5A6D836EDC5F. A read-only tablespace therefore stays bound to the source master
key across a rotation
```

Canary-Blockvergleich:

- `identical 313 differing 0 total 313`
- `identical 313 differing 0 total 313`

Blockvergleich gesamt: `blocks compared 6401, identical 6401, differing 0`

Gemessene Schluesselwerte:

- MASTERKEYID `A7D954A5F5B9423D8C4EF9084DAE347D`
- MASTERKEYID `EFDFB56CEFC94900AD4D5A6D836EDC5F`
- ENCRYPTEDKEY `F19A97984D1DA8EBFEEE076E9C11D365B6AFE027EA3C8172630A4368BC4FE608`
- ENCRYPTEDKEY `3BA00862D0CF075555E19B082EB622EDA9D17F5B321E6159D0E2F89CD1D9AC36`

### Schritt 69 - PDB P6: ONLINE REKEY in target after P2 or P4

Ergebnis: **PASS**, Dauer 10s

Verdict:

```text
P6: ONLINE REKEY created new key material (KEY_VERSION 0 -> 1) and rewrote the data blocks (identical 0
differing 313 total 313) - the ciphertext in PDBCLONE_P4 no longer matches its own prior state
```

Canary-Blockvergleich:

- `identical 0 differing 313 total 313`

Blockvergleich gesamt: `blocks compared 6401, identical 0, differing 6401`

Gemessene Schluesselwerte:

- MASTERKEYID `EFDFB56CEFC94900AD4D5A6D836EDC5F`
- ENCRYPTEDKEY `3BA00862D0CF075555E19B082EB622EDA9D17F5B321E6159D0E2F89CD1D9AC36`
- ENCRYPTEDKEY `9D876AE771F96273105E81BB7298FC51052A380DEF7B6DB2B4A67D2B5E026C87`

### Schritt 70 - Variant G: ALTER TABLESPACE ENCRYPTION ONLINE REKEY

Ergebnis: **PASS**, Dauer 158s

Verdict:

```text
TEK changed by ONLINE REKEY (1 -> 2) and the canary ciphertext changed with it (identical 0 differing 313
total 313) - new key material, blocks rewritten
```

Canary-Blockvergleich:

- `identical 0 differing 313 total 313`

Blockvergleich gesamt: `blocks compared 2561, identical 0, differing 2561`

Beobachtete Fehlercodes: `ORA-19912`

### Schritt 80 - Positive control: two tablespaces prove method sensitivity

Ergebnis: **PASS**, Dauer 6s

Verdict:

```text
the method is sensitive: identical content under two different tablespace keys produces different ciphertext
in every canary block (identical 0 differing 313 total 313). An 'identical' result elsewhere in the suite
therefore means the key really is unchanged
```

Canary-Blockvergleich:

- `identical 0 differing 313 total 313`

Blockvergleich gesamt: `blocks compared 2561, identical 1421, differing 1140`

Beobachtete Fehlercodes: `ORA-00959`

### Schritt 90 - Key withdrawal test: verify cryptographic independence

Ergebnis: **PASS**, Dauer 2s

Verdict:

```text
the database does not open at all without the source master key: it stops at MOUNTED with ORA-28374.
Dependency is total - not a single tablespace is unreadable, the whole database is unusable
```

Beobachtete Fehlercodes: `ORA-28374`
