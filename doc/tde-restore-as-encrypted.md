# TDE RESTORE AS ENCRYPTED - Verifikationstest

**Anlass:** Kundenfrage vom 2026-09-03
**Status:** Messungen zu den Varianten A, B1, B2 und zum Entschluesselungspfad
abgeschlossen. Variante C nicht gemessen.
**Autor:** Stefan Oehrli

## Fragestellung

Macht `RESTORE DATABASE AS ENCRYPTED USING KEY <mek>` ein echtes Re-encrypt der Datenbloecke
(neues Tablespace-Encryption-Key-Material) oder nur ein Re-wrap des bestehenden TEK im
Datafile-Header?

**Hintergrund:** Ein Kunde moechte seine Produktionsdatenbank (mit TDE-verschluesseltem
`USERS`-Tablespace) in eine Entwicklungsumgebung kopieren. Nach dem Klon sollen weder der
Master Encryption Key (MEK) noch das Tablespace-Encryption-Key-Material aus Prod
wiederverwendbar sein. Kein Rueckschluss auf Prod darf moeglich bleiben.

**Ziel:** Dem Kunden mit messbaren, reproduzierbaren Belegen zeigen, welche RMAN-Klonstrategie
diese Anforderung erfuellt - und welche sie nicht erfuellt.

## Zusammenfassung

Kein RMAN-basierter Klonweg erzeugt neues Tablespace-Encryption-Key-Material. Gemessen wurde:

- **Variante A (normaler RESTORE):** alle 313 Canary-Datenbloecke im Klon byteidentisch zur
  Quelle. `MASTERKEYID`, `KEY_VERSION` und der gewrappte TEK sind identisch, der gewrappte TEK
  liegt physisch an derselben Stelle (Offset 8977). Kein Re-encrypt, kein neuer TEK.
- **Variante B2 (`AS ENCRYPTED USING KEY` ohne Prod-MEK):** Abbruch mit ORA-19870 plus
  ORA-28374. RMAN braucht den Quell-MEK, um die verschluesselten Quellbloecke zu lesen. Ein
  RMAN-Klon ohne Transfer des Prod-Schluessels existiert nicht.
- **Variante B1 (`AS ENCRYPTED USING KEY` mit Prod-MEK und eigenem Ziel-MEK):** die
  unverschluesselten CDB-Datafiles werden korrekt neu verschluesselt (Laufzeit 5:45 in einem Einzellauf gegenueber
  3 Sekunden bei einem normalen Restore, also echte Blockarbeit). Beim ersten bereits
  verschluesselten Datafile bricht RMAN mit ORA-00600
  `[kcbtse_encdec_tbsblk_1]` ab, dreimal reproduziert. Fuer eine bereits verschluesselte
  Produktionsdatenbank ist dieser Weg nicht nutzbar.
- **Entschluesselungspfad (`RESTORE FORCE AS DECRYPTED`, dann eigener MEK, dann
  `ENCRYPTION OFFLINE ENCRYPT`):** funktioniert technisch. Der gewrappte TEK und die
  `MASTERKEYID` im Header sind danach neu und die Prod-Werte physisch nicht mehr im Datafile
  auffindbar. Die 313 Canary-Datenbloecke sind aber weiterhin byteidentisch zur Quelle. Das
  TEK-Material selbst hat den Zyklus ueberlebt, nur seine Verpackung wechselte.
- **Positivkontrolle:** zwei frische verschluesselte Tablespaces mit identischem Inhalt
  unterscheiden sich in 367 von 501 Bloecken. Das Messverfahren erkennt einen TEK-Wechsel also
  zuverlaessig - der Nullbefund oben ist keine Blindheit der Methode.

Neues TEK-Material entsteht nachweislich nur beim Anlegen eines neuen verschluesselten
Tablespace. Fuer die Kundenanforderung "keine Rueckschluesse auf Prod" bedeutet das: ein
RMAN-Klon allein genuegt nicht.

## Variantenvergleich

Die Varianten unterscheiden sich in nur zwei Punkten: dem Zustand des Ziel-Keystores und der
`RESTORE`-Klausel. Alles andere wurde bewusst konstant gehalten, damit ein Unterschied im
Ergebnis nicht aus dem Verfahren stammen kann.

<!-- markdownlint-disable MD013 MD060 -->
| Variante | Datenbloecke gegen Prod | TEK | Prod-MEK beim Klon noetig | Keystore beim Restore offen noetig | Ergebnis | Eignung fuer kryptografische Trennung |
|---|---|---|---|---|---|---|
| A - normaler `RESTORE` | 313 von 313 Canary-Bloecken byteidentisch; gesamt 1269 von 2561 identisch | unveraendert, Prod-TEK unter Prod-MEK | ja, ueber das transportierte Prod-Wallet | nein - ein normaler RESTORE kopiert Chiffrat | erfolgreich | keine |
| B1 - `AS ENCRYPTED USING KEY` mit Prod-MEK | nicht messbar, Abbruch vor dem verschluesselten Datafile | nicht messbar | ja, sonst kein Lesen der Quellbloecke | ja, sonst ORA-28365 | ORA-00600 `[kcbtse_encdec_tbsblk_1]`, dreimal reproduziert | nicht nutzbar |
| B2 - `AS ENCRYPTED USING KEY` ohne Prod-MEK | nicht messbar, Abbruch beim ersten Backup-Piece | nicht messbar | ja - genau dieser fehlende Schluessel ist die Abbruchursache | ja | ORA-19870 plus ORA-28374 | nicht nutzbar |
| C - `DUPLICATE ... AS ENCRYPTED` | nicht gemessen | nicht gemessen | nicht gemessen | nicht gemessen | nicht gemessen | offen |
| D - `AS DECRYPTED` plus `SET KEY` plus `OFFLINE ENCRYPT` | Bloecke 2 bis 1407 einschliesslich aller 313 Canary-Bloecke byteidentisch; gesamt 1406 von 2561 identisch | Material unveraendert, neu gewrappt unter Dev-MEK | ja, fuer den `AS DECRYPTED`-Lauf | ja | erfolgreich | keine fuer die Datenbloecke; die MEK-Abhaengigkeit ist loesbar |
| Positivkontrolle - neuer verschluesselter Tablespace | 367 von 501 Bloecken im Canary-Bereich abweichend, 134 identisch | neues Material | entfaellt | entfaellt | erfolgreich | ja - so sieht ein echter TEK-Wechsel aus |
<!-- markdownlint-restore -->

In Worten: Variante A ist der Ist-Zustand beim Kunden und liefert eine Kopie, die
kryptografisch vollstaendig an Prod haengt - identisches Chiffrat, identischer gewrappter TEK,
identische `MASTERKEYID`. Variante B2 zeigt, dass es keinen RMAN-Weg gibt, der ohne den
Prod-Schluessel auskommt: RMAN muss die Quellbloecke lesen, dazu braucht es den Quell-MEK.
Variante B1 erfuellt genau den dokumentierten Anwendungsfall - unverschluesselte Quelldateien
werden beim Restore verschluesselt, messbar an der Laufzeit von 5:45 gegenueber 3 Sekunden, je Einzellauf -
scheitert aber beim ersten bereits verschluesselten Datafile mit einem internen Fehler.
Variante C wurde nicht gemessen und bleibt offen.

Variante D ist der einzige Weg, der im Lab bis zum Ende durchlief und im Ziel eine neue
Schluesselverpackung hinterliess. Sie loest die Keystore-Abhaengigkeit, nicht aber die
Datenabhaengigkeit: die Canary-Datenbloecke sind nach dem Zyklus wieder Byte fuer Byte
dieselben wie in Prod. Erst die Positivkontrolle - ein neu angelegter verschluesselter
Tablespace - erzeugt Chiffrat, das sich vom Original unterscheidet.

