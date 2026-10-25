# Messwerte der TDE-Verifikationslaeufe

**Diese Datei ist die einzige zulaessige Quelle fuer Zahlen in der
Dokumentation.** Werte, die hier nicht stehen, gehoeren nicht in ein Dokument.

Sie enthaelt **mehrere Laeufe**, je in einem eigenen Abschnitt mit Datum und
Lauf-Kennung im Titel. Schluessel-IDs sind pro Lauf neu, und Blockzahlen
beziehen sich auf unterschiedliche Datafiles - **keine Zahl darf ueber
Abschnittsgrenzen hinweg verglichen oder gemischt werden.** Wer eine Zahl
zitiert, nennt den Lauf dazu.

## Messwerte des E2E-Laufs vom 2026-09-06

Quelle: `artefacts/tde-e2e-run-20260906.log`, ein durchgehender Lauf 00 bis 90,
21 von 21 Schritten bestanden, Dauer 27 Minuten.

### Ausgangswerte 2026-09-06

| Objekt | MASTERKEYID | ENCRYPTEDKEY |
|---|---|---|
| Prod `USERS` (Baseline, Schritt 10) | `EC574AF166934D45AB5AC1F2267A297A` | `059EFEB1BB6D72140B68FD768F80105B37BB912E84E6273E82227A027FD830F3` |
| Prod `PDBCLONE.CLONE_ENC` (Schritt 61) | `A7D954A5F5B9423D8C4EF9084DAE347D` | `FC11003A257C8515095D64B4E961E7328964A6DE12A90D729147009A85E38760` |

### RMAN-Wege 2026-09-06

| Variante | MASTERKEYID danach | ENCRYPTEDKEY danach | Canary-Bloecke | Aussage |
|---|---|---|---|---|
| A `RESTORE` | unveraendert | unveraendert | 313 identisch / 0 | Schluessel bleibt |
| B1 `AS ENCRYPTED USING KEY` mit Prod-MEK | - | - | - | bricht ab, `ORA-00600` |
| B2 `AS ENCRYPTED USING KEY` ohne Prod-MEK | - | - | - | bricht ab, `ORA-19870` / `ORA-28374` |
| C `DUPLICATE ... AS ENCRYPTED` | unveraendert | unveraendert | 313 identisch / 0 | Schluessel bleibt |
| D `AS DECRYPTED` + `SET KEY` + `OFFLINE ENCRYPT` | `DC68C44C673F402CB782CFF2D329ADC4` | `74D071CF0CC7E0A5B8F313C995484943EB7D84DE8B01BAEFC02F5FE56457C926` | 313 identisch / 0 | Re-wrap, Chiffrat unveraendert |
| F Discard-Pfad, Database Key erneuert | `C7A38A0C0653495F882671BF2ED974A3` | `A0BB56AF4790B1C12B2F21D8263CBBE470EA04CDCBE7DCE5A062F6C177D8E2AC` | 0 identisch / 313 | **neues Schluesselmaterial** |
| G `ONLINE REKEY` | - | - | 0 identisch / 313 | **neues Schluesselmaterial**, `KEY_VERSION 1 -> 2` |

### PDB-Wege 2026-09-06

| Fall | MASTERKEYID danach | ENCRYPTEDKEY danach | Canary-Bloecke | Aussage |
|---|---|---|---|---|
| P1 lokaler Klon | `A7D954A5...347D` **unveraendert** | `A341ABA714216D48A156995247C13AC058D67B07E62CA9812642E6C7382FA239` | 0 identisch / 313 | **neues Material** - bei gleichem MEK kein Re-wrap moeglich |
| P2 Archiv-Transport in fremde CDB | `A7D954A5...347D` unveraendert | `FC11003A...8760` **unveraendert** | 313 identisch / 0 | Schluessel und Chiffrat erhalten |
| P3 Unplug ohne Key-Export | - | - | - | `ORA-46680`, Oracle verweigert das Unplug, kein Archiv entsteht |
| P4 Remote-Klon via DB-Link | `A7D954A5...347D` **unveraendert** | `F19A97984D1DA8EBFEEE076E9C11D365B6AFE027EA3C8172630A4368BC4FE608` | 0 identisch / 313 | **neues Material** |
| P5 MEK-Rotation, Tablespace READ ONLY | Tablespace zeigt weiter auf `A7D954A5...347D` | unveraendert | 313 identisch / 0 | read-only bleibt an den Quellschluessel gebunden |
| P5 MEK-Rotation, Tablespace READ WRITE | `EFDFB56CEFC94900AD4D5A6D836EDC5F` | `3BA00862D0CF075555E19B082EB622EDA9D17F5B321E6159D0E2F89CD1D9AC36` | 313 identisch / 0 | Re-wrap, Chiffrat unveraendert |
| P6 `ONLINE REKEY` in der PDB | `EFDFB56C...DC5F` | `9D876AE771F96273105E81BB7298FC51052A380DEF7B6DB2B4A67D2B5E026C87` | 0 identisch / 313 | **neues Material**, `KEY_VERSION 0 -> 1` |
| P7 Herkunft des transportierten Schluessels | - | - | - | `ORIGIN = LOCAL` im Ziel, obwohl per `EXPORT`/`IMPORT KEYS` aus Prod transportiert |
| P8 `KEY_VERSION` nach Plug-in | - | - | - | unveraendert 0; der dokumentierte Reset auf 0 wurde **nicht beobachtet** |

### Kontrollen 2026-09-06

| Kontrolle | Messwert | Aussage |
|---|---|---|
| Positivkontrolle, zwei Tablespaces gleichen Inhalts unter verschiedenen Keys | 0 identisch / 313 | die Methode erkennt einen Schluesselwechsel |
| Entzugstest nach Variante G | Datenbank oeffnet nicht, bleibt `MOUNTED` mit `ORA-28374` | ohne den Quell-MEK ist nicht ein Tablespace unlesbar, sondern die ganze Datenbank unbrauchbar |

