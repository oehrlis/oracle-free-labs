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
Beide greift `.gitignore` (`*.log`) - nicht versioniert. Protokoll:
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