> Benennung: `D` bezeichnet in diesem Protokoll den Entschluesselungspfad. Die Referenzmessung
> mit garantiert neuem TEK ist als Positivkontrolle gefuehrt, weil sie kein Klonverfahren ist,
> sondern die Sensitivitaet des Messverfahrens belegt.

## Zwei-Ebenen-Schluesselarchitektur

Oracle TDE verwendet eine zweistufige Schluessel-Hierarchie:

- **MEK (Master Encryption Key):** liegt im Keystore (Software-Wallet oder HSM). Der aktive MEK
  ist pro CDB eindeutig und wird ueber `V$ENCRYPTION_KEYS` und `V$ENCRYPTION_WALLET` sichtbar.
- **TEK (Tablespace Encryption Key):** generiert beim Anlegen des verschluesselten Tablespace.
  Er liegt nicht im Keystore, sondern im Datafile-Header - dort mit dem MEK gewrappt.
  `V$ENCRYPTED_TABLESPACES.ENCRYPTEDKEY` (RAW) ist dieser gewrappte TEK.
  `V$ENCRYPTED_TABLESPACES.MASTERKEYID` zeigt, welcher MEK ihn aktuell wrappt.

Kein V$-View gibt das rohe TEK-Material preis oder liefert eine TEK-ID, die sich von einem
Re-wrap unterscheiden liesse.

Diagramme zur Hierarchie, zum Keystore-Modus und zum MEK-Lebenslauf stehen im Begleitdokument
[tde-key-architecture.md](tde-key-architecture.md).

### Terminologie-Falle

<!-- markdownlint-disable MD013 MD060 -->
| Operation | Was passiert | TEK veraendert | Datenbloecke neu verschluesselt | Dauer |
|-----------|-------------|----------------|--------------------------------|-------|
| MEK-Rotation (`ADMINISTER KEY MANAGEMENT SET KEY`) | TEK wird im Header neu gewrappt; das TEK-Material bleibt unveraendert | Nein (nur Re-wrap) | Nein | Sekunden |
| `ALTER TABLESPACE ... ENCRYPTION ... ONLINE REKEY` | Datafiles werden Block fuer Block neu geschrieben; neues TEK-Material erzeugt | Ja | Ja | Proportional zur Datenmenge |
<!-- markdownlint-restore -->

## Dokumentationslage

Die nachfolgenden Aussagen beruhen ausschliesslich auf den unter [Quellen](#quellen) gelisteten
Oracle-Dokumenten.

- `RESTORE DATABASE|TABLESPACE AS ENCRYPTED [USING KEY 'key_id']` ist dokumentiert,
  Voraussetzung `COMPATIBLE >= 12.2`. Ohne `USING KEY` nutzt RMAN den aktiven MEK des
  Ziel-Keystores. Quelle: Oracle Backup and Recovery Reference 19c/26ai, RESTORE.
- `DUPLICATE TARGET DATABASE TO <db> AS ENCRYPTED` ist dokumentiert, `COMPATIBLE >= 18.0`.
  Die Doku nennt als Voraussetzung, dass der Source-Keystore auf das Auxiliary-System kopiert
  und geoeffnet ist. Quelle: Oracle Backup and Recovery Reference 19c, DUPLICATE.
- Der Doku-Wortlaut von `DUPLICATE AS ENCRYPTED` adressiert ausdruecklich Quellen, die nicht
  verschluesselt sind ("...that are not encrypted").
- Fuer den Fall verschluesselt zu verschluesselt ist die TEK-Semantik in der oeffentlichen
  Oracle-Doku nicht belegt. Das ist die Luecke, die dieser Test schliesst.
- Kein V$-View zeigt TEK-Material oder eine TEK-ID. `ENCRYPTEDKEY` und `KEY_VERSION` aendern
  sich sowohl bei einem neuen TEK als auch bei einem reinen Re-wrap - sie sind kein
  Unterscheidungsmerkmal allein. `KEY_VERSION` resettet zudem auf 0 nach einem Plug-in in
  eine fremde DB oder nach einer Control-File-Recreation.
- `ALTER TABLESPACE ... ENCRYPTION USING 'AES256' ONLINE REKEY` ist das einzige dokumentierte
  Verfahren fuer neues Tablespace-Key-Material; fuer Spalten zusaetzlich
  `ALTER TABLE ... REKEY`. Verfuegbar seit 12.2.0.1. OFFLINE-Operationen sind laut Doku nicht
  fuer Rekeying vorgesehen. Quelle: Oracle Database Advanced Security Guide 19c, Configuring
  Transparent Data Encryption.
- `ALTER TABLESPACE ... ENCRYPTION ONLINE REKEY` ist in Oracle Database Free nicht unterstuetzt.
  Quelle: Oracle Database Free 26ai, Licensing Restrictions. Die Doku verspricht dafuer
  "independent encryption keys" - gemessen wurde das im Lab daher nicht.
- Ob `ALTER TABLESPACE ... ENCRYPTION OFFLINE DECRYPT` gefolgt von `OFFLINE ENCRYPT` denselben
  TEK wiederverwendet, ist in oeffentlichen Quellen **nicht belegt** - weder bestaetigt noch
  widerlegt. Der Laborbefund byteidentischen Chiffrats (Variante D) steht damit ohne Gegenprobe
  aus der Literatur da.
- In UNITED Mode braucht jede PDB zwingend einen eigenen MEK. Der Keystore wird vom CDB-Root
  verwaltet, muss aber einen fuer die PDB spezifischen TDE-Master-Key enthalten, damit die PDB
  TDE nutzen kann; PDB-Tablespace-Keys werden mit dem PDB-spezifischen MEK gewrappt. Ein
  dokumentierter Weg, mit einem einzigen MEK fuer CDB und PDB zu arbeiten, ist nicht belegt.
  Quelle: Oracle Database Advanced Security Guide 19c, Managing Keystores and Encryption Keys in
  United Mode.
- `TDE_CONFIGURATION` unterscheidet UNITED und ISOLATED **nicht** ueber seinen Wert - beide
  Modi nutzen `KEYSTORE_CONFIGURATION=FILE`. Der Moduswechsel laeuft laut Primaerdoku ueber
  `ADMINISTER KEY MANAGEMENT ISOLATE KEYSTORE ... FROM ROOT KEYSTORE FORCE KEYSTORE ...
  WITH BACKUP` in der PDB und zurueck ueber `UNITE KEYSTORE ... WITH ROOT KEYSTORE`. Eine
  isolierte PDB kann `TDE_CONFIGURATION` danach separat setzen. Quellen: Oracle Database
  Advanced Security Guide 26ai, Administering United Mode; Oracle Database Reference 26ai,
  `TDE_CONFIGURATION`.
- Der dokumentierte Weg bei ORA-28374 ist `MERGE KEYSTORE`, also den fehlenden Schluessel aus
  einem Backup-Wallet in den aktuellen Keystore mergen:
  `ADMINISTER KEY MANAGEMENT MERGE KEYSTORE '<backup>' IDENTIFIED BY <pw> INTO EXISTING
  KEYSTORE '<current>' IDENTIFIED BY <pw> WITH BACKUP;`. Alternativ `IMPORT KEYS` aus einem
  Export. Quelle: Oracle Database Advanced Security Guide 26ai, ORA-28374.
- Nach einem Klon empfiehlt die Oracle-Doku ein REKEY, damit Prod- und Non-Prod-MEK
  auseinanderlaufen. Ausserdem muessen alle historischen Master Keys im transportierten Wallet
  enthalten sein, weil sie zum Wiederherstellen aelterer Backups gebraucht werden. Das stuetzt
  den Hygienepunkt weiter unten: ein kopierter Keystore bringt die vollstaendige
  Schluesselhistorie der Quelle mit.
- Sekundaerquelle (Blog, siehe [Quellen](#quellen)): bereits verschluesselte Bloecke werden beim
  RMAN-Backup unveraendert durchgereicht, nur unverschluesselte Bloecke erhalten
  Backup-Verschluesselung. Das deckt sich mit dem Befund zu Variante A - ein normaler RESTORE
  kopiert Chiffrat verbatim und braucht dafuer keinen Schluessel.
- Oracle Free Limits: 2 CPU, 2 GB RAM, 12 GB User Data.
- `ENABLE_ARCHIVELOG=true` ist Default in der Image-ENV des Free-Containers und wird an DBCA
  als `-enableArchive` durchgereicht (verifiziert per `docker inspect` am Image
  `oracle-free-labs:latest`). Ein eigenes Skript zum Aktivieren von ARCHIVELOG war nicht noetig.

## Beweisstrategie

Der Beweis laeuft nicht ueber Laufzeit, sondern ueber Ciphertext auf Blockebene. Laufzeit waere
kein zuverlaessiges Kriterium, weil RMAN auch bei reinem Re-wrap Metadaten schreibt.

Pro Variante werden vier Nachweise erhoben:

**a) Blockweiser Ciphertext-Vergleich des Datafiles**
Dasselbe Datafile wird in Quelle und Klon Block fuer Block per SHA-256 verglichen. Der
Tablespace wird vor dem Backup auf `READ ONLY` gesetzt, damit die Datenbloecke stabil sind.

- Nur eine Handvoll Header-Bloecke (niedrige Blocknummern) verschieden: Re-wrap - der TEK
  ist unveraendert, nur der gewrappte Eintrag im Header wurde neu geschrieben.
- Fast alle allozierten Bloecke verschieden: Re-encrypt - Bloecke wurden mit neuem
  TEK-Material neu verschluesselt.

Robustheitseigenschaft: Dieser Vergleich braucht keine Annahme ueber Oracles IV-Ableitung
(CFB/XTS), weil im Re-wrap-Fall die Datenbloecke byte-gleich kopiert werden.

**b) Lokalisierung des gewrappten TEK im Datafile**
Die Hex-Bytes aus `V$ENCRYPTED_TABLESPACES.ENCRYPTEDKEY` werden im Datafile gesucht.
Vorher-Nachher zeigt, ob sich der gewrappte TEK im Header geaendert hat. Ergaenzt durch
Oracles eigenen File-Header-Dump.

**c) Schluesselkette aus den V$-Views**
`MASTERKEYID`, `KEY_VERSION` und `ORIGIN` (LOCAL vs IMPORTED) aus `V$ENCRYPTED_TABLESPACES`
und `V$ENCRYPTION_KEYS` - vor und nach dem Klon verglichen.