### Betriebsbefunde 2026-09-06

- **Verschluesseltes Undo bricht den Discard-Pfad.** Nach `OFFLINE DECRYPT` sind
  die Daten lesbar, die Undo-Saetze aus der Zeit davor haengen aber weiter am
  Quellschluessel. Nach dem Keystore-Austausch scheitert die naechste Operation
  mit `ORA-28304` auf dem **Undo-Datafile**. `V$ENCRYPTED_TABLESPACES` meldet
  dabei korrekt 0 Zeilen - Undo taucht dort nicht auf.
- **Jede PDB-Operation ueber verschluesselte Tablespaces verlangt das
  Keystore-Passwort** (`ORA-46697`), lokaler Klon, Remote-Klon und Einpluggen
  gleichermassen. Ein Auto-Login-Keystore genuegt fuer keine davon.
- **`V$ENCRYPTION_KEYS.CON_ID` ist die Container-ID zum Erzeugungszeitpunkt**,
  nicht die aktuelle. Jeder Unplug/Plug-Zyklus aendert die con_id der PDB.
  Schluesselauswahl ueber die aktuelle con_id trifft den falschen oder gar
  keinen Schluessel. `EXPORT KEYS` innerhalb einer PDB ist mit `ORA-65040`
  gesperrt.
- **Ein Auto-Login-Keystore laesst sich nicht per SQL schliessen**
  (`ORA-28389`), und der Speicherkontext ueberlebt das Loeschen der Dateien.
  Nur ein Instanz-Neustart entfernt ihn.
- **Das Transport-Secret verlangt doppelte Anfuehrungszeichen.** Einfache
  ergeben `ORA-00922` bei `ENCRYPT USING` und `ORA-46609` bei `WITH SECRET`.

## Messwerte des manuellen Laufs vom 2026-09-10 - nicht Teil der Suite

**Andere Messung, andere Zahlen.** Dieser Abschnitt gehoert nicht zum E2E-Lauf vom
2026-09-06 oben. Er stammt aus einem von Hand gefahrenen Lauf **ausserhalb** der
automatisierten Suite. Keine Zahl aus diesem Abschnitt darf mit einer Zahl aus dem
Abschnitt darueber verglichen oder vermischt werden - Schluessel-IDs sind pro Lauf
neu, und die Canary-Blockzahlen der Suite (313) haben mit den hier gemessenen
Datafile-Blockzahlen (6401) nichts zu tun.

Belege:

- `artefacts/p4b-experiment-20260910_171555.log` - Testbed und Remote-Klon ohne
  Key-Import
- `artefacts/p4b-setkey-20260910_185928.log` - die beiden `SET KEY`-Laeufe und die
  Blockvergleiche

Gegenstand: Ziel-PDB `PDBCLONE_P4B` in der Dev-CDB, Tablespace `CLONE_ENC`, geklont
aus der Quell-PDB `PDBCLONE`. Frage: haengt das Ziel nach einem Remote-Klon am Master
Key der Quelle?

### Schluesselkette ueber die vier Stufen (manueller Lauf 2026-09-10)

<!-- markdownlint-disable MD013 MD060 -->
| Stufe | MASTERKEYID | gewrappter Tablespace-Schluessel |
|---|---|---|
| Quell-PDB `PDBCLONE` | `EDFEDD10AA204295A661E896A6566C30` | `B94E4B6C8DD99C5BE7D6AD613DFA4AB82148F8CA16FC09013817372A999562A0` |
| nach dem Remote-Klon | `EDFEDD10...` unveraendert, weiter der Quellschluessel | `127E86CD273CA5AC1952B19F97E34FD3E42F5E84917CDAAB358C7905BD769275` neu |
| nach `SET KEY`, Tablespace READ ONLY | `EDFEDD10...` unveraendert | `127E86CD...` unveraendert |
| nach READ WRITE und erneutem `SET KEY` | `4E7C6CED26084FE2890515571405DFF0` eigener | `C6F33FFF6AD9632AF2D709445AC24E117E39530559592654B243DFAE8917EAEA` |
<!-- markdownlint-restore -->

### Weitere Befunde desselben Laufs (2026-09-10)

- Der Klon lief **ohne** `EXPORT KEYS` und **ohne** `IMPORT KEYS`. Danach lag der
  Master Key der Quelle trotzdem im Ziel-Keystore, unter `CON_ID 4` und mit
  `ORIGIN = LOCAL`. Der Klon transportiert den Schluessel selbst.
- Die Markertabelle lieferte auf jeder Stufe 5000 Zeilen.
- Blockvergleich des Ziel-Datafiles vor und nach der abschliessenden Rotation:
  6401 Bloecke verglichen, **6400 identisch, 1 abweichend - Block 1**, der Header.
  Ein Re-wrap, keine Neuverschluesselung.
- Blockvergleich vor und nach dem ersten `SET KEY` (Tablespace READ ONLY):
  6401 verglichen, 6401 identisch, 0 abweichend.
- Nach der abschliessenden Rotation verweist im Ziel kein verschluesselter
  Tablespace und kein Database Key mehr auf den Quell-MEK.
- `CLONE_ENC` war im Ziel `READ ONLY`, aus der Quelle geerbt. Genau deshalb hat der
  erste `SET KEY` den Tablespace-Schluessel nicht neu gewrappt.

## Messwerte des E2E-Laufs vom 2026-09-11 - `run_20260911_080723`

