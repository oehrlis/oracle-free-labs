# Messwerte des E2E-Laufs vom 2026-09-06

Quelle: `artefacts/tde-e2e-run-20260906.log`, ein durchgehender Lauf 00 bis 90,
21 von 21 Schritten bestanden, Dauer 27 Minuten.

**Diese Datei ist die einzige zulaessige Quelle fuer Zahlen in der
Dokumentation.** Werte, die hier nicht stehen, gehoeren nicht in ein Dokument.

## Ausgangswerte

| Objekt | MASTERKEYID | ENCRYPTEDKEY |
|---|---|---|
| Prod `USERS` (Baseline, Schritt 10) | `EC574AF166934D45AB5AC1F2267A297A` | `059EFEB1BB6D72140B68FD768F80105B37BB912E84E6273E82227A027FD830F3` |
| Prod `PDBCLONE.CLONE_ENC` (Schritt 61) | `A7D954A5F5B9423D8C4EF9084DAE347D` | `FC11003A257C8515095D64B4E961E7328964A6DE12A90D729147009A85E38760` |

## RMAN-Wege

| Variante | MASTERKEYID danach | ENCRYPTEDKEY danach | Canary-Bloecke | Aussage |
|---|---|---|---|---|
| A `RESTORE` | unveraendert | unveraendert | 313 identisch / 0 | Schluessel bleibt |
| B1 `AS ENCRYPTED USING KEY` mit Prod-MEK | - | - | - | bricht ab, `ORA-00600` |
| B2 `AS ENCRYPTED USING KEY` ohne Prod-MEK | - | - | - | bricht ab, `ORA-19870` / `ORA-28374` |
| C `DUPLICATE ... AS ENCRYPTED` | unveraendert | unveraendert | 313 identisch / 0 | Schluessel bleibt |
| D `AS DECRYPTED` + `SET KEY` + `OFFLINE ENCRYPT` | `DC68C44C673F402CB782CFF2D329ADC4` | `74D071CF0CC7E0A5B8F313C995484943EB7D84DE8B01BAEFC02F5FE56457C926` | 313 identisch / 0 | Re-wrap, Chiffrat unveraendert |
| F Discard-Pfad, Database Key erneuert | `C7A38A0C0653495F882671BF2ED974A3` | `A0BB56AF4790B1C12B2F21D8263CBBE470EA04CDCBE7DCE5A062F6C177D8E2AC` | 0 identisch / 313 | **neues Schluesselmaterial** |
| G `ONLINE REKEY` | - | - | 0 identisch / 313 | **neues Schluesselmaterial**, `KEY_VERSION 1 -> 2` |

## PDB-Wege

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

## Kontrollen

| Kontrolle | Messwert | Aussage |
|---|---|---|
| Positivkontrolle, zwei Tablespaces gleichen Inhalts unter verschiedenen Keys | 0 identisch / 313 | die Methode erkennt einen Schluesselwechsel |
| Entzugstest nach Variante G | Datenbank oeffnet nicht, bleibt `MOUNTED` mit `ORA-28374` | ohne den Quell-MEK ist nicht ein Tablespace unlesbar, sondern die ganze Datenbank unbrauchbar |

## Betriebsbefunde aus dem Lauf

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