**d) Entzugstest**
Der Prod-MEK wird aus dem Dev-Keystore entfernt, die Instanz neu gestartet, und die
Canary-Zeilen werden abgefragt. Erst wenn diese Abfrage erfolgreich ist (kein ORA-28365
oder ORA-28374), ist die kryptografische Unabhaengigkeit von Prod belegt.

## Laboraufbau

Oracle AI Database Free 26ai, Image `oracle-free-labs:latest`, aarch64, Docker Desktop.

### Services

<!-- markdownlint-disable MD013 MD060 -->
| Service | Profile | Port | Rolle | PDB | DBID | Beschreibung |
|---------|---------|------|-------|-----|------|-------------|
| `odbencprod` | `odbencprod` | 1532 | Produktion (Klon-Quelle) | `ODBENCPROD` | 1515066983 | Eigener Software-Keystore, eigener MEK, TDE, verschluesselter `USERS`-Tablespace, SCOTT-Schema mit Canary-Daten, `LOG_MODE` ARCHIVELOG |
| `odbencdev` | `odbencdev` | 1533 | Entwicklung (Klon-Ziel) | - | 1515067722 vor dem Klon | Eigener Software-Keystore, eigener MEK, keine Nutzdaten, Ziel fuer alle Klon-Varianten |
<!-- markdownlint-restore -->

Beide Container nutzen denselben internen `WALLET_ROOT`-Pfad `/opt/oracle/dbconfig/FREE/wallet`,
der aber auf getrennte Host-Verzeichnisse zeigt - genau die Kundenkonstellation. Memory-Limit
je Container: 3 GB (`ODBENCPROD_DB_MEM=3g`, `ODBENCDEV_DB_MEM=3g`).

**Gemeinsamer Austausch-Mount:** `data/xchange` wird in beiden Containern als
`/opt/oracle/xchange` eingehaengt. Darueber werden RMAN-Backupsets und Wallet-Exports
ausgetauscht.

### Keystore-Modus

Gemessen an `odbencprod`: Modus UNITED. Genau ein Keystore-Verzeichnis `WALLET_ROOT/tde` plus
`tde_seps` und `backups`, kein PDB-eigenes Keystore-Verzeichnis. `KEYSTORE_MODE=UNITED` fuer die
PDB, `TDE_CONFIGURATION=KEYSTORE_CONFIGURATION=FILE` nur auf CDB-Ebene gesetzt - die PDB hat
keinen eigenen Wert und erbt. Im gemeinsamen Keystore liegen zwei MEKs: einer von `CDB$ROOT`
erzeugt und aktiviert, einer von `ODBENCPROD`. Dass beide Container einen eigenen MEK haben,
entspricht der Doku: in UNITED Mode braucht jede PDB einen PDB-spezifischen Master Key, und die
Tablespace-Keys der PDB werden mit diesem gewrappt.

Der Wert von `TDE_CONFIGURATION` ist **nicht** das Unterscheidungsmerkmal zwischen UNITED und
ISOLATED - beide Modi nutzen `KEYSTORE_CONFIGURATION=FILE`. Umgeschaltet wird laut Primaerdoku
mit `ADMINISTER KEY MANAGEMENT ISOLATE KEYSTORE ... FROM ROOT KEYSTORE FORCE KEYSTORE ...
WITH BACKUP` in der PDB und zurueck mit `UNITE KEYSTORE ... WITH ROOT KEYSTORE`. Erst eine
isolierte PDB kann `TDE_CONFIGURATION` sinnvoll separat setzen.

### Canary-Daten

Schema `SCOTT`, Tabelle `CANARY_TDE`, 5000 Zeilen, deterministischer Payload (kein Zufallswert,
damit ein Blockvergleich ueber Testlaeufe hinweg stabil bleibt). Kontrollgruppe
`SCOTT.CANARY_PLAIN_TAB` im unverschluesselten Bigfile-Tablespace `CANARY_PLAIN`, ebenfalls
5000 Zeilen.

## Werkzeuge