**Eigener Lauf, eigene Zahlen.** Schluessel-IDs sind pro Lauf neu. Keine ID aus
diesem Abschnitt darf mit einer ID aus dem 2026-09-06-Lauf oder dem manuellen
Lauf vom 2026-09-10 vermischt werden. Vergleichbar sind allein die
**Canary-Blockzahlen** (313) und die strukturellen Aussagen.

Belege: `artefacts/run_20260911_080723.log` (Evidence) und
`artefacts/run_20260911_080723-stdout.log` (vollstaendig, mit Ergebnistabelle).
Beide sind **versioniert** - die `.gitignore`-Ausnahme `!artefacts/run_*.log` wurde
mit v1.2.2 ergaenzt, weil das Protokoll einen der Logs als seine Quelle nennt und
die Angabe sonst im Repo nicht aufloest. Protokoll:
`doc/tde-e2e-protokoll.md`.

21 von 21 Schritten bestanden, Dauer 23 Minuten (08:07 bis 08:35).

### Ausgangswerte 2026-09-11

| Objekt | MASTERKEYID | ENCRYPTEDKEY |
|---|---|---|
| Prod `USERS` (Baseline, Schritt 10) | `448E89AB65BE4992959E6C866A4B4907` | `7C410458C6D61BBDAFBE556CD21EEE9BD71CA73898BFEC48EFFADDBD0E112BC6` |
| Prod `PDBCLONE.CLONE_ENC` (Schritt 61) | `BEE197456D8547F089D5872876526609` | `7EBC0EB57A3EA2B32D7AFB691DFAD56509048E004C281543D01A46709F331FF6` |

### RMAN-Wege 2026-09-11

<!-- markdownlint-disable MD013 MD060 -->

| Variante | MASTERKEYID danach | ENCRYPTEDKEY danach | Canary-Bloecke | Aussage |
|---|---|---|---|---|
| A `RESTORE` | unveraendert | unveraendert | 313 identisch / 0 | Schluessel bleibt |
| B1 mit Prod-MEK | - | - | - | bricht ab, `ORA-00600 [kcbtse_encdec_tbsblk_1]` |
| B2 ohne Prod-MEK | - | - | - | bricht ab, `ORA-19870` / `ORA-28374` |
| C `DUPLICATE ... AS ENCRYPTED` | unveraendert | unveraendert | 313 identisch / 0 | Schluessel bleibt, neue DBID `1515728338` (Quelle `1515727551`) |
| D `AS DECRYPTED` + `SET KEY` + `OFFLINE ENCRYPT` | `B951544D5CFC462AACB45628B948CBAD` | `E5DA70D44292035C9E6224BA33811034382D052417D970C8097F46F0089F2775` | 313 identisch / 0 | Re-wrap, Chiffrat unveraendert |
| F Discard-Pfad | `A13F3C285D0941AB87CA336ACEB984E9` | `B3B88E7A376465A3A8C34E0662AF215B9810840BC53C5ED2B077BBD917FAA7AB` | 0 identisch / 313 | **neues Schluesselmaterial** |
| G `ONLINE REKEY` | - | - | 0 identisch / 313 | **neues Schluesselmaterial**, `KEY_VERSION 1 -> 2` |

<!-- markdownlint-restore -->

### PDB-Wege 2026-09-11

<!-- markdownlint-disable MD013 MD060 -->

| Fall | MASTERKEYID danach | ENCRYPTEDKEY danach | Canary-Bloecke | Aussage |
|---|---|---|---|---|
| P1 lokaler Klon | `BEE19745...6609` **unveraendert** | `378916194479E62498DC2BFFFB690BCEE0CDD1C936188EAF91A085C895D406A3` | 0 identisch / 313 | **neues Material** |
| P2 Archiv-Transport | `BEE19745...6609` unveraendert | `7EBC0EB5...31FF6` **unveraendert** | 313 identisch / 0 | Schluessel und Chiffrat erhalten, `ORIGIN=LOCAL`, `KEY_VERSION=0` |
| P3 Unplug ohne Key-Export | - | - | - | `ORA-46680`, kein Archiv entsteht |
| P4 Remote-Klon | `BEE19745...6609` **unveraendert** | `F71B01BBC38C7587A55CF6304D850C4E64E4CEF9CE08AE3974A05409B584D07E` | 0 identisch / 313 | **neues Material** |
| P5 MEK-Rotation, `READ ONLY` | bleibt `BEE19745...6609` | unveraendert | 313 identisch / 0 | read-only bleibt am Quellschluessel |
| P5 MEK-Rotation, `READ WRITE` | `8B828291FCC648C89C318FC5B6572D5F` | `B237E4A768BC65F696217A3697DBFDCC2068D3440A5F3BD6455148F60AAC85DF` | 313 identisch / 0 | Re-wrap, Chiffrat unveraendert |
| P6 `ONLINE REKEY` in der PDB | `8B828291...2D5F` unveraendert | `FD108CE38CF976D95DE05193CCA676374D9E61BA96190855FC4B945D2B40C365` | 0 identisch / 313 | **neues Material**, `KEY_VERSION 0 -> 1` |
| P7 Herkunft | - | - | - | `ORIGIN = LOCAL` im Ziel trotz `EXPORT`/`IMPORT KEYS` |
| P8 `KEY_VERSION` nach Plug-in | - | - | - | unveraendert 0; Reset auf 0 erneut **nicht beobachtet** |

<!-- markdownlint-restore -->

### Kontrollen 2026-09-11

| Kontrolle | Messwert | Aussage |
|---|---|---|
| Positivkontrolle | 0 identisch / 313 | die Methode erkennt einen Schluesselwechsel |
| Entzugstest nach Variante G | Datenbank oeffnet nicht, bleibt `MOUNTED` mit `ORA-28374` | ganze Datenbank unbrauchbar, nicht nur ein Tablespace |