<!-- markdownlint-disable MD013 MD060 -->
| Datei | Zweck |
|-------|-------|
| `scripts/tde-verify/block_fingerprint.py` | Block-Level-Fingerabdruck und Vergleich von Oracle-Datafiles. Subkommandos: `fingerprint` (SHA-256 je Block, wahlweise in Datei), `compare` (zwei Fingerabdruck-Dateien gegenueberstellen; `--rewrap-threshold` legt fest, bis zu wie vielen abweichenden Bloecken das Ergebnis als Header-Re-wrap gilt), `scan-plaintext` (Klartext-Marker im Datafile suchen; `--expect-absent` schlaegt fehl, wenn der Marker gefunden wird), `find-hex` (bekannte Byte-Sequenz lokalisieren, z.B. `ENCRYPTEDKEY`), `hexdump` (einzelnen Block hexdumpen). |
| `scripts/tde-verify/tde_evidence.sh` | Orchestrierungsskript fuer die Beweissammlung. Ruft `ssenc_keyproof.sql` in `CDB$ROOT` und der PDB auf, listet verschluesselte Tablespace-Datafiles mit Blockgroesse, erstellt Fingerabdruck-Dateien und fuehrt optional einen Klartext-Scan durch. Mit `--compare` werden zwei Evidence-Sets gegenuebergestellt. Ablage unter `data/xchange/evidence/<label>/`. |
| `scripts/tde-verify/tde_clone.sh` | Fuehrt eine Klonvariante (`a`, `b1`, `b2`, `c`) aus. Nur Wallet-Vorbereitung und `RESTORE`-Klausel unterscheiden sich, alles andere ist konstant. Enthaelt die im Lab noetigen Korrekturen: Quarantaene der veralteten Online-Redo-Logs, `SET CONTROLFILE AUTOBACKUP FORMAT`, explizites Oeffnen des Keystores und `SET UNTIL SEQUENCE`. Variante `c` ist nicht implementiert. |
| `config/common/scripts/ssenc_keyproof.sql` | Evidence-Snapshot der TDE-Schluesselhierarchie. Zeigt MEK-Identitaet, `MASTERKEYID`, `KEY_VERSION`, `ORIGIN` (LOCAL/IMPORTED) und den gewrappten TEK (`ENCRYPTEDKEY`). Muss in `CDB$ROOT` und in der PDB ausgefuehrt werden; die verschluesselten Tablespace-Eintraege liegen im PDB-Container. Hinweis laut Script-Header: `ENCRYPTEDKEY` aendert sich sowohl bei neuem TEK als auch bei reinem Re-wrap und beweist daher allein nicht, dass Datenbloecke neu verschluesselt wurden. |
| `config/common/scripts/csenc_canary.sql` | Legt die Canary-Tabelle an. Parameter: Owner, Tablespace, Marker-String, Zeilenanzahl, Tabellenname. Jede Zeile enthaelt den Marker, damit ein Klartext-Scan falsifizierbar ist. Der Tabellenname ist Parameter, damit derselbe Canary zweimal gebaut werden kann: einmal im verschluesselten, einmal im unverschluesselten Tablespace. Gibt `RELATIVE_FNO` und `BLOCK_NUMBER` zurueck. |
| `config/common/scripts/ssenc_canary.sql` | Liest die Canary-Tabelle nach einem Klon oder nach dem Entzugstest zurueck. Verwendet absichtlich kein `WHENEVER SQLERROR EXIT`, damit ein ORA-28365 oder ORA-28374 im Log erscheint und als Messergebnis erhalten bleibt. |
| `config/common/scripts/ssenc_filehdr.sql` | Dump der Datafile-Header und eines gewaehlten Blocks ueber Oracles eigenes Tracing, als zweite Quelle neben der Host-Analyse. Parameter: Datafile-Pfad, Blocknummer. Oracle benennt die Felder, der Hexdump belegt die Bytes. |
<!-- markdownlint-restore -->

## Messungen

### Phase 0 - Prod-Baseline auf odbencprod

Messsatz `data/xchange/evidence/baseline/`, gemessen 2026-09-03.

#### Vorgehen

Canary-Tabelle anlegen und Tablespace auf `READ ONLY` setzen:

```sql
-- In PDB ODBENCPROD als SYSDBA
@/opt/oracle/common/scripts/csenc_canary.sql SCOTT USERS OEHRLI-CANARY-01 5000 CANARY_TDE
ALTER TABLESPACE USERS READ ONLY;
```

Schluesselkette sichern und Evidence-Set erstellen:

```bash
scripts/tde-verify/tde_evidence.sh \
  -s odbencprod -p ODBENCPROD -l baseline -m 'OEHRLI-CANARY-01'
```

#### Ergebnis

Tablespace `USERS`: bigfile, AES256, `CIPHERMODE` XTS, TS# 6, 2560 Bloecke, 20971520 Byte.
Das Datafile ist 20979712 Byte gross, also 2561 Bloecke bei 8192 Byte Blockgroesse.

<!-- markdownlint-disable MD013 MD060 -->
| Messwert | Wert |
|---|---|
| `MASTERKEYID` | 8A27589796A248BE95222E59407FF962 |
| `KEY_VERSION` | 1 |
| gewrappter TEK (`ENCRYPTEDKEY`) | BAD537ADDD695BEE7A29F6F27B65A03D6F195CCE3388AD0119D718087A8AFA55 |
| MEK `CDB$ROOT` | `KEY_ID` AbyhIcXQQk+XiBYrKzrI3FY..., `ORIGIN` LOCAL, con_id 1 |
| MEK PDB | `KEY_ID` AYonWJeWoki+lSIuWUB/+WI..., `ORIGIN` LOCAL, con_id 4 |
| Canary `SCOTT.CANARY_TDE` | 5000 Zeilen, Segment 384 Bloecke / 3145728 Byte, 313 belegte Bloecke, Bereich 979 bis 1407 |
| Kontrollgruppe `SCOTT.CANARY_PLAIN_TAB` | 5000 Zeilen, 313 Bloecke, Bereich 779 bis 1279, Tablespace `CANARY_PLAIN` unverschluesselt |
| Klartext-Scan | 313 Treffer im unverschluesselten Datafile ab Block 779, 0 Treffer im verschluesselten |
| gewrappter TEK physisch | Offset 8977 = Block 1 Byte 785, genau 1 Treffer im verschluesselten Datafile, 0 in der Kontrolldatei |
| `MASTERKEYID` physisch | Offset 9025 = Block 1 Byte 833, genau 1 Treffer im verschluesselten Datafile, 0 in der Kontrolldatei |
<!-- markdownlint-restore -->

Rechnerisch verifiziert: `KEY_ID` ist base64 des `MASTERKEYID` mit vorangestelltem Typbyte
`0x01`.

Der Hexdump von Block 1 zeigt die Struktur direkt: Laengenbyte `04`, dann 32 Byte gewrappter
TEK, dann Fuellbytes, dann 16 Byte `MASTERKEYID` im Klartext. Der Abstand von 48 Byte zwischen
TEK-Beginn und `MASTERKEYID` erklaert sich damit als 32 Byte Schluessel plus 16 Byte Fuellbytes.

Die 313 Treffer aus dem Rohdatei-Scan decken sich mit den 313 belegten Bloecken aus
`DBMS_ROWID`. Damit ist die Block-zu-Offset-Rechnung unabhaengig bestaetigt.

Impliziter Database Key fuer `SYSTEM`, `UNDO` und `TEMP` aus `V$DATABASE_KEY_INFO`: RAW(48),
9FA346CD92BF77F2967675FD236BF54B56A5834859447E5CA76D9BE659B724DF plus Nullbytes, unter derselben
`MASTERKEYID`, `CIPHERMODE` XTS.

`USERS` und `CANARY_PLAIN` wurden vor dem Backup auf `READ ONLY` gesetzt. Das RMAN-Backup liegt
in `/opt/oracle/xchange/backup`, das Controlfile-Autobackup heisst
`cf_c-1515066983-20260903-00`.

Merkposten fuer die Auswertung: `DBMS_ROWID.ROWID_RELATIVE_FNO` liefert bei Bigfile-Tablespaces
0, waehrend `DBA_DATA_FILES.RELATIVE_FNO` 1024 meldet. Das ist erwartetes Bigfile-Verhalten -
`ROWID_BLOCK_NUMBER` traegt dann die vollstaendige absolute Blocknummer, was fuer die
Offset-Rechnung genau passt.

### Variante A - Normaler RESTORE mit transportiertem Prod-Wallet

**Hypothese:** Identischer Ciphertext, `MASTERKEYID` gleich Prod-MEK,
Entzugstest schlaegt fehl (Dev-DB nicht nutzbar ohne Prod-MEK).

#### Vorgehen

Prod-Keystore nach Dev kopiert, dann `RESTORE DATABASE`, `RECOVER DATABASE`,
`ALTER DATABASE OPEN RESETLOGS`.

```bash
scripts/tde-verify/tde_clone.sh --variant a --dbid 1515066983 --delete --yes
scripts/tde-verify/tde_evidence.sh \
  -s odbencdev -p ODBENCPROD -l variant_a -m 'OEHRLI-CANARY-01'
scripts/tde-verify/tde_evidence.sh --compare baseline variant_a
```

#### Ergebnis

Der Restore selbst brauchte **keinen** offenen Keystore. Ein normaler RESTORE kopiert Chiffrat
und benoetigt keinen Schluessel; der Schluessel wird erst zum Lesen gebraucht. Laufzeit des
ersten Backup-Sets: 3 Sekunden.

Schluesselkette im Klon, identisch zur Quelle:

- `MASTERKEYID` 8A27589796A248BE95222E59407FF962 - identisch
- `KEY_VERSION` 1 - identisch
- gewrappter TEK BAD537ADDD695BEE7A29F6F27B65A03D6F195CCE3388AD0119D718087A8AFA55 -
  byteidentisch, und physisch an derselben Stelle: Offset 8977, Block 1 Byte 785

Blockvergleich des `USERS`-Datafiles, 2561 Bloecke verglichen:

| Kategorie | identisch | geaendert |
|---|---|---|
| Header-Bloecke 0 bis 1 | 0 | 2 |
| Canary-Datenbloecke (313, aus `DBMS_ROWID`) | 313 | 0 |
| Bloecke im Canary-Bereich ohne Daten | 52 | 64 |
| Bloecke vor dem Canary-Bereich (2 bis 979) | 904 | 73 |
| Bloecke nach dem Canary-Bereich (1408 bis 2560) | 0 | 1153 |
| Gesamt | 1269 | 1292 |

Auswertung: alle 313 Bloecke mit echten Nutzdaten sind byteidentisch. Die abweichenden Bloecke
sind leere bzw. nie benutzte Bloecke - RMAN Backup Optimization sichert leere Bloecke nicht,
sondern schreibt sie beim Restore neu. Belegt am Rohbyte-Vergleich von Block 2000: die Quelle
traegt dort Zufallsbytes, der Klon nur Nullen nach dem Blockheader. Die Header-Bloecke
unterscheiden sich nur in Checkpoint-Metadaten - die TEK-Region im Header ist byteidentisch.

Nebenbefunde mit Kundenrelevanz:

- **LOCAL Auto-Login:** ein LOCAL Auto-Login-Keystore oeffnet auf einem anderen Host nicht.
  Nach dem Wallet-Transfer stand `v$encryption_wallet` auf CLOSED mit `WALLET_TYPE` UNKNOWN,
  Lesen scheiterte mit ORA-28365. Ursache: der Keystore wird als LOCAL AUTO_LOGIN erzeugt und
  ist damit an den Host gebunden - hier Hostname `odbencprod` gegen `odbencdev`. Erst
  `ADMINISTER KEY MANAGEMENT SET KEYSTORE OPEN FORCE KEYSTORE IDENTIFIED BY <pwd>
  CONTAINER=ALL` oeffnete ihn, danach `WALLET_TYPE` PASSWORD. Betrifft auch den SEPS-Store
  `tde_seps`, der ebenfalls als LOCAL AUTO_LOGIN angelegt wird.
- **`ORIGIN`:** der transportierte Prod-Schluessel zeigt im Ziel `ORIGIN` LOCAL, nicht
  IMPORTED. Wer das Keystore-File kopiert, hinterlaesst keine Spur der Herkunft. `ORIGIN` taugt
  nicht als Nachweis lokaler Schluesselerzeugung.
- **Recovery:** "datafile 20 not processed because file is read-only", ebenso fuer Datafile 21.
  Die `READ ONLY`-Entscheidung hat die Canary-Datafiles vollstaendig aus der Recovery
  herausgehalten, also kein Recovery-Rauschen im Blockvergleich.

Betriebliche Stolpersteine, die auftraten und geloest wurden:

- ORA-19698 "is from different database", weil die Online-Redo-Logs des Ziels auf denselben
  Pfaden liegen wie in der Quell-Controlfile. Loesung: Redo-Logs verschieben,
  `OPEN RESETLOGS` legt sie neu an.
- RMAN-06054 fuer die Sequenz, die beim Backup noch aktives Online-Log war. Loesung:
  `SET UNTIL SEQUENCE <letzte plus 1> THREAD 1` vor `RECOVER`.

Entzugstest: Dev-eigenes Wallet zurueckgespielt, Instanz neu gestartet. Nur der Dev-MEK
`AWZuopGe2EGHqnGxulapWxw...` ist sichtbar. Lesen des Canary scheitert mit ORA-28374
"typed master key not found in wallet". Der dokumentierte Ausweg aus diesem Zustand ist
`ADMINISTER KEY MANAGEMENT MERGE KEYSTORE '<backup>' ... INTO EXISTING KEYSTORE '<current>'
... WITH BACKUP` oder `IMPORT KEYS` aus einem Export - also das Zurueckholen des Prod-Schluessels.
Genau das ist im Klon-Szenario nicht gewuenscht.

**Bewertung:** kein Re-encrypt, kein neuer TEK, kryptografisch vollstaendig von Prod abhaengig.
Fuer die Anforderung "keine Rueckschluesse auf Prod" untauglich.

### Variante B2 - RESTORE AS ENCRYPTED USING KEY ohne Prod-MEK

Dieser Lauf prueft, ob RMAN den Prod-MEK im Dev-Keystore voraussetzt.

#### Vorgehen

```bash
scripts/tde-verify/tde_clone.sh --variant b2 --dbid 1515066983 --key '<dev_mek>' --yes
```

#### Ergebnis

`RESTORE DATABASE AS ENCRYPTED USING KEY '<dev_mek>'` scheitert mit ORA-19870 "error while
restoring backup piece" plus ORA-28374 "typed master key not found in wallet".

Aussage: RMAN braucht den Quell-MEK, um die verschluesselten Quellbloecke ueberhaupt zu lesen.
Ein RMAN-Klon ohne Transfer des Prod-Schluessels existiert nicht.

### Variante B1 - RESTORE AS ENCRYPTED USING KEY mit Prod-MEK und eigenem Ziel-MEK

**Hypothese unbekannt** - das ist der Streitfall. Ob Bloecke re-encrypted oder nur re-wrapped
werden, ist in der Oracle-Doku fuer verschluesselte Quellen nicht belegt.

#### Vorgehen

Der Ziel-Keystore enthielt beide Prod-Schluessel plus einen neu erzeugten Ziel-Schluessel:

```sql
ADMINISTER KEY MANAGEMENT CREATE KEY USING TAG 'devtarget-2026-09-03'
  FORCE KEYSTORE IDENTIFIED BY <pwd> WITH BACKUP;
```

Der neue Schluessel `AV75yf3iEUAWtYUhndGAVAg...` hatte zunaechst con_id 0, war also angelegt
aber nicht aktiviert.

```bash
scripts/tde-verify/tde_clone.sh --variant b1 --dbid 1515066983 \
  --key 'AV75yf3iEUAWtYUhndGAVAg...' --yes
```

#### Ergebnis

Der Keystore musste nach dem Instanzneustart explizit mit Passwort geoeffnet werden, sonst
ORA-28365. Anders als bei Variante A ist das hier zwingend.