Gesamtblockzahlen zur Einordnung, **nicht** zur Beurteilung: Variante A 1271
identisch / 1290 abweichend von 2561. Der 2026-09-06-Lauf mass 1269 / 1292. Die
Differenz liegt in nie benutzten Bloecken und ist bedeutungslos - beurteilt wird
allein die Marker-Blockzahl 313.

### Neue Befunde 2026-09-11

- **`ORA-46655` beim Key-Import nach dem Remote-Klon (P4, Schritt 65).**
  `no valid keys in the file from which keys are to be imported`, in Phase 6 des
  Schritts. Der Import findet nichts, **weil der Remote-Klon den Master Key
  bereits selbst ins Ziel-Keystore getragen hat** - ohne `EXPORT KEYS`, ohne
  `IMPORT KEYS`, mit `ORIGIN = LOCAL`. Das ist die Bestaetigung des Befunds aus
  dem manuellen Lauf vom 2026-09-10 auf einem anderen Codepfad, diesmal
  innerhalb der automatisierten Suite. Der Schritt laeuft danach korrekt durch.
- **Konsequenz: der PDB-Klon allein trennt nicht.** Er erneuert den
  Tablespace-Schluessel, wickelt ihn aber unter dem **Quell-MEK** ein. Erst eine
  MEK-Rotation im Ziel trennt - und die greift bei `READ ONLY` nicht, siehe P5.
- **`ORA-28365` tritt im automatisierten Weg nicht auf, und das ist Absicht.**
  `15_backup.sh:21-23` stellt die Bedingung bewusst nicht her: nur `ewallet.p12`
  wird transportiert, `cwallet.sso` nicht, weil ein LOCAL-Auto-Login-Keystore
  host-gebunden ist und auf einem anderen Host mit `ORA-28365` aufgeht. Der
  **manuelle** Runbook-Weg kopiert das ganze Wallet-Verzeichnis und laeuft
  deshalb hinein (`STATUS CLOSED`, `WALLET_TYPE UNKNOWN`, Abhilfe
  `SET KEYSTORE OPEN FORCE KEYSTORE`). Beide Wege sind korrekt; sie
  unterscheiden sich im Aufbau, nicht im Ergebnis.
- Die fuenf `ORA-19912` im Log sind **keine Fehler**, sondern Kommentarzeilen in
  den RMAN-Skripten. Ein Zaehlen von `ORA-`-Codes ueber das Log hinweg
  ueberschaetzt die Fehlerzahl entsprechend.

## Messwerte des E2E-Laufs vom 2026-09-11 - `run_20260911_093022`

**Eigener Lauf, eigene Zahlen.** Auch dieser Lauf hat eigene Schluessel-IDs. Keine
ID aus diesem Abschnitt darf mit einer ID aus `run_20260911_080723`, dem
2026-09-06-Lauf oder dem manuellen Lauf vom 2026-09-10 vermischt werden - die
beiden Laeufe vom 2026-09-11 sind zwei getrennte Messungen am selben Tag.
Vergleichbar sind allein die **Canary-Blockzahlen** (313) und die strukturellen
Aussagen.

Belege: `artefacts/run_20260911_093022.log` (Evidence) und
`artefacts/run_20260911_093022-stdout.log` (vollstaendig, mit Ergebnistabelle).
Beide sind ueber die `.gitignore`-Ausnahme `!artefacts/run_*.log` versioniert.

21 von 21 Schritten bestanden, Dauer 26 Minuten (09:30 bis 09:56). Prod-DBID
`1515732537`.

### Ausgangswerte 2026-09-11 093022

<!-- markdownlint-disable MD013 MD060 -->

| Objekt | MASTERKEYID | ENCRYPTEDKEY |
|---|---|---|
| Prod `USERS` (Baseline, Schritt 10) | `F502DFF545904BBEA20853017F84BE39` | `FF27143DE967554706317B6691C471226EA029147FF3E1905F29270F341846BC` |
| Prod `PDBCLONE.CLONE_ENC` (Schritt 61) | `64CB07B4027B4409B5035BED495E0DFA` | `3C6BE579296ECB9A77EFE8D88E32A9D8B3141A6B6F56E3786F2D66D9912EC0A3` |

<!-- markdownlint-restore -->

### RMAN-Wege 2026-09-11 093022

<!-- markdownlint-disable MD013 MD060 -->

| Variante | MASTERKEYID danach | ENCRYPTEDKEY danach | Canary-Bloecke | Aussage |
|---|---|---|---|---|
| A `RESTORE` | unveraendert | unveraendert | 313 identisch / 0 | Schluessel bleibt, Klon-DBID `1515732537` wie Quelle |
| B1 mit Prod-MEK | - | - | - | **nicht gemessen** - der Schritt bricht vor RMAN ab mit `--key is required for variant b1` |
| B2 ohne Prod-MEK | - | - | - | bricht ab, `ORA-19870` / `ORA-28374` |
| C `DUPLICATE ... AS ENCRYPTED` | unveraendert | unveraendert | 313 identisch / 0 | Schluessel bleibt, neue DBID `1515733343` (Quelle `1515732537`) |
| D `AS DECRYPTED` + `SET KEY` + `OFFLINE ENCRYPT` | `D59390F4B7C64DE58DCCF5B6041D1C28` | `0BD4854AC09E1B1FB84D3D208CBAE2C8A8BE77DC4EF7E7B918C4643B1F32D087` | 313 identisch / 0 | Re-wrap, Chiffrat unveraendert |
| F Discard-Pfad | `62586FEB47EC4863979C5D4D5C5A27ED` | `D6627397B86CDCFE6091EB82B49CD1AB0F1F294F4F138A23F095CE8B342BB187` | 0 identisch / 313 | **neues Schluesselmaterial** |
| G `ONLINE REKEY` | `F502DFF5...BE39` unveraendert | `618E5A9A7752BABC772D0E8BD5D7D7436E88C0B8C8D09458B6EBB67525E8F68C` | 0 identisch / 313 | **neues Schluesselmaterial**, `KEY_VERSION 1 -> 2` |