Das erste Backup-Set mit den unverschluesselten CDB-Datafiles wurde erfolgreich restauriert,
Laufzeit 5:45 in einem Einzellauf gegenueber 3 Sekunden bei einem normalen Restore. Auf unverschluesselten
Quelldateien leistet `AS ENCRYPTED` also echte Blockarbeit. Der dokumentierte Anwendungsfall
funktioniert und ist am Timing messbar.

Sobald RMAN das bereits verschluesselte Datafile 20 erreicht:

```text
ORA-00600: internal error code, arguments: [kcbtse_encdec_tbsblk_1], [4], [2],
[806], [18], [806], [20], [4294967295], [0], [0], [], []
```

Dreimal reproduziert, mit und ohne `FORCE`, identische Argumente. Der Keystore war jeweils
offen mit `WALLET_TYPE` PASSWORD.

**Bewertung:** der dokumentierte Fall unverschluesselt nach verschluesselt funktioniert. Der
undokumentierte Fall verschluesselt nach verschluesselt bricht mit einem internen Fehler ab.
Fuer den Kunden heisst das: dieser Weg ist fuer eine bereits verschluesselte
Produktionsdatenbank nicht nutzbar.

### Variante C - DUPLICATE AS ENCRYPTED

Nicht gemessen. Der Doku-Wortlaut von `DUPLICATE AS ENCRYPTED` adressiert Quellen, die nicht
verschluesselt sind; das Verhalten bei verschluesselter Quelle bleibt damit offen. Variante `c`
ist in `tde_clone.sh` angelegt, aber nicht implementiert.

### Variante D - Entschluesselungspfad ueber RESTORE FORCE AS DECRYPTED

#### Vorgehen und Ergebnis

`RESTORE ... FORCE AS DECRYPTED` funktioniert bei verschluesselter Quelle.

`FORCE` ist zwingend. Ohne `FORCE` ueberspringt die Restore-Optimierung genau die Datafiles,
die schon auf Stand sind. Im Lab sah ein Lauf ohne `FORCE` erfolgreich aus, hat aber die
Datafiles 20 und 21 gar nicht angefasst - das Ergebnis war wertlos.

Danach:

- `DBA_TABLESPACES.ENCRYPTED` gleich NO fuer alle Tablespaces
- `V$ENCRYPTED_TABLESPACES` leer
- Canary mit 5000 Zeilen lesbar
- der Klartext-Marker ist mit 313 Treffern im Datafile auffindbar, ab Block 979

Die Bloecke sind also echt entschluesselt.

Die Datenbank oeffnet trotzdem nicht, wenn der Quell-MEK fehlt. Alert Log:

```text
KZTDE:kztsmptc: Missing Key ID: AbyhIcXQQk+XiBYrKzrI3FY...
Active database master key not found in the wallet!: ena 4 flag 0x4e mkloc 0x9
mkid bca121c5d0424f9788162b2b3ac8dc56
ORA-28374 signalled during ALTER DATABASE OPEN
```

Tablespaces zu entschluesseln bricht die Abhaengigkeit also nicht.

`ADMINISTER KEY MANAGEMENT SET KEY ... CONTAINER=ALL` dreht den CDB-Database-Key von
BCA121C5D0424F9788162B2B3AC8DC56 auf 6E93045783B04AAAADA609B4C8CDBFB3, scheitert aber mit
ORA-46663 "master encryption keys not created for all PDBs for REKEY", weil `PDB$SEED` keinen
Schluessel hat. Ein separates `SET KEY` in der PDB dreht deren Key auf
8252C3B0871744CBA42F15CA00FFBCA7.

Danach `ALTER TABLESPACE USERS ENCRYPTION OFFLINE ENCRYPT`:

<!-- markdownlint-disable MD013 MD060 -->
| Messwert | Wert nach dem Zyklus |
|---|---|
| `DBA_TABLESPACES.ENCRYPTED` fuer `USERS` | YES |
| `KEY_VERSION` | 3 |
| gewrappter TEK | 8FBDA2A856F5128B5C2D27F51A9B769608D1CA60185320DD67861E148C303E41 |
| `MASTERKEYID` | 8252C3B0871744CBA42F15CA00FFBCA7 |
| Canary | 5000 Zeilen lesbar |
<!-- markdownlint-restore -->

Blockvergleich gegen die Prod-Baseline: 1406 identisch, 1155 geaendert. Die abweichenden
Bloecke sind 0, 1 und 1408 bis 2560. Die Bloecke 2 bis 1407 einschliesslich aller
Canary-Datenbloecke sind byteidentisch zur Quelle.

Prods gewrappter TEK und Prods `MASTERKEYID` sind physisch nicht mehr im Datafile auffindbar.
Der neue Dev-TEK liegt an derselben Header-Stelle, Offset 8977.

Kontrolliert wiederholt: offline `DECRYPT`, dabei den Klartext-Marker mit 313 Treffern
nachgewiesen, dann offline `ENCRYPT`. Ergebnis erneut 1406 identisch und 1155 geaendert,
`KEY_VERSION` 5, gewrappter TEK unveraendert 8FBDA2A8...3E41.

**Schlussfolgerung:** identisches Chiffrat bei identischem Inhalt und identischer Blockadresse
bedeutet identischer TEK. Der Tablespace-Encryption-Key uebersteht den
Entschluesseln-Verschluesseln-Zyklus, nur seine Verpackung wechselt.

Einordnung der Quellenlage: ob `OFFLINE DECRYPT` gefolgt von `OFFLINE ENCRYPT` denselben TEK
wiederverwendet, ist in oeffentlichen Quellen nicht belegt - weder bestaetigt noch widerlegt.
Dieser Laborbefund steht damit ohne Gegenprobe aus der Literatur da. Die Doku fuehrt
OFFLINE-Operationen ohnehin nicht als Rekeying-Verfahren; dafuer ist ausschliesslich
`ONLINE REKEY` dokumentiert.

### Positivkontrolle der Messmethode

Frage: erkennt der Blockvergleich einen TEK-Wechsel ueberhaupt?

Zwei frische verschluesselte Bigfile-Tablespaces `CTRL_ENC_A` und `CTRL_ENC_B` in Prod,
identische DDL, identischer Canary-Inhalt ueber `csenc_canary.sql`. Beide belegen die Bloecke
779 bis 1279 mit je 313 belegten Bloecken.

- gewrappter TEK `CTRL_ENC_A`: 6B6A512AC8BFAEF411C5F6C1BAEB8845E618E0B6F9C66F7DD1A3361982D83B07
- gewrappter TEK `CTRL_ENC_B`: F29E623B3D421496F54A8BE21F80E35DF2CC3739DBEBEC04D4390E7C0B491C79
- beide unter derselben `MASTERKEYID` 8A27589796A248BE95222E59407FF962

Von den 501 Bloecken im Bereich 779 bis 1279 unterscheiden sich 367, identisch sind 134.

Damit ist die Methode nachweislich sensitiv fuer einen TEK-Wechsel. Der Nullbefund bei
Variante A und beim Entschluesselungspfad ist keine Blindheit des Messverfahrens.

## Messmatrix