<!-- markdownlint-restore -->

### PDB-Wege 2026-09-11 093022

<!-- markdownlint-disable MD013 MD060 -->

| Fall | MASTERKEYID danach | ENCRYPTEDKEY danach | Canary-Bloecke | Aussage |
|---|---|---|---|---|
| P1 lokaler Klon | `64CB07B4...0DFA` **unveraendert** | `F33A907E275234A4CD4B556FE7F9EB3E3E5E1C2DA3F31AC05002A1CB6C90CC40` | 0 identisch / 313 | **neues Material** |
| P2 Archiv-Transport | `64CB07B4...0DFA` unveraendert | `3C6BE579...C0A3` **unveraendert** | 313 identisch / 0 | Schluessel und Chiffrat erhalten, `ORIGIN=LOCAL`, `KEY_VERSION=0` |
| P3 Unplug ohne Key-Export | - | - | - | `ORA-46680`, kein Archiv entsteht |
| P4 Remote-Klon | `64CB07B4...0DFA` **unveraendert** | `5B61ADAB9E6AFEC8D8C5ECCA2C5DEC5808FE2BCA751D93AD85BA37FCB4140283` | 0 identisch / 313 | **neues Material**, `ORIGIN=LOCAL` |
| P5 MEK-Rotation, `READ ONLY` | bleibt `64CB07B4...0DFA` | unveraendert | 313 identisch / 0 | read-only bleibt am Quellschluessel |
| P5 MEK-Rotation, `READ WRITE` | `97CF49F6610C4D81AB99E9816AAC4051` | `1DB777897118476F708550634C3D027521EE70150AB2CB142281201B726F9BC6` | 313 identisch / 0 | Re-wrap, Chiffrat unveraendert |
| P6 `ONLINE REKEY` in der PDB | `97CF49F6...4051` unveraendert | `A9BBC531203D39AAD9431C057880344A643CD7B55620F724A9910009615129A9` | 0 identisch / 313 | **neues Material**, `KEY_VERSION 0 -> 1` |
| P7 Herkunft | - | - | - | `ORIGIN = LOCAL` im Ziel trotz `EXPORT`/`IMPORT KEYS` |
| P8 `KEY_VERSION` nach Plug-in | - | - | - | unveraendert 0; Reset auf 0 erneut **nicht beobachtet** |

<!-- markdownlint-restore -->

Die MEK-Rotation in P5 lief ueber drei Schluessel:
`64CB07B4027B4409B5035BED495E0DFA` -> `051318493F524ACB94476A0C9B5BC405` ->
`97CF49F6610C4D81AB99E9816AAC4051`. Der Tablespace folgte erst nach `READ WRITE`.

### Kontrollen 2026-09-11 093022

| Kontrolle | Messwert | Aussage |
|---|---|---|
| Positivkontrolle | 0 identisch / 313 | die Methode erkennt einen Schluesselwechsel |
| Entzugstest nach Variante G | Datenbank oeffnet nicht, bleibt `MOUNTED` mit `ORA-28374` | ganze Datenbank unbrauchbar, nicht nur ein Tablespace |

Gesamtblockzahlen zur Einordnung, **nicht** zur Beurteilung: Variante A 1271
identisch / 1290 abweichend von 2561. Beurteilt wird allein die
Marker-Blockzahl 313.

### Neue Befunde 2026-09-11 093022

- **Variante B1 wurde in diesem Lauf nicht gemessen.** Schritt 35 bricht in
  `tde_clone.sh` ab, bevor RMAN startet: `ERROR --key is required for variant b1`.
  Die Zeile `VERDICT: PASS - RMAN failed as expected (exit 1): ORA-00600 on
  encrypted source datafile` ist ein fest hinterlegter Text, kein Messwert - im
  ganzen Log steht kein einziges `ORA-00600` aus der Datenbank. Der Schritt
  zaehlt trotzdem als `PASS`. Die B1-Zeile in der Tabelle oben belegt deshalb
  nichts ueber das Verhalten von `AS ENCRYPTED USING KEY`.
- **`ORA-46655` beim Key-Import nach dem Remote-Klon (P4, Schritt 65)**, wie im
  Lauf `run_20260911_080723`: `no valid keys in the file from which keys are to
  be imported`, in Phase 6 des Schritts. Der Remote-Klon hat den Master Key
  bereits selbst ins Ziel-Keystore getragen, mit `ORIGIN = LOCAL`. Der Schritt
  laeuft danach korrekt durch. Damit ist der Befund auf einem zweiten Lauf
  reproduziert.
- Die fuenf `ORA-19912` im Log sind **keine Fehler**, sondern Kommentarzeilen in
  den RMAN-Skripten - identische Zahl wie im Lauf `run_20260911_080723`.
- `ORA-28365` tritt auch hier nicht auf; der automatisierte Weg transportiert
  nur `ewallet.p12`, nicht `cwallet.sso`.

## Messwerte der Einzellaeufe vom 2026-10-24 - B1, B2, Schritt 45, Schritt 72

**Eigene Laeufe, eigene Zahlen.** Neue Basis (Schritte 00, 10, 15), neue
Schluessel-IDs. Keine ID aus diesem Abschnitt darf mit einer ID aus den
Abschnitten darueber vermischt werden. Vergleichbar sind allein die
Canary-Blockzahlen (313) und die strukturellen Aussagen.

Belege, alle unter `artefacts/` und ueber `!artefacts/run_*.log` versioniert,
Secret-Pruefung nach `artefacts/README.md` je Datei `0`:

<!-- markdownlint-disable MD013 MD060 -->

| Log | Inhalt |
|---|---|
| `artefacts/run_20261024_081906.log` | Basis: 00, 10, 15, je `PASS` (Zeilen 73, 646, 792) |
| `artefacts/run_20261024_082444.log` | Schritt 35, Variante B1 |
| `artefacts/run_20261024_082753.log` | Schritt 30, Variante B2 |
| `artefacts/run_20261024_090859.log` | Schritt 45, Fehlversuch: `STARTUP FORCE` mit offener Auxiliary-PDB |
| `artefacts/run_20261024_092534.log` | Schritt 45, Fehlversuch: `SHUTDOWN IMMEDIATE` mit offener Auxiliary-PDB |
| `artefacts/run_20261024_094125.log` | Schritt 45, gueltiger Lauf |
| `artefacts/run_20261024_095047.log` | Schritt 72, gueltiger Lauf |
| `artefacts/run_20261025_063549.log` | Wiederholung Schritt 30 mit der finalen Skriptrevision |
| `artefacts/run_20261025_063809.log` | Wiederholung Schritt 35 mit der finalen Skriptrevision |
| `artefacts/run_20261025_064027.log` | Wiederholung Schritt 45 mit der finalen Skriptrevision |
| `artefacts/run_20261025_064340.log` | Wiederholung Schritt 72 mit der finalen Skriptrevision |

<!-- markdownlint-restore -->

Prod-DBID `1519529852`, Prod `USERS` `MASTERKEYID`
`D8D7BB0F7DA7460CACFBFBB60198DBA1`, `ENCRYPTEDKEY`
`894916F8682E723C4EFF5BD8A35050AD85A54A35746019670CABDAC8CE2AFFD2`
(`run_20261024_081906.log:641-643`).

### B1 - `AS ENCRYPTED USING KEY` mit Prod-MEK, erstmals per Skript gemessen

- Bis 2026-10-23 hat `tde_clone.sh` fuer `b1` den Prod-MEK **gar nicht**
  importiert (nur ein Hinweis "separate documented step"). Jeder geskriptete
  B1-Lauf waere damit ein verkappter B2-Lauf gewesen. Seit 2026-10-24 merged
  `merge_source_keystore` den gestagten Prod-Keystore per `MERGE KEYSTORE ...
  INTO EXISTING KEYSTORE` in den Dev-Keystore: `MERGE_OK`
  (`run_20261024_082444.log:52`), Keystore danach `OPEN` / `PASSWORD`
  (`:143`).
- Das erste Backup-Set (Datafiles 1, 3, 7, 11 der CDB, unverschluesselt) wurde
  restauriert, `elapsed time: 00:00:03` (`:201-210`). Die Laufzeit von 5:45 aus
  dem manuellen Lauf ist hier **nicht** reproduziert; ob `AS ENCRYPTED` diese
  Dateien tatsaechlich verschluesselt hat, ist nicht pruefbar, weil der Restore
  danach abbricht.
- Beim Backup-Set mit Datafile 20 (`USERS`, verschluesselt, `:217`):
  `ORA-19870` plus `ORA-00600: internal error code, arguments:
  [kcbtse_encdec_tbsblk_1], [4], [2], [1244], [18], [1244], [20],
  [4294967295], [0], [0], [], []` (`:227-228`). Das Argument `[20]` entspricht der Datafile-Nummer von `USERS`.
- Verdict `PASS` aus der RMAN-Zeile abgeleitet, nicht aus festem Text
  (`:244`). **Damit steht `kcbtse` erstmals in einem Log unter `artefacts/`.**
  Die Argumente 3 und 5 (`1244`) weichen vom manuellen Lauf (`806`) ab; die
  Struktur ist identisch.

### B2 - `AS ENCRYPTED USING KEY` ohne Prod-MEK

- Abbruch bereits beim **ersten** Backup-Piece `024ojrp4_2_1_1`, also beim Set
  mit den CDB-Datafiles 1, 3, 7, 11 (`:197-201`), die alle zu unverschluesselten
  Tablespaces gehoeren (`CDB$ROOT` `SYSTEM`, `SYSAUX`, `USERS`, `UNDOTBS1` mit
  `ENC NO`, `run_20261024_095047.log:296-307`): `ORA-19870` plus
  `ORA-28374: typed master key not found in wallet`
  (`run_20261024_082753.log:208-210`), Verdict `PASS` (`:226`).