<!-- markdownlint-disable MD013 MD060 -->
| Variante | Ciphertext-Diff (geaendert / verglichen) | Canary-Datenbloecke identisch | Gewrappter TEK im Header geaendert | `MASTERKEYID` | `KEY_VERSION` | `ORIGIN` | Prod-MEK beim Klon noetig | Entzugstest | Bewertung |
|---|---|---|---|---|---|---|---|---|---|
| A - normaler RESTORE | 1292 / 2561 | 313 von 313 | nein | 8A2758...F962, wie Prod | 1, wie Prod | LOCAL (auch fuer den transportierten Prod-Schluessel) | ja | schlaegt fehl: ORA-28374 | Re-wrap-frei, kein neuer TEK, vollstaendig von Prod abhaengig |
| B1 - AS ENCRYPTED mit Prod-MEK | nicht messbar | nicht messbar | nicht messbar | nicht messbar | nicht messbar | nicht messbar | ja | nicht erreicht | Abbruch mit ORA-00600 `[kcbtse_encdec_tbsblk_1]` |
| B2 - AS ENCRYPTED ohne Prod-MEK | nicht messbar | nicht messbar | nicht messbar | nicht messbar | nicht messbar | nicht messbar | ja | nicht erreicht | Abbruch mit ORA-19870 plus ORA-28374 |
| C - DUPLICATE AS ENCRYPTED | nicht gemessen | nicht gemessen | nicht gemessen | nicht gemessen | nicht gemessen | nicht gemessen | nicht gemessen | nicht gemessen | offen |
| D - AS DECRYPTED plus SET KEY plus offline ENCRYPT | 1155 / 2561 | 313 von 313 | ja - 8FBDA2A8...3E41 statt BAD537AD...FA55 | 8252C3B0...BCA7, dev-eigen | 3, im Wiederholungslauf 5 | nicht gemessen | ja, fuer den AS DECRYPTED-Lauf | nicht gemessen | neue Schluesselverpackung, identisches Datenchiffrat |
| Positivkontrolle - neuer Tablespace | 367 / 501 im Canary-Bereich | 134 von 501 Bloecken im Bereich | ja - unterschiedliche TEKs unter demselben MEK | 8A2758...F962 fuer beide | nicht gemessen | nicht gemessen | entfaellt | entfaellt | echtes neues TEK-Material |
<!-- markdownlint-restore -->

## Bewertung und Empfehlung fuer den Kunden

- **Jeder RMAN-basierte Weg erhaelt den Tablespace-Encryption-Key.** Auch der Umweg ueber
  `AS DECRYPTED` und anschliessendes Neuverschluesseln erzeugt kein neues Schluesselmaterial:
  die Canary-Datenbloecke sind nach dem vollstaendigen Zyklus wieder byteidentisch zur Quelle,
  und der gewrappte TEK bleibt ueber einen zweiten Zyklus hinweg unveraendert.
- **Der MEK laesst sich im Ziel auf einen eigenen drehen.** Damit ist die
  Keystore-Abhaengigkeit loesbar - `MASTERKEYID` und gewrappter TEK im Header sind danach
  dev-eigen, die Prod-Werte physisch nicht mehr im Datafile. Das Chiffrat der Daten bleibt aber
  identisch zur Quelle. Wer die Datenabhaengigkeit als Risiko fuehrt, hat sie damit nicht
  behoben.
- **Neues TEK-Material entsteht nachweislich beim Anlegen eines neuen verschluesselten
  Tablespace.** Das ist der einzige im Lab belegte Weg zu echtem neuem Schluesselmaterial.
  `ONLINE REKEY` verspricht laut Doku "independent encryption keys", ist in Oracle Database
  Free aber nicht unterstuetzt und wurde daher nicht gemessen.
- **Ein kopierter Keystore behaelt alle historischen Quell-Schluessel.** Das ist kein
  Nebeneffekt, sondern Voraussetzung: laut Doku muessen alle historischen Master Keys im
  transportierten Wallet enthalten sein, weil sie zum Wiederherstellen aelterer Backups
  gebraucht werden. Wer im Ziel wirklich nur eigene Schluessel haben will, braucht einen
  frischen Keystore mit selektivem Import. `ORIGIN` hilft dabei nicht als Kontrolle: der
  transportierte Prod-Schluessel zeigt im Ziel LOCAL.
- **Ein REKEY nach dem Klon ist der dokumentierte Schritt**, damit Prod- und Non-Prod-MEK
  auseinanderlaufen. Er loest die MEK-Abhaengigkeit, nicht die Datenabhaengigkeit - das belegt
  Variante D.
- **Der Prod-Schluessel muss fuer jeden RMAN-Klon einer verschluesselten Quelle
  voruebergehend ins Ziel.** Variante B2 belegt das durch den Abbruch. Die relevante Frage ist
  damit nicht, ob der Prod-Schluessel ins Ziel gelangt, sondern ob er danach wieder entfernt
  werden kann - und was dann noch lesbar ist.

## Offene Punkte und Risiken

### Aus der Testplanung

- Recovery kann Blockinhalte anfassen und den Ciphertext-Diff verrauschen. Gegenmittel:
  Tablespace `READ ONLY`, konsistentes Backup, Vergleich auf den Canary-Datenblock begrenzt.
  Im Lab wirksam - Recovery meldete "datafile 20 not processed because file is read-only".
- Falls `RESTORE AS ENCRYPTED` bei verschluesselter Quelle einen Fehler wirft, ist auch das ein
  verwertbares Ergebnis fuer den Kunden - kein Testabbruch. Eingetreten bei B1 und B2.
- `DUPLICATE` mit identischem `DB_NAME` `FREE` in beiden Containern: getrennte Hosts, sollte
  tragen. Falls nicht, Fallback auf Backup-basiertes DUPLICATE. Nicht gemessen.
- Das 12-GB-Limit von Oracle Free ist bei wenigen MB Testdaten nicht relevant.
- `DUPLICATE AS ENCRYPTED` ist in der Doku fuer den Fall unverschluesselt zu verschluesselt
  beschrieben. Verhalten bei verschluesselter Quelle koennte undokumentiert oder ungetestet
  sein.
- Ob `RESTORE AS ENCRYPTED` bei verschluesselter Quelle den Prod-MEK im Ziel-Keystore
  voraussetzt (Variante B2), ist in der oeffentlichen Doku nicht adressiert. Gemessen: ja, er
  ist Voraussetzung.

### Neu hinzugekommen

- **Variante C nicht gemessen.** `DUPLICATE ... AS ENCRYPTED` bleibt offen; Variante `c` in
  `tde_clone.sh` ist nicht implementiert.
- **`_db_discard_lost_masterkey` neu zu messen.** Siehe naechster Abschnitt.
- **`ONLINE REKEY` in Free nicht pruefbar.** Der einzige laut Doku Schluessel-unabhaengige Weg
  ist in Oracle Database Free lizenzseitig nicht verfuegbar. Eine Messung braucht eine Enterprise
  Edition.
- **UNITED gegen ISOLATED Keystore-Modus als Folgefrage.** Alle Messungen liefen im
  UNITED Mode. Ob der ISOLATED Mode am Ergebnis etwas aendert - insbesondere bei Transport und
  selektivem Import - ist nicht gemessen. Der dokumentierte Moduswechsel geht ueber
  `ISOLATE KEYSTORE` bzw. `UNITE KEYSTORE`, nicht ueber einen Wert von `TDE_CONFIGURATION`.
- **`TDE_CONFIGURATION` auf PDB-Ebene.** Die Praxisbeobachtung, dass ein in der PDB gesetztes
  `TDE_CONFIGURATION` ein eigenes Keystore-File erzeugt, deckt sich nicht mit der
  Oracle-Dokumentation. Der Punkt wird im Lab gemessen.

### Offener Pruefpunkt - `_db_discard_lost_masterkey`

Hidden Parameter. `ssenc_info.sql` fragt ihn bereits in der Hidden-Parameter-Liste ab.
Fachlich nur zulaessig, wenn nachweislich kein verschluesseltes Objekt mehr existiert, also
nach vollstaendigem `AS DECRYPTED`.

Quellenlage: keine MOS Note ist frei einsehbar. In einer Sekundaerquelle werden die IDs
1301365.1, 1228046.1 und 1241925.1 genannt, ohne Inhalt. Ob Oracle Support eine Freigabe
verlangt, ist in keiner oeffentlichen Quelle belegt - das ist hier als Vorgabe aus der Praxis
gefuehrt, nicht als Oracle-Aussage.

Zweck laut Sekundaerquelle (Blog, siehe [Quellen](#quellen)): der Parameter erlaubt ein
`ADMINISTER KEY MANAGEMENT SET KEY`, obwohl der bisher referenzierte Schluessel fehlt. Er ist
dort **nicht** als Mittel beschrieben, eine Datenbank zu oeffnen. Verwendete Form:

```sql
ALTER SYSTEM SET "_db_discard_lost_masterkey"=true SCOPE=MEMORY;
```

Der Blog dokumentiert dazu diese Alert-Log-Warnung:

> Warning: replacing lost SYSAUX key with new database key due to prior wallet deletion.
> Encrypted blocks in SYSAUX tablespace would appear corrupted, since the original key is
> replaced.

Wiederholter Einsatz fuehrt laut Blog zu echten Korruptionen; genannt werden ORA-01595 und
ORA-28304. Oracle empfiehlt laut derselben Quelle ausdruecklich, Keystores niemals zu loeschen.

Ein Versuch im Lab setzte den Parameter auf TRUE, verifiziert zur Laufzeit ueber `x$ksppi` und
`x$ksppsv`, und `ALTER DATABASE OPEN` scheiterte weiter mit ORA-28374.

Dieser Versuch war methodisch falsch angesetzt: es wurde nur `ALTER DATABASE OPEN` versucht und
kein `SET KEY` - genau das ist aber der beschriebene Zweck des Parameters. Zusaetzlich lief er
auf einem Zustand, der vorher mehrfach umgebaut worden war: Restore, Wallet-Tausch,
`SET KEY CONTAINER=ALL` mit ORA-46663, separates `SET KEY` in der PDB, offline Encrypt, offline
Decrypt. **Als Negativbefund ist er deshalb nicht belastbar und wird als solcher nicht
gewertet.** Der Parameter ist in einer klaren Kette auf gruener Wiese neu zu messen, dann mit
`SET KEY`. Es ist bekannt, dass der Parameter in CDBs erfolgreich eingesetzt wurde.

## Quellen

- Oracle Backup and Recovery Reference 19c, RESTORE:
  <https://docs.oracle.com/en/database/oracle/oracle-database/19/rcmrf/RESTORE.html>
- Oracle Backup and Recovery Reference 26ai, RESTORE:
  <https://docs.oracle.com/en/database/oracle/oracle-database/26/rcmrf/RESTORE.html>
- Oracle Backup and Recovery Reference 19c, DUPLICATE:
  <https://docs.oracle.com/en/database/oracle/oracle-database/19/rcmrf/DUPLICATE.html>
- Oracle Database Free 26ai, Licensing Restrictions:
  <https://docs.oracle.com/en/database/oracle/oracle-database/26/xeinl/licensing-restrictions.html>
- Oracle Database Advanced Security, Encryption Conversions:
  <https://docs.oracle.com/en/database/oracle/oracle-database/26/dbtde/encryption-conversions-tablespaces-and-databases1.html>
- Oracle Database Reference 19c, V$ENCRYPTED_TABLESPACES:
  <https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/V-ENCRYPTED_TABLESPACES.html>
- Oracle Database Advanced Security Guide 26ai, Administering United Mode:
  <https://docs.oracle.com/en/database/oracle/oracle-database/26/dbtde/administering-united-mode1.html>
- Oracle Database Reference 26ai, TDE_CONFIGURATION:
  <https://docs.oracle.com/en/database/oracle/oracle-database/26/refrn/TDE_CONFIGURATION.html>
- Oracle Database Advanced Security Guide 19c, Managing Keystores and Encryption Keys in United
  Mode:
  <https://docs.oracle.com/en/database/oracle/oracle-database/19/asoag/managing-keystores-encryption-keys-in-united-mode.html>
- Oracle Database Advanced Security Guide 26ai, ORA-28374 typed master key not found:
  <https://docs.oracle.com/en/database/oracle/oracle-database/26/dbtde/error-ora-28374-typed-master-key-not-found.html>
- Oracle Database Advanced Security Guide 19c, Configuring Transparent Data Encryption:
  <https://docs.oracle.com/en/database/oracle/oracle-database/19/asoag/configuring-transparent-data-encryption.html>

**Sekundaerquelle** - kein Oracle-Dokument, als Blog gekennzeichnet und nur dort zitiert, wo es
im Text ausdruecklich vermerkt ist:

- Asanga Pradeep, 19c Encryption (Blog):
  <https://asanga-pradeep.blogspot.com/2019/10/19c-encryption.html>

MOS Notes: keine der genannten Notes ist frei einsehbar. Die IDs 1301365.1, 1228046.1 und
1241925.1 stammen aus einer Sekundaerquelle und wurden inhaltlich nicht geprueft.

## Algorithmuswechsel als Beweis fuer neues Schluesselmaterial

Ein Wechsel der Schluessellaenge ist der einzige Nachweis, der ohne Chiffratvergleich
auskommt: ein 192-Bit-Schluessel kann kein umgewickelter 256-Bit-Schluessel sein.

Zuerst eine Korrektur. Ein frueherer Versuch, den Algorithmus mit
`ALTER TABLESPACE ... ENCRYPTION OFFLINE USING 'AES192' ENCRYPT` zu wechseln, scheiterte
mit ORA-28340. Ursache war das falsche Kommando, nicht eine Sperre. Oracle dokumentiert
fuer den SYSTEM-Tablespace, dass die ENCRYPT-Klausel keinen Algorithmus annimmt, weil
beim ersten Mal mit dem bestehenden Database Key verschluesselt wird, und dass fuer den
Algorithmus die REKEY-Klausel zu verwenden ist.

Gemessen an einem eigenen Tablespace in der Quelldatenbank, 5000 Canary-Zeilen:

<!-- markdownlint-disable MD013 MD060 -->

| Groesse | vor dem Rekey | nach `ENCRYPTION ONLINE USING 'AES192' REKEY` |
|---|---|---|
| Algorithmus und Cipher Mode | AES256 XTS | AES192 CFB |
| KEY_VERSION | 0 | 2 |
| gewrappter TEK | 3792A5BB...84A0 | D1D460D8...2DD3 plus Nullbytes |
| signifikante Schluesselbytes | 32, also 256 Bit | 24, also 192 Bit |
| Datafile | unveraendert | neu geschrieben |
| Blockvergleich | - | 2560 von 2561 Bloecken geaendert, nur Block 0 gleich |
| alter TEK im neuen Datafile | - | 0 Treffer |
| Canary | 5000 Zeilen | 5000 Zeilen |

<!-- markdownlint-restore -->

Geltungsbereich des Algorithmus, ebenfalls gemessen: der tablespace-lokale
`USING 'AES192' REKEY` wird akzeptiert, obwohl der Instanz-Default-Cipher-Mode auf XTS
steht, und stellt diesen Tablespace auf CFB. Der Instanzparameter
`tablespace_encryption_default_algorithm` dagegen wird bei aktivem XTS mit ORA-38134
abgelehnt. Belegt in der SQL Language Reference 26ai: XTS ist nur mit AES128 und AES256
erlaubt, fuer AES192 ist CFB zu verwenden. XTS existiert erst ab 23ai, 19c kennt nur CFB.

Konsequenz fuer die Empfehlung: wer AES192 waehlt, verlaesst XTS. Als Mittel zur
Trennung von der Produktion ist der Algorithmuswechsel damit kein Selbstzweck - ein
`ONLINE REKEY` unter AES256 erneuert das Schluesselmaterial genauso und behaelt den
modernen Cipher Mode.