- `30_variant_b2.sh` leitet das Verdict seit 0.2.0 aus der Ausgabe ab; vorher
  genuegte jeder Exit-Code ungleich 0, wie bei B1 vor 2026-09-22. 0.2.0
  akzeptierte noch `ORA-19870` **oder** `ORA-28374` - `ORA-19870` allein steht
  aber auch in der B1-Signatur (`ORA-19870` + `ORA-00600`). Seit 0.3.0 verlangt
  `PASS` `ORA-28374` und kein `ORA-00600`; `ORA-00600` ist `FAIL` ("source key
  present - this is B1"). Der Lauf vom 2026-10-24 erfuellt auch die strengere
  Regel (`run_20261024_082753.log:209-210`, kein `ORA-00600` im Log).

### Schritt 45 - PDB-Klon aus einem restaurierten Auxiliary

- Auxiliary nach dem Restore: `USERS` haengt am Prod-MEK
  `D8D7BB0F...DBA1` (`run_20261024_094125.log:382`), Canary 5000 Zeilen
  (`:316`). `READ ONLY` ist dort nicht protokolliert; belegt ist es fuer die
  Baseline (`run_20261024_081906.log:643`) und fuer dasselbe restaurierte
  `USERS` in Schritt 72 (`run_20261024_095047.log:307`).
- Dev-MEK in `CDB$ROOT` `CD13CEB06BE943EC973D0DEDE1949481`, in der
  Auxiliary-PDB `0664705EC4554DBE91737247B5AB23BE` (`:525-526`).
- Klon `PDBAUX_CLONE`: `USERS` unter `0664705E...23BE`, `ENCRYPTEDKEY`
  `BBCC75A99A1413FDACE1307F07883FD5D84FFFC391F84684C07EF846976B00CD`
  (`:662`, `:795`); Canary-Bloecke Auxiliary gegen Klon
  `identical 0 differing 313 total 313` (`:793`) - neues Schluesselmaterial.
- Entzug: neuer Keystore nur mit den zwei Dev-MEKs (`:854-855`). Danach oeffnet
  die CDB `READ WRITE` (`:890`), der Klon liest den Canary
  (`READABLE - all rows decrypt`, `:950`), die Auxiliary-PDB nicht:
  `File 20 not verified due to error ORA-28374` (`:1008`). Verdict `PASS`
  (`:1027`).
- **Antwort:** ein PDB-Klon aus einem restaurierten Auxiliary bekommt neues
  Tablespace-Schluesselmaterial unter dem Dev-MEK und uebersteht den Entzug des
  Quell-MEK; die Auxiliary-PDB scheitert. Einschraenkung: Auxiliary und Klon in
  derselben CDB mit einem Keystore (Lab hat zwei Container).

Befunde aus den Fehlversuchen desselben Tages:

- **Beobachtung:** mit offener Auxiliary-PDB blieb die CDB nach dem Entzug
  `MOUNTED` mit `ORA-28374`, nach `STARTUP FORCE`
  (`run_20261024_090859.log:871`, `:878`) wie nach `SHUTDOWN IMMEDIATE` +
  `STARTUP` (`run_20261024_092534.log:870`, `:877`). **Ursache nicht
  isoliert (Hypothese):** dass die offene abhaengige PDB das Oeffnen der ganzen
  CDB verhindert, stuetzt sich auf das Alert-Log, das als fehlenden Schluessel
  den Prod-PDB-MEK in Container 4 nannte - live gelesen, **nicht** in einem
  versionierten Log - und auf den Folgelauf, der `CLOSE IMMEDIATE` und
  `DISCARD STATE` gleichzeitig einfuehrte. Mit vorher geschlossener PDB oeffnet
  die CDB `READ WRITE` (`run_20261024_094125.log:890`), und nur die Daten dieser
  PDB scheitern (`ORA-01187` `:986`, Alert-Log `:1008`); der Klon liest (`:950`).
- **Leerer Keystore != Keystore ohne den Quellschluessel.** Mit leerem
  Keystore-Verzeichnis oeffnet dieselbe CDB `READ WRITE`, Wallet-Status
  `NOT_AVAILABLE` (`run_20261024_090859.log:826-834`). Ein Entzugstest, der den
  Keystore nur wegnimmt, unterscheidet abhaengig und unabhaengig deshalb nicht
  am Open-Mode.
- **Fehlender Tablespace-Schluessel zeigt sich in der Session als `ORA-01187`**
  ("failed verification tests"), nicht als `ORA-28374`. Die Ursache steht nur
  im Alert-Log (`ORA-01187` `run_20261024_094125.log:986`, `File 20 not
  verified due to error ORA-28374` `:1008`). Seit `lib.sh` 0.3.0 zaehlt nur eine
  Alert-Log-Zeile, die waehrend des Versuchs geschrieben wurde und die Datei aus
  `ORA-01110` nennt.
- Nach dem Restore ist der CDB-Tempfile `temp01.dbf` (Datei 1025) unbrauchbar
  (`ORA-01187`), `ADD TEMPFILE` scheitert an ihm mit `ORA-01122`/`ORA-01203`;
  erst `DROP` dann `ADD` geht. Eine neu geklonte PDB hat den Keystore
  `CLOSED` / `UNKNOWN` (`ORA-28365`), bis er erneut mit Passwort geoeffnet
  wird. Beides in Schritt 45 behoben. Die Logs dieser zwei Fehlversuche hat die
  erste Session geloescht - die Befunde sind damit **unbelegt** (siehe
  `tasks/lessons.md`, 2026-10-25).

### Schritt 72 - Rekey aller verschluesselten Tablespaces, `SET KEY` je Container, Entzug

- Vorher: einziger verschluesselter Tablespace `ODBENCPROD.USERS` unter
  `D8D7BB0F...DBA1`, `KEY_VERSION 1` (`run_20261024_095047.log:288`);
  Container Database Keys unter den Prod-MEKs `C6DF452C3A9343329106BEA81BD3B0CA`
  (`CDB$ROOT`) und `D8D7BB0F...DBA1` (`ODBENCPROD`) (`:315`, `:317`).
  `SYSTEM`, `SYSAUX`, `UNDOTBS1`, `TEMP` in beiden Containern unverschluesselt
  (`:291-309`).
- Nach `READ WRITE`, `SET KEY` in `CDB$ROOT` und in `ODBENCPROD` und
  `ONLINE REKEY` von `USERS`: `USERS` unter `256E49C63EA347DEAE6101B4A746618D`,
  `KEY_VERSION 2`, `ENCRYPTEDKEY` `384F426D...C2AB` (`:377`); Database Keys
  unter den neuen MEKs `B0E568695FCF4CE2AB1B70A6E5503334` und `256E49C6...618D`
  (`:404`, `:406`) - `SET KEY` wrappt den Database Key also um.
- Probes `ALTER TABLESPACE ... ENCRYPTION ONLINE REKEY` auf den
  **unverschluesselten** `SYSTEM`, `SYSAUX`, `UNDOTBS1`: `Tablespace altered.`
  in beiden Containern (`:428-438`, `:454-464`), die Tablespaces bleiben
  `ENC NO` (`:538`, `:545`). Danach hat der Database Key bei **gleicher**
  `MASTERKEYID` einen anderen gewrappten Wert (`:404` gegen `:556`, `:406`
  gegen `:558`). **Schluss, nicht Messung:** das kann neues Material fuer den
  Database Key sein (Logik wie bei P1), aber ebenso ein erneutes Wrappen
  desselben Schluessels mit neuem IV - der gewrappte Wert allein trennt das
  nicht. `TEMP`: `ORA-28370 ... online encryption not allowed for temp`
  (`:440-444`, `:466-470`).
- `ALTER DATABASE DICTIONARY REKEY CREDENTIALS` als SYSKM in `CDB$ROOT`:
  `ORA-28446 ... missing current encryption key` (`:495`), weil
  `dictionary_credentials_encrypt` `DISABLED` ist (`:486`) - es gibt keinen
  Credential-Schluessel, also nichts zu erneuern. In der PDB als SYSDBA:
  `ORA-28447` (`:519`); eine SYSKM-Session konnte den Container nicht wechseln
  (`ORA-01031` im ersten, verworfenen Lauf - **nicht** in einem versionierten Log).
- Danach referenziert kein Tablespace- und kein Database Key mehr einen
  Quell-MEK (`:575`). Canary-Bloecke gegen Baseline
  `identical 0 differing 313 total 313` (`:763`).
- Entzug: neuer Keystore nur mit den zwei neuen MEKs (`:768`, `:820-821`),
  sauberer Neustart `OPEN_MODE=READ WRITE` (`:849`), Canary
  `READABLE - all rows decrypt` (`:913`). Verdict `PASS` (`:928`).
- **Antwort:** `SET KEY` in **jedem** Container, `ONLINE REKEY` der
  verschluesselten Tablespaces **und** die `ONLINE REKEY`-Probes auf den
  unverschluesselten `SYSTEM`/`SYSAUX`/`UNDOTBS1` zusammen machen ein per RMAN
  restauriertes Ziel unabhaengig vom Quell-MEK - belegt durch den Entzug
  (`READ WRITE` `:849`, Canary lesbar `:913`), nicht durch die
  `v$`-Zeilen. Der Beitrag der Probes ist nicht isoliert. Dass der
  Entzugstest nach Variante G scheiterte, **weil** dort der MEK nie gewechselt
  wurde, ist eine Hypothese; moeglich ist auch derselbe Open-/Saved-State-
  Mechanismus wie in Schritt 45, nicht nachgemessen.

### Wiederholung 2026-10-25 mit der finalen Skriptrevision

Nach den Fixes aus Review 2 (`lib.sh` 0.3.0, `tde_clone.sh` 0.2.0,
`30_variant_b2.sh` 0.3.0, `35_variant_b1.sh` 0.4.0, `45_zdlra_aux_pdb_clone.sh`
0.4.0, `72_rekey_all_withdrawal.sh` 0.2.0) liefen 30, 35, 45 und 72 erneut auf
derselben Basis (Schritte 00/10/15 vom 2026-10-24, Gates erfuellt). **Kein
Verdict hat sich geaendert.** Die Laeufe vom 2026-10-24 bleiben als Belege
erhalten; neue Zahlen ersetzen sie nur, wo unten genannt.

<!-- markdownlint-disable MD013 MD060 -->

| Schritt | 2026-10-24 | 2026-10-25 |
|---|---|---|
| 30 B2 | `PASS`, `run_20261024_082753.log:226` | `PASS`, `ORA-19870` + `ORA-28374` (`run_20261025_063549.log:212-213`), kein `ORA-00600`, Verdict `:229` |
| 35 B1 | `PASS`, `run_20261024_082444.log:244` | `PASS`, `MERGE_OK` `:52`, `ORA-00600 [kcbtse_encdec_tbsblk_1] ... [20]` (`run_20261025_063809.log:227-228`), Verdict `:244` |
| 45 | `PASS`, `run_20261024_094125.log:1027` | `PASS`, Canary `identical 0 differing 313 total 313` (rc 3, `run_20261025_064027.log:741`), Keystore offen ausser `PDB$SEED` (`:541`), Klon `READABLE` (`:899`), Auxiliary `ORA-01187` (`:935`) mit Alert-Log `File 20 not verified due to error ORA-28374` aus dem Versuchsfenster (`:957`), Verdict `:972` |
| 72 | `PASS`, `run_20261024_095047.log:928` | `PASS`, keine Quell-MEK-Referenz (`run_20261025_064340.log:561`), Canary `identical 0 differing 313 total 313` (`:745`), `READ WRITE` nach Entzug (`:833`), Canary `READABLE` (`:897`), Verdict `:910` |

<!-- markdownlint-restore -->

- Der transiente Docker-Desktop-Fehler `mount source path` trat erneut auf und
  wurde mit einem Retry ueberwunden (`run_20261025_063549.log:34-35`).
- Die Schluesselexporte werden auf Mode 600 gesetzt und nach dem Entzug
  geloescht (`run_20261025_064027.log:758`, `:813`;
  `run_20261025_064340.log:760`, `:813`).
- Schritt 72 reproduziert: der gewrappte Database Key aendert sich bei
  gleicher `MASTERKEYID` nach den Probes (`run_20261025_064340.log:390` gegen
  `:542`, `:392` gegen `:544`) - weiterhin Schluss, nicht Messung (siehe oben).
- Schritt 45 reproduziert auch den Negativbefund: die Auxiliary-PDB hat nach
  `SET KEY` (ohne Rekey) ihren `USERS`-Schluessel unter dem Dev-MEK
  (`run_20261025_064027.log:612`) und scheitert nach dem Entzug trotzdem
  (`:935`, `:957`).
