# Oracle Free Labs - Repo Overhaul Plan

## Overview

Vollständige Überarbeitung des `oracle-free-labs` Repos auf OraDBA-Standards.
Sechs unabhängige Aufgabenbereiche, sequenziell umzusetzen.

---

## Phase 1: Cleanup & Fixes (P1 - Sofortmassnahmen) ✅

- [x] 1.1 Stray file `"docker-compose copy.yml"` löschen
- [x] 1.2 `bin/data/` stray directory entfernen (leer, falsch platziert)
- [x] 1.3 `bin/` umbenennen zu `scripts/` (analog `ora-db-audit-eng`)
- [x] 1.4 Alle Referenzen auf `bin/` aktualisieren (README.md, CLAUDE.md, Makefile-Target)

## Phase 2: ORACLE_SID-Konflikt beheben (P1 - kritisch) ✅

- [x] 2.1 In `.env.example`: `ORACLE_SID` umbenennen zu `DB_ORACLE_SID`
- [x] 2.2 In `.env` (lokal): gleiche Umbenennung
- [x] 2.3 In `docker-compose.yml` x-db-service base: `ORACLE_SID=${ORACLE_SID}` → `ORACLE_SID=${DB_ORACLE_SID}`
- [x] 2.4 Kommentar im `.env.example` erklären warum DB_ORACLE_SID (oraenv-Konflikt)

## Phase 3: Fehlende Standarddateien (P2) ✅

- [x] 3.1 `VERSION` Datei anlegen mit `1.0.0`
- [x] 3.2 `CHANGELOG.md` anlegen mit sinnvoller History bis v1.0.0
- [x] 3.3 `CONTRIBUTING.md` anlegen (analog ora-db-audit-eng)

## Phase 4: Shell Scripts auf Standard bringen (P2) ✅

- [x] 4.1 `scripts/generate_pdf.sh` - `set -euo pipefail` ergänzen, Header korrigieren
- [x] 4.2 `scripts/template.sh` - `set -euo pipefail` ergänzen, Header korrigieren
- [x] 4.3 `scripts/install_oradba_init.sh` - Pfad geprüft nach Umbenennung

## Phase 5: Makefile erstellen (P1) ✅

- [x] 5.1 `Makefile` im Projektroot erstellen
- [x] 5.2 Generische Targets: `up/down/ps/logs/bash/sql/reset SERVICE=<name>`
- [x] 5.3 Explizite Targets: `up-<service>`, `down-<service>`, `logs-<service>`, `bash-<service>`,
      `sql-<service>`, `reset-<service>` fuer alle 6 Services
- [x] 5.4 Build-Targets: `build`, `build-push`
- [x] 5.5 PDF/Doku-Target: `doc DOCNAME=<name>`
- [x] 5.6 Lint-Targets: `lint`, `lint-shell`, `lint-yaml`, `lint-markdown`, `fmt-shell`, `fmt-shell-write`
- [x] 5.7 Versions-Targets: `version`, `check-version`, `version-bump-{patch,minor,major}`, `tag`, `release`
- [x] 5.8 `DB_ORACLE_SID` via `-include .env` im Makefile verfügbar

## Phase 6: Dockerfile & Build-Kontext (P1) ✅

- [x] 6.1 `build/` Verzeichnis anlegen
- [x] 6.2 `build/Dockerfile` erstellen (ARG DB_IMAGE, microdnf install rlwrap less tar gzip)
- [x] 6.3 `build/.dockerignore` anlegen
- [x] 6.4 GitHub Workflow angepasst: `file: build/Dockerfile`, `context: build`

## Phase 7: .gitignore & Docker-Standards (P2) ✅

- [x] 7.1 `.dockerignore` im Projektroot anlegen
- [x] 7.2 `.gitignore` - kein `bin/data/` Eintrag mehr nötig (bereinigt)
- [x] 7.3 `docker-compose.yml` - `:latest` vorerst beibehalten (lab-Kontext)

## Phase 8: Dokumentation aktualisieren (P3) ✅

- [x] 8.1 `README.md` - `ORACLE_SID` → `DB_ORACLE_SID` Verweis aktualisiert
- [x] 8.2 `README.md` - Makefile-Usage ergänzt (make help, make up-labdb etc.)
- [x] 8.3 `README.md` - `odbenc` war bereits in Services-Tabelle vorhanden
- [x] 8.4 `CLAUDE.md` - `bin/` → `scripts/` Referenz bereits aktualisiert
- [x] 8.5 GitHub Workflow docker-publish.yml: OraDBA-Header + korrekte Pfade

---

## Entscheidungen (dokumentiert)

| # | Entscheidung | Begründung |
|---|-------------|------------|
| 1 | `ORACLE_SID` → `DB_ORACLE_SID` | oraenv/oradba setzt `ORACLE_SID` in Shell; Docker Compose liest Shell-Env mit höherer Priorität als `.env` |
| 2 | Dockerfile in `build/` | Alle Services nutzen dasselbe Image; analog ora-db-audit-eng Struktur |
| 3 | `bin/` → `scripts/` | Konsistenz mit ora-db-audit-eng; lokale Hilfsscripte != system bin |
| 4 | Explizite Make-Targets pro Service | Autocomplete-freundlich; zusätzlich generischer `make up SERVICE=x` |
| 5 | VERSION = 1.0.0 | Repo ist production-ready seit mehreren Monaten |
| 6 | `grep -h` in help-Target | `-include .env` fügt .env zu MAKEFILE_LIST hinzu; ohne -h zeigt grep Dateinamen als Prefix |

---

## Status: VOLLSTÄNDIG ABGESCHLOSSEN ✅

## TDE RESTORE AS ENCRYPTED - Verifikationstest (Plan 2026-09-03)

Anlass: Frage aus ALTIMA-Meeting 2026-09-03. Macht `RESTORE DATABASE AS ENCRYPTED
USING KEY <mek>` ein echtes Re-encrypt der Bloecke (neues TEK-Material) oder nur ein
Re-wrap des bestehenden TEK im Datafile-Header? Ziel ist ein nachvollziehbares
Testprotokoll plus Varianten-Praesentation fuer den Kunden.

### Doku-Befund (Basis, recherchiert 2026-09-03)

- `RESTORE DATABASE|TABLESPACE AS ENCRYPTED [USING KEY 'key_id']` ist dokumentiert,
  COMPATIBLE >= 12.2. Ohne `USING KEY` nimmt RMAN den aktiven MEK des Ziel-Keystores.
  Quelle: Backup and Recovery Reference 19c/26ai, RESTORE.
- `DUPLICATE TARGET DATABASE TO <db> AS ENCRYPTED` ist dokumentiert, COMPATIBLE >= 18.0.
  Voraussetzung laut Doku: Source-Keystore auf das Auxiliary-System kopiert und geoeffnet.
- Beide Klauseln sind in der Doku fuer den Fall **unverschluesselt -> verschluesselt**
  beschrieben. Fuer verschluesselt -> verschluesselt ist die TEK-Semantik **nicht belegt**.
  Genau diese Luecke schliesst der Test.
- Kein V$-View zeigt TEK-Material oder eine TEK-ID. `ENCRYPTEDKEY` und `KEY_VERSION`
  aendern sich bei neuem TEK **und** bei reinem Re-wrap. SQL allein beweist nichts.
- `ALTER TABLESPACE ... ENCRYPTION ONLINE REKEY` ist in Oracle Free **nicht unterstuetzt**
  (Licensing Restrictions 26ai). Referenzvariante daher ueber neuen Tablespace.
- Oracle Free Limits: 2 CPU, 2 GB RAM, 12 GB User Data. Fuer wenige MB Testdaten irrelevant.

### Beweisstrategie

Nicht Laufzeit, sondern Ciphertext. Pro Variante vier Nachweise:

1. **Ciphertext-Diff**: derselbe Datenblock in Quell- und Ziel-Datafile per `dd` +
   `sha256sum`. Identische Bytes => selber TEK, nur Re-wrap. Andere Bytes => Bloecke
   neu verschluesselt. Tablespace vor dem Backup READ ONLY, damit die Bloecke stabil sind.
2. **Canary-Test**: bekannter Klartext-String in den Daten. `strings`/`grep` gegen das
   Datafile muss negativ sein (belegt, dass ueberhaupt verschluesselt ist) und dient als
   Anker, um den richtigen Block zu finden.
3. **MEK-Kette**: `V$ENCRYPTED_TABLESPACES.MASTERKEYID` / `KEY_VERSION` /
   `ENCRYPTEDKEY` / `CIPHERMODE` vor und nach dem Klon.
4. **Entzugstest**: Prod-MEK aus dem Dev-Keystore entfernen, Dev-DB neu starten,
   Canary-Zeile lesen. Erst das belegt kryptografische Unabhaengigkeit von Prod.

### Phase 0 - Lab-Infrastruktur

Entscheid 2026-09-03: `odbenc` bleibt unangetastet. Der Test bekommt zwei eigene
Services. Keine OEM-Express-Port-Mappings (nicht gebraucht), damit die bestehende
5511-Kollision zwischen `odbdemo` und `odbenc` hier keine Rolle spielt.

- [ ] Service `odbencprod` in `docker-compose.yml`: Profile `odbencprod`, Port 1532,
      Mounts analog `odbenc`, eigener `data/odbencprod/`, TDE via SQL-Scripts
- [ ] Service `odbencdev` in `docker-compose.yml`: Profile `odbencdev`, Port 1533,
      eigener `data/odbencdev/`
- [ ] `.env.example` + `.env`: `ODBENCPROD_LISTENER_PORT=1532`,
      `ODBENCDEV_LISTENER_PORT=1533`, `ODBENCPROD_DB_MEM=3g`, `ODBENCDEV_DB_MEM=3g`
      (Compose-Fallback `${ODBENCPROD_DB_MEM:-${DB_MEM}}`, damit andere Services
      unveraendert bleiben)
- [ ] Austausch-Mount `data/xchange` -> `/opt/oracle/xchange` in beiden neuen Services
      (RMAN-Backupsets, Wallet-Exports); `.gitignore` ergaenzen
- [ ] Makefile: `SERVICES` erweitern + `up/down/logs/bash/sql/reset-odbencprod` und
      `-odbencdev`
- [ ] `config/odbencprod/setup/`: abgeleitet von `config/odbenc/setup/` - PDB `ODBENCPROD`,
      TDE mit Software-Keystore, verschluesselter `USERS`-Tablespace, SCOTT/HR-Demodaten
- [ ] `config/odbencdev/setup/`: WALLET_ROOT, eigener Software-Keystore, eigener MEK,
      **keine** Nutzdaten, kein PDB-Clone. WALLET_ROOT loest in beiden Containern auf
      `/opt/oracle/dbconfig/FREE/wallet` auf, zeigt aber je Container auf ein eigenes
      Host-Verzeichnis - genau die Kundenkonstellation.
- [ ] ARCHIVELOG + FRA auf `odbencprod` aktivieren (Voraussetzung fuer DUPLICATE FROM
      ACTIVE DATABASE und fuer konsistente Restores)

### Phase 1 - Prod-Baseline auf odbencprod (CDBPROD)

- [ ] Canary-Tabelle in verschluesseltem `USERS`-Tablespace der PDB `ODBENCPROD`, wenige MB
- [ ] `ALTER TABLESPACE USERS READ ONLY` (Blockstabilitaet fuer den Ciphertext-Diff)
- [ ] Baseline erfassen: `V$ENCRYPTION_KEYS`, `V$ENCRYPTED_TABLESPACES`,
      `V$ENCRYPTION_WALLET`, `V$DATABASE_KEY_INFO`, `V$TABLESPACE`/`V$DATAFILE`
- [ ] Canary-Block lokalisieren (`DBMS_ROWID`) und Ciphertext-Hash je Block sichern
- [ ] Negativtest: Canary-String nicht im Datafile findbar
- [ ] `RMAN BACKUP DATABASE PLUS ARCHIVELOG` nach `/opt/oracle/xchange`
- [ ] Prod-MEK exportieren (`ADMINISTER KEY MANAGEMENT EXPORT KEYS`) nach `/opt/oracle/xchange`

### Phase 2 - Variante A: normaler RESTORE (Ist-Zustand beim Kunden)

- [ ] Prod-Wallet/MEK nach `odbencdev` importieren, Restore + Recover ohne `AS ENCRYPTED`
- [ ] Alle vier Nachweise erfassen. Erwartung: identischer Ciphertext, MASTERKEYID = Prod,
      Entzugstest schlaegt fehl (DB unbrauchbar ohne Prod-MEK)

### Phase 3 - Variante B: RESTORE ... AS ENCRYPTED USING KEY (Streitfall)

- [ ] `odbencdev` zuruecksetzen, eigenen MEK anlegen, Key-ID notieren
- [ ] `RESTORE DATABASE AS ENCRYPTED USING KEY '<dev_key_id>'` + Recover
- [ ] Dokumentieren, **ob** der Prod-MEK dafuer im Dev-Keystore vorhanden sein muss
      (Doku schweigt dazu - beide Faelle testen: mit und ohne Prod-MEK-Import)
- [ ] Alle vier Nachweise. Ciphertext-Diff entscheidet Re-wrap vs Re-encrypt

### Phase 4 - Variante C: DUPLICATE ... AS ENCRYPTED

- [ ] `odbencdev` zuruecksetzen, Auxiliary-Instanz NOMOUNT, Netzwerkpfad odbencprod -> odbencdev
- [ ] `DUPLICATE TARGET DATABASE TO FREE AS ENCRYPTED` (from active database und/oder aus Backup)
- [ ] Alle vier Nachweise. Doku-Wortlaut adressiert nur unverschluesselte Quellen -
      Verhalten bei verschluesselter Quelle protokollieren

### Phase 5 - Variante D: Referenz mit garantiert neuem TEK

- [ ] Nach dem Klon: neuen verschluesselten Tablespace im Dev anlegen, Canary-Daten
      umziehen, alten Tablespace droppen
- [ ] Ciphertext-Diff muss abweichen (Kontrollgruppe: so sieht echtes Re-encrypt aus)
- [ ] `ONLINE REKEY` in Free nicht verfuegbar - im Protokoll als EE-Weg dokumentarisch
      belegen, nicht messen

### Phase 6 - Entzugstest je Variante

- [ ] Prod-MEK aus Dev-Keystore entfernen, `STARTUP FORCE`, Canary-Zeile lesen
- [ ] Ergebnis je Variante in die Messmatrix

### Phase 7 - Deliverables

- [ ] `doc/tde-restore-as-encrypted.md`: Testprotokoll mit Befehlen, Rohoutput, Messmatrix,
      Bewertung, Doku-Quellen und offenen Punkten
- [ ] Messmatrix je Variante: Ciphertext-Diff | MASTERKEYID | KEY_VERSION | ENCRYPTEDKEY |
      Prod-MEK beim Klon noetig | Entzugstest | Bewertung
- [ ] Kunden-Praesentation: Varianten mit Empfehlung und Restrisiko
- [ ] Testskripte reproduzierbar im Repo (`config/odbencdev/`, `scripts/`)
- [ ] CHANGELOG.md ergaenzen

### Risiken und offene Punkte

- Recovery kann Blockinhalte anfassen und den Ciphertext-Diff verrauschen. Gegenmittel:
  Tablespace READ ONLY, konsistentes Backup, Vergleich auf den Canary-Datenblock begrenzt.
- Falls `RESTORE AS ENCRYPTED` bei verschluesselter Quelle einen Fehler wirft, ist auch das
  ein verwertbares Ergebnis fuer den Kunden - kein Testabbruch.
- DUPLICATE mit identischem DB_NAME `FREE` in beiden Containern: getrennte Hosts, sollte
  tragen. Falls nicht, Fallback auf Backup-basiertes DUPLICATE.
- 12-GB-Limit von Free ist bei wenigen MB Testdaten nicht relevant.

### Umgebungsbefund (2026-09-03)

- Docker-Desktop-VM: 8 GB RAM, 14 CPUs, aarch64. `DB_MEM=8g` gilt pro Service, zwei
  parallele Container wuerden 16 GB anfordern. Fix: `${ODBENCPROD_DB_MEM:-${DB_MEM}}` und
  `${ODBENCDEV_DB_MEM:-${DB_MEM}}` auf 3g - Oracle Free ist auf 2 GB SGA begrenzt.
- 113 GB Plattenplatz frei, Ports 1520-1540 und 5500-5520 frei, Image
  `oracle-free-labs:latest` lokal vorhanden, Netz `oracle-free-labs_default` existiert.
- `data/cdbfree` belegt 11 GB bei gestopptem Container - fuer den Test irrelevant.

### Phase 8 - Illustrationen (Zusatzaufgabe 2026-09-03)

Mermaid statt Excalidraw: rendert direkt im Protokoll-Markdown und ist ohne
zusaetzliches Werkzeug versionierbar.

- [ ] Architekturdiagramm der Schluesselhierarchie: Software Keystore -> MEK ->
      gewrappter TEK im Datafile-Header -> Datenbloecke. Mit dem gemessenen
      Fundort im Header (Block 1, Byte 785 fuer den TEK, Byte 833 fuer die
      MASTERKEYID) als Beleg.
- [ ] Diagramm Database Key vs Tablespace Key (SYSTEM/UNDO/TEMP gegen USERS)
- [ ] Sequenzdiagramm je Testvariante A bis D: wer haelt welchen Schluessel,
      was wandert von prod nach dev, was wird neu erzeugt
- [ ] Entscheidungsbaum fuer den Kunden: welches Verfahren erfuellt welche
      Trennungsanforderung
- [ ] Terminologiefalle als Diagramm: MEK-Rotation gegen Tablespace-Rekey
- [ ] MEK-Lebenslauf grafisch: wo liegt welcher MEK (Keystore-Datei
      ewallet.p12, Auto-Login cwallet.sso, SEPS-Store tde_seps), welcher ist
      aktiv, welcher CDB- gegen PDB-MEK, und was genau passiert bei
      SET KEY, bei Import eines fremden MEK und beim Restore je Variante.
      Zustand vorher/nachher je Variante als Diagramm, nicht nur als Tabelle.

### Baseline-Messwerte odbencprod (gemessen 2026-09-03)

Belegt und reproduzierbar, Messsatz `data/xchange/evidence/baseline/`:

- DBID 1515066983, LOG_MODE ARCHIVELOG (Image-Default, kein Skript noetig)
- PDB ODBENCPROD, Tablespace USERS: bigfile, AES256, CIPHERMODE XTS, TS# 6
- MASTERKEYID 8A27589796A248BE95222E59407FF962, KEY_VERSION 1
- gewrappter TEK BAD537ADDD695BEE7A29F6F27B65A03D6F195CCE3388AD0119D718087A8AFA55
- zwei MEKs, beide ORIGIN LOCAL (CDB con_id 1, PDB con_id 4)
- KEY_ID ist base64 des MASTERKEYID mit 0x01-Typprefix - rechnerisch verifiziert
- Canary SCOTT.CANARY_TDE: 5000 Zeilen, 313 Bloecke, Bereich 979-1407
- Kontrollgruppe SCOTT.CANARY_PLAIN_TAB in unverschluesseltem Tablespace
  CANARY_PLAIN: 5000 Zeilen, 313 Bloecke, Bereich 779-1279
- Klartext-Scan: 313 Treffer im unverschluesselten Datafile, 0 im verschluesselten
  Die 313 aus dem Rohdatei-Scan deckt sich mit den 313 aus DBMS_ROWID - damit ist
  die Block-zu-Offset-Rechnung unabhaengig bestaetigt
- gewrappter TEK physisch bei Offset 8977 = Block 1 Byte 785
- MASTERKEYID physisch bei Offset 9025 = Block 1 Byte 833, also 48 Byte nach dem
  TEK (32 Byte Schluessel + 16 Byte Fuellbytes)
- beide Sequenzen: genau 1 Treffer im verschluesselten Datafile, 0 in der
  Kontrolldatei
- USERS und CANARY_PLAIN vor dem Backup auf READ ONLY gesetzt
- RMAN Backup nach /opt/oracle/xchange/backup, Controlfile-Autobackup
  cf_c-1515066983-20260903-00

Merkposten fuer die Auswertung: DBMS_ROWID.ROWID_RELATIVE_FNO liefert bei
Bigfile-Tablespaces 0, waehrend DBA_DATA_FILES.RELATIVE_FNO 1024 meldet. Das ist
erwartetes Bigfile-Verhalten - ROWID_BLOCK_NUMBER traegt dann die vollstaendige
absolute Blocknummer, was fuer die Offset-Rechnung genau passt.

### Ergebnis Variante A - normaler RESTORE mit transportiertem Prod-Wallet

Gemessen 2026-09-03, Messsaetze `baseline` (odbencprod) und `variant_a` (odbencdev).

Schluesselkette im Klon, identisch zur Quelle:

- MASTERKEYID 8A27589796A248BE95222E59407FF962 - identisch
- KEY_VERSION 1 - identisch
- gewrappter TEK BAD537ADDD695BEE7A29F6F27B65A03D6F195CCE3388AD0119D718087A8AFA55
  - byteidentisch, und physisch an derselben Stelle: Offset 8977, Block 1 Byte 785

Blockvergleich des USERS-Datafiles, 2561 Bloecke:

| Kategorie | identisch | geaendert |
|---|---|---|
| Header-Bloecke 0-1 | 0 | 2 |
| Canary-Datenbloecke (313, aus DBMS_ROWID) | 313 | 0 |
| Bloecke im Canary-Bereich ohne Daten | 52 | 64 |
| Bloecke vor dem Canary-Bereich (2-979) | 904 | 73 |
| Bloecke nach dem Canary-Bereich (1408-2560) | 0 | 1153 |
| Gesamt | 1269 | 1292 |

Auswertung: alle 313 Bloecke mit echten Nutzdaten sind byteidentisch. Die
abweichenden Bloecke sind leere bzw. nie benutzte Bloecke - RMAN Backup
Optimization sichert leere Bloecke nicht, sondern schreibt sie beim Restore neu.
Belegt am Rohbyte-Vergleich: Block 2000 traegt in der Quelle Zufallsbytes, im Klon
nur Nullen nach dem Blockheader. Die Header-Bloecke unterscheiden sich nur in
Checkpoint-Metadaten - die TEK-Region im Header ist byteidentisch.

Nebenbefunde mit Kundenrelevanz:

- Ein LOCAL Auto-Login-Keystore oeffnet auf einem anderen Host nicht.
  Nach dem Wallet-Transfer stand `v$encryption_wallet` auf CLOSED /
  WALLET_TYPE UNKNOWN, Lesen scheiterte mit ORA-28365. Erst
  `SET KEYSTORE OPEN FORCE KEYSTORE IDENTIFIED BY <pwd>` oeffnete den Keystore,
  danach WALLET_TYPE PASSWORD. Betrifft auch den SEPS-Store `tde_seps`, der
  ebenfalls als LOCAL AUTO_LOGIN angelegt wird.
- `ORIGIN` zeigt fuer den transportierten Prod-Schluessel `LOCAL`, nicht
  `IMPORTED`. Wer das Keystore-File kopiert, hinterlaesst keine Spur der
  Herkunft - `ORIGIN` taugt nicht als Nachweis lokaler Schluesselerzeugung.

Entzugstest: Dev-eigenes Wallet zurueckgespielt, Instanz neu gestartet. Nur der
Dev-MEK sichtbar (AWZuopGe2EGHqnGxulapWxw..., ORIGIN LOCAL). Lesen des Canary
scheitert mit ORA-28374 "typed master key not found in wallet".

Bewertung Variante A: kein Re-encrypt, kein neuer TEK, kryptografisch vollstaendig
von Prod abhaengig. Fuer die Anforderung "keine Rueckschluesse auf Prod" untauglich.

### Phase 9 - Abschluss auf gruener Wiese (Anforderung 2026-09-03)

Nach Durchlauf aller Varianten alles verwerfen und aus dem committeten Stand neu
aufsetzen, ohne Zwischenkorrekturen. Das ist gleichzeitig der Reproduzierbarkeits-
nachweis fuer das Protokoll.

- [ ] `make reset SERVICE=odbencprod` und `SERVICE=odbencdev`, data/xchange leeren
- [ ] beide Services frisch hochziehen, Logs auf ORA-/SP2-Fehler pruefen -
      erwartet: keine, insbesondere kein SP2-0734/SP2-0042 mehr
- [ ] Phasen 1 bis 6 vollstaendig durchlaufen, ausschliesslich ueber die Skripte
- [ ] Messwerte gegen die hier dokumentierten vergleichen
- [ ] Erst danach gilt das Protokoll als abgenommen

### Ergebnisse Varianten B und der Entschluesselungspfad (gemessen 2026-09-03)

Variante B2 - AS ENCRYPTED USING KEY ohne Prod-MEK im Ziel-Keystore:

- `RESTORE DATABASE AS ENCRYPTED USING KEY '<dev_mek>'` scheitert mit
  ORA-19870 plus ORA-28374 "typed master key not found in wallet"
- Aussage: RMAN braucht den Quell-MEK, um die verschluesselten Quellbloecke
  ueberhaupt zu lesen. Ein RMAN-Klon ohne Transfer des Prod-Schluessels
  existiert nicht.

Variante B1 - AS ENCRYPTED USING KEY mit Prod-MEK und neu erzeugtem Ziel-MEK:

- Ziel-Keystore enthielt beide Prod-Schluessel plus einen neuen, per
  `ADMINISTER KEY MANAGEMENT CREATE KEY` erzeugten Schluessel
- Das erste Backup-Set mit den unverschluesselten CDB-Datafiles wurde
  erfolgreich restauriert, Laufzeit 5:45 gegenueber 3 Sekunden bei einem
  normalen Restore. Auf unverschluesselten Quelldateien leistet AS ENCRYPTED
  also echte Blockarbeit - der dokumentierte Fall funktioniert und ist messbar.
- Sobald RMAN das bereits verschluesselte Datafile 20 erreicht:
  ORA-00600 [kcbtse_encdec_tbsblk_1], [4], [2], [806], [18], [806], [20], ...
- Deterministisch: dreimal reproduziert, mit und ohne `FORCE`, identische
  Argumente. Keystore war jeweils offen (WALLET_TYPE PASSWORD).

Entschluesselungspfad - RESTORE ... FORCE AS DECRYPTED:

- Funktioniert bei verschluesselter Quelle. `FORCE` ist zwingend: ohne
  FORCE ueberspringt die Restore-Optimierung genau die Datafiles, die schon
  auf Stand sind - der Lauf sieht erfolgreich aus und sagt nichts.
- Danach `DBA_TABLESPACES.ENCRYPTED = NO`, `V$ENCRYPTED_TABLESPACES` leer,
  Canary lesbar, und der Klartext-Marker ist mit 313 Treffern im Datafile
  auffindbar - die Bloecke sind echt entschluesselt.
- Die DB oeffnet trotzdem nicht ohne den Prod-MEK. Alert Log:
  `KZTDE:kztsmptc: Missing Key ID: AbyhIcXQQk+...`,
  `Active database master key not found in the wallet!`,
  `mkid bca121c5d0424f9788162b2b3ac8dc56` - der aktive CDB-Master-Key.
  Tablespaces zu entschluesseln bricht die Abhaengigkeit also nicht.
- `ADMINISTER KEY MANAGEMENT SET KEY ... CONTAINER=ALL` dreht den
  CDB-Database-Key auf einen dev-eigenen MEK (BCA121C5...DC56 nach
  6E930457...BFB3), scheitert aber mit ORA-46663, weil PDB$SEED keinen
  Schluessel hat. SET KEY in der PDB dreht deren Key auf 8252C3B0...BCA7.

Kernbefund - der TEK ueberlebt jeden dieser Wege:

- Nach `AS DECRYPTED` plus `SET KEY` plus `ALTER TABLESPACE USERS ENCRYPTION
  OFFLINE ENCRYPT` sind die 313 Canary-Datenbloecke **byteidentisch zu Prod**.
  Gewrappter TEK und MASTERKEYID sind neu, Prods Werte physisch nicht mehr im
  Datafile - aber das Chiffrat der Daten ist dasselbe.
- Kontrolliert wiederholt: offline DECRYPT (Marker mit 313 Treffern im
  Klartext nachgewiesen), dann offline ENCRYPT - erneut byteidentisch zu Prod,
  KEY_VERSION 3 dann 5, gewrappter TEK unveraendert 8FBDA2A8...3E41.
- Identisches Chiffrat bei identischem Inhalt und identischer Blockadresse
  bedeutet identischer TEK. Der Tablespace-Key uebersteht den
  Konvertierungszyklus, nur seine Verpackung wechselt.

Positivkontrolle - erkennt die Methode einen TEK-Wechsel ueberhaupt?

- Zwei frische verschluesselte Tablespaces CTRL_ENC_A und CTRL_ENC_B in Prod,
  identische DDL, identischer Canary-Inhalt, beide belegen Bloecke 779-1279
  mit 313 Bloecken, gewrappte TEKs 6B6A512A... und F29E623B... unter demselben MEK
- 367 von 501 Bloecken im Bereich unterscheiden sich. Die Methode ist also
  sensitiv fuer einen TEK-Wechsel, und der Nullbefund oben ist keine Blindheit
  des Messverfahrens.

### Offener Pruefpunkt - _db_discard_lost_masterkey

Hinweis Stefan 2026-09-03. Der Hidden Parameter `_db_discard_lost_masterkey`
verwirft die Master-Key-Handles aus den Datafile-Headern und adressiert damit
genau den oben gemessenen Zustand: nichts mehr verschluesselt, aber der aktive
Master Key aus der Quelle blockiert das Oeffnen.

Bedingungen, die im Protokoll und in der Praesentation mitstehen muessen:

- Hidden Parameter, in einer MOS Note dokumentiert, Einsatz nur nach Freigabe
  durch Oracle Support - nicht nach Gutduenken setzen
- fachlich nur zulaessig, wenn tatsaechlich kein verschluesseltes Objekt mehr
  existiert, also nach vollstaendigem AS DECRYPTED
- `ssenc_info.sql` fragt den Parameter bereits in der Hidden-Parameter-Liste ab

- [ ] Als eigene Variante messen: AS DECRYPTED, dann Master-Key-Handles
      verwerfen, dann in Dev von Null auf verschluesseln. Erwartung, die zu
      pruefen ist: dann entsteht neues TEK-Material, weil kein alter
      Schluesselhandle mehr im Header steht - der Blockvergleich muesste
      abweichen wie in der Positivkontrolle.

### Recherche-Korrekturen 2026-09-03

Zwei Punkte, die dokumentierte Annahmen im Protokoll korrigieren:

1. `TDE_CONFIGURATION` unterscheidet UNITED und ISOLATED nicht ueber seinen Wert.
   Beide nutzen `KEYSTORE_CONFIGURATION=FILE`. Der Moduswechsel laeuft laut
   Oracle 26ai "Administering United Mode" ueber
   `ADMINISTER KEY MANAGEMENT ISOLATE KEYSTORE ... FROM ROOT KEYSTORE` in der PDB
   und zurueck ueber `UNITE KEYSTORE`. Die Praxisbeobachtung, dass ein in der PDB
   gesetztes `TDE_CONFIGURATION` ein eigenes Keystore-File erzeugt, ist damit
   nicht belegt und im Lab zu messen.
2. `_db_discard_lost_masterkey` ist laut asanga-pradeep-Blog kein Mittel, eine DB
   zu oeffnen, sondern erlaubt ein `ADMINISTER KEY MANAGEMENT SET KEY`, obwohl der
   referenzierte Schluessel fehlt. Dort verwendet als
   `ALTER SYSTEM SET "_db_discard_lost_masterkey"=true SCOPE=MEMORY`.
   Mein Labortest war deshalb falsch angesetzt: ich habe nur `ALTER DATABASE OPEN`
   versucht, kein `SET KEY`.
   Der Blog dokumentiert ausserdem die Alert-Log-Warnung "replacing lost SYSAUX key
   with new database key due to prior wallet deletion. Encrypted blocks in SYSAUX
   tablespace would appear corrupted, since the original key is replaced" und
   berichtet bei wiederholtem Einsatz echte Korruptionen, ORA-01595 und ORA-28304.

Weitere belegte Punkte fuer das Protokoll:

- Dokumentierter Weg bei ORA-28374 ist `MERGE KEYSTORE` aus einem Backup-Wallet,
  alternativ `IMPORT KEYS`. Quelle: Oracle 26ai, ORA-28374 Troubleshooting.
- `ONLINE REKEY` ist das einzige dokumentierte Verfahren fuer neues
  Tablespace-Key-Material, seit 12.2.0.1. OFFLINE-Operationen sind laut Doku
  nicht fuer Rekeying vorgesehen.
- In UNITED Mode braucht jede PDB einen eigenen MEK. Ein Weg, PDB-Tablespace-Keys
  direkt mit dem CDB-Root-MEK zu wrappen, ist nicht belegt. Nur eine Non-CDB hat
  naturgemaess einen einzigen MEK.
- Der asanga-pradeep-Blog bestaetigt indirekt unseren Befund zum normalen Restore:
  bereits verschluesselte Bloecke werden beim RMAN-Backup unveraendert
  durchgereicht, nur unverschluesselte erhalten Backup-Verschluesselung.
- MOS-Notes zu `_db_discard_lost_masterkey` sind nicht frei einsehbar. Genannt
  werden in einer Sekundaerquelle 1301365.1, 1228046.1, 1241925.1 ohne Inhalt.
  Dass Oracle Support eine Freigabe verlangt, ist oeffentlich nicht belegt und
  bleibt eine Vorgabe aus der Praxis.

### Zusaetzliche Messpunkte fuer den Gruene-Wiese-Lauf

- [ ] `_db_discard_lost_masterkey` richtig testen: nach `FORCE AS DECRYPTED` und
      nachgewiesen leerem `V$ENCRYPTED_TABLESPACES` den Parameter mit
      `SCOPE=MEMORY` setzen und dann `ADMINISTER KEY MANAGEMENT SET KEY`
      ausfuehren, nicht nur `ALTER DATABASE OPEN`. Alert Log auf die
      SYSAUX-Warnung pruefen und sie im Protokoll zitieren.
- [ ] UNITED gegen ISOLATED messen: in der PDB `TDE_CONFIGURATION` setzen und
      pruefen, ob ein eigenes Keystore-File entsteht. Gegenprobe mit
      `ADMINISTER KEY MANAGEMENT ISOLATE KEYSTORE`. Damit ist der Widerspruch
      zwischen Praxisbeobachtung und Primaerdoku entschieden.
- [ ] Variante C `DUPLICATE ... AS ENCRYPTED` nachholen, sie fehlt noch komplett.
- [ ] `MERGE KEYSTORE` als dokumentierten Weg einmal durchspielen, damit die
      Empfehlung an den Kunden nicht nur zitiert, sondern gezeigt ist.

### Variante C - Vorversuche und Fallstricke (2026-09-03)

Zwei Anlaeufe, beide nicht bis zu einem Messergebnis gekommen. Die Fallstricke sind
festgehalten, damit der Gruene-Wiese-Lauf nicht darueber stolpert.

Anlauf 1, `FROM ACTIVE DATABASE`:

- `ORA-12514: Service FREE is not registered` - der Servicename lautet
  `FREE.oradba.ch`, weil `common_db_config.sql` `db_domain='oradba.ch'` setzt.
  Registriert sind laut lsnrctl: FREE.oradba.ch, FREEXDB.oradba.ch,
  odbencprod.oradba.ch und der PDB-GUID-Service. Ein `tnsping` auf
  `odbencprod:1521/FREE` meldet trotzdem OK - es prueft nur die Adresse, nicht
  den Service. Nicht darauf verlassen.
- Mit korrektem Servicenamen stand die Target-Verbindung, dann scheiterte die
  Rueckverbindung der Auxiliary-Instanz zum Target:
  `RMAN-06136 ... ORA-17629: cannot connect to the remote database server`,
  `ORA-17627: ORA-01017: invalid credential or not authorized`.
  Die SYS-Passwoerter beider Container sind nachweislich identisch (Vergleich
  per Hash ohne Ausgabe des Werts), die Ursache ist damit nicht das Passwort
  selbst. Offen.

Anlauf 2, `BACKUP LOCATION` ohne Target-Verbindung:

- `DUPLICATE DATABASE TO FREE BACKUP LOCATION '/opt/oracle/xchange/backup'
  NOFILENAMECHECK AS ENCRYPTED` startet, meldet erwartete RMAN-05158-Warnungen
  zu Pfadkonflikten und bricht dann ab mit
  `RMAN-03015 ... RMAN-06136: ORA-01507: database not mounted`.
- Ursache ist der Zustand des Ziels, nicht die Klausel: odbencdev trug zu diesem
  Zeitpunkt Prods Controlfile, hatte ein OPEN RESETLOGS hinter sich und ein
  veraendertes SPFILE. DUPLICATE erwartet eine unberuehrte Auxiliary-Instanz.

Konsequenz: Variante C ist nur auf einem frischen odbencdev messbar und wird im
Gruene-Wiese-Lauf als erste Variante gefahren, bevor irgendein Restore das Ziel
veraendert.

## Gruene-Wiese-Lauf 2026-09-03 (Abnahmelauf)

Vollstaendiger Neuaufbau aus dem committeten Stand, ohne Zwischenkorrekturen.

### Startzustand - fehlerfrei

| Service | Setup-Skripte | Meldung | ORA/SP2/DBT-Zeilen | checkDBStatus.sh |
|---|---|---|---|---|
| odbencprod | 12 | DATABASE IS READY TO USE | 0 | exit 0 |
| odbencdev | 2 | DATABASE IS READY TO USE | 0 | exit 0 |

Beide Container `healthy`. Zwei Defekte waren dafuer noch zu beheben, siehe
Commit `74d8de0`: das Reset-Target stellte nur die README wieder her und
verwarf die `.gitkeep`-Marker, und `odbencdev` meldete einen Setup-Fehler, weil
der Entrypoint-Healthcheck eine offene User-PDB verlangt.

### Baseline odbencprod

- DBID 1515072404, ARCHIVELOG, PDB ODBENCPROD
- MEK CDB con_id 1: AX6Pmn3ZnEskqh9sLfCA4yE... ORIGIN LOCAL
- MEK PDB con_id 4: AQHQDfbAHEU1kpgFJFfaj5g... ORIGIN LOCAL
- Tablespace USERS: AES256, KEY_VERSION 1,
  MASTERKEYID 01D00DF6C01C45359298052457DA8F98,
  gewrappter TEK E36623ECEAF2AA7D0AE19D6AE59E0D9E8CEFEF94BC4F6A2B1FC726E8EC1F934F
- Canary SCOTT.CANARY_TDE: 313 Bloecke, Bereich 979-1407
- Kontrollgruppe SCOTT.CANARY_PLAIN_TAB: 313 Bloecke, Bereich 779-1279
- Klartext-Scan: 313 Treffer in der unverschluesselten Kontrolldatei ab Block 779,
  0 Treffer in der verschluesselten
- gewrappter TEK physisch bei Offset 8977, Block 1 Byte 785
- MASTERKEYID physisch bei Offset 9025, Block 1 Byte 833
- RMAN Backup nach /opt/oracle/xchange/backup,
  Autobackup cf_c-1515072404-20260903-02
- odbencdev vor den Varianten: DBID 1515074205, eigener MEK
  AfWleiW/Okw2uSymAnITWic... ORIGIN LOCAL, FREEPDB1 READ WRITE,
  FREEPDB1-Wallet OPEN_NO_MASTER_KEY

### Reproduzierbarkeit gegen den ersten Lauf

Strukturell deckungsgleich, obwohl die Datenbanken unabhaengig neu erzeugt wurden:

| Groesse | Erster Lauf | Gruene Wiese |
|---|---|---|
| Canary-Bloecke USERS | 313, Bereich 979-1407 | 313, Bereich 979-1407 |
| Canary-Bloecke Kontrolle | 313, Bereich 779-1279 | 313, Bereich 779-1279 |
| Klartext-Treffer Kontrolle | 313 ab Block 779 | 313 ab Block 779 |
| Offset gewrappter TEK | 8977, Block 1 Byte 785 | 8977, Block 1 Byte 785 |
| Offset MASTERKEYID | 9025, Block 1 Byte 833 | 9025, Block 1 Byte 833 |

Die Schluesselwerte selbst sind naturgemaess neu. Dass Blockbereiche und
Header-Offsets bitgenau uebereinstimmen, belegt den deterministischen Aufbau -
der deterministische Canary-Payload war dafuer die Voraussetzung.

### Querschnittsbefund - transportierte Keystores und Auto-Login

In drei Varianten unabhaengig aufgetreten, gehoert in die Praesentation:

1. `csenc_swkeystore.sql` erzeugt ein **LOCAL** Auto-Login-Keystore. Das ist an
   den erzeugenden Host gebunden. Nach dem Transport steht
   `v$encryption_wallet` auf CLOSED mit WALLET_TYPE UNKNOWN, Zugriff scheitert
   mit ORA-28365. Betrifft auch den SEPS-Store `tde_seps`.
2. Ein per Passwort geoeffneter Keystore ueberlebt keinen Instanz-Neustart.
   Genau daran scheiterten `RESTORE ... AS ENCRYPTED` und
   `DUPLICATE ... AS ENCRYPTED`: beide starten die Instanz ueber eigene
   Memory-Scripts mehrfach neu, danach ist der Keystore zu und es kommt
   ORA-28365 aus `DBMS_BACKUP_RESTORE.RESTORESETDATAFILE`.
3. Die mitgebrachte `cwallet.sso` blockiert die Neuerzeugung eines lokalen
   Auto-Login-Keystores mit ORA-46630 "Keystore cannot be created at location".

Vorgehen, das im Lab funktioniert:

```sql
-- fremde cwallet.sso beiseite legen, ewallet.p12 mit den Schluesseln behalten
-- dann auf dem Zielhost neu erzeugen:
ADMINISTER KEY MANAGEMENT CREATE LOCAL AUTO_LOGIN KEYSTORE
  FROM KEYSTORE '/opt/oracle/dbconfig/FREE/wallet/tde' IDENTIFIED BY <pwd>;
```

Konsequenz fuer den Kunden: beim Klon einer TDE-Datenbank ist der Keystore
nicht einfach kopierbar. Die Schluesseldatei `ewallet.p12` wandert, die
Auto-Login-Datei muss am Ziel neu erzeugt werden. Wer das uebersieht, sieht
ORA-28365 an einer Stelle, die nach einem Backup-Problem aussieht.

### Ergebnis Variante C - DUPLICATE ... AS ENCRYPTED (gemessen 2026-09-03)

Erste `AS ENCRYPTED`-Variante, die bei verschluesselter Quelle ueberhaupt
durchlaeuft. Voraussetzung war ein auf dem Zielhost neu erzeugtes
Auto-Login-Keystore, siehe Querschnittsbefund oben.

Ablauf: `DUPLICATE DATABASE TO FREE BACKUP LOCATION '/opt/oracle/xchange/backup'
NOFILENAMECHECK AS ENCRYPTED` gegen eine unberuehrte Auxiliary-Instanz,
`FROM ACTIVE DATABASE` scheiterte an ORA-17627/ORA-01017 und wurde nicht
weiterverfolgt.

- Lauf endet mit "database opened" und "Finished Duplicate Db"
- Klon traegt eine **neue DBID** 1515081178 gegen 1515072404 in der Quelle -
  DUPLICATE erzeugt eine eigenstaendige Datenbank, keine Kopie
- Datafile 20 und 21 wurden verarbeitet
- Canary 5000 Zeilen, 5000 Marker-Treffer, lesbar
- Klartext-Scan im Klon: 0 Treffer, weiterhin verschluesselt

Schluessellage im Klon, PDB ODBENCPROD:

| Tablespace | TS# | KEY_VERSION | gewrappter TEK |
|---|---|---|---|
| SYSTEM | 0 | 0 | 566B2C9C...69CE |
| SYSAUX | 1 | 0 | 566B2C9C...69CE |
| UNDOTBS1 | 2 | 0 | 566B2C9C...69CE |
| AUDIT_DATA | 5 | 0 | 566B2C9C...69CE |
| CANARY_PLAIN | 7 | 0 | 566B2C9C...69CE |
| USERS | 6 | 0 | E36623EC...934F |

In der Quelle ist nur USERS verschluesselt, mit demselben TEK
E36623EC...934F und KEY_VERSION 1.

Auswertung: `AS ENCRYPTED` hat die fuenf zuvor **unverschluesselten** Tablespaces
neu verschluesselt, alle unter dem gemeinsamen Database Key 566B2C9C...69CE.
Der bereits verschluesselte USERS behielt seinen Original-TEK aus der Quelle.
Genau das sagt der Doku-Wortlaut "...that are not encrypted" - hier am
Verhalten belegt statt nur zitiert.

Blockvergleich des USERS-Datafiles gegen die Prod-Baseline:

| Kategorie | identisch | geaendert |
|---|---|---|
| Header-Bloecke 0-1 | 1 | 1 |
| Canary-Datenbloecke (313) | 313 | 0 |
| Canary-Bereich ohne Daten | 54 | 62 |
| vor dem Canary-Bereich (2-978) | 904 | 73 |
| nach dem Canary-Bereich (1408+) | 0 | 1153 |
| Gesamt | 1272 | 1289 |

Alle 313 Bloecke mit Nutzdaten byteidentisch. Die abweichenden Bloecke sind
wieder die leeren, die RMAN Backup Optimization nicht sichert und beim Restore
neu schreibt.

MEKs im Klon: beide aus der Quelle, AX6Pmn3ZnEskqh9sLfCA4yE... con_id 1 und
AQHQDfbAHEU1kpgFJFfaj5g... con_id 4, jeweils ORIGIN LOCAL.
MASTERKEYID unveraendert 01D00DF6C01C45359298052457DA8F98.

Bewertung: fuer die Anforderung "keine Rueckschluesse auf Prod" untauglich,
solange der Tablespace bereits in der Quelle verschluesselt war. Fuer eine
unverschluesselte Quelle ist es dagegen das passende Werkzeug - dann entsteht
im Ziel nachweislich neues Schluesselmaterial.

### Messmatrix vollstaendig

| Variante | Canary-Bloecke identisch | TEK USERS | Ergebnis |
|---|---|---|---|
| A normaler RESTORE | 313 von 313 | unveraendert | laeuft, haengt am Prod-MEK |
| B1 AS ENCRYPTED mit Prod-MEK | - | - | ORA-00600 kcbtse_encdec_tbsblk_1 |
| B2 AS ENCRYPTED ohne Prod-MEK | - | - | ORA-19870 plus ORA-28374 |
| C DUPLICATE AS ENCRYPTED | 313 von 313 | unveraendert | laeuft, neue DBID, TEK bleibt |
| D AS DECRYPTED plus SET KEY plus OFFLINE ENCRYPT | 313 von 313 | unveraendert | MEK neu, Chiffrat identisch |
| Positivkontrolle neuer Tablespace | 134 von 501 im Bereich | neu | TEK-Wechsel nachweisbar |

Kernaussage: kein RMAN-basierter Weg erneuert den Tablespace-Encryption-Key
eines bereits verschluesselten Tablespace. Neues Schluesselmaterial entsteht nur
ueber einen neuen verschluesselten Tablespace, laut Doku zusaetzlich ueber
ONLINE REKEY, das in Free nicht verfuegbar ist.

### Algorithmus-Test AES192 - die Mechanik hinter allen Nullbefunden

Idee Stefan 2026-09-03: einen anderen Algorithmus erzwingen. Wenn AES192 statt
AES256 greift, muss der TEK zwingend neu sein, weil die Schluessellaenge
abweicht. Kein Deutungsspielraum mehr.

Gefundener Hebel, dokumentierter Parameter ohne Unterstrich, in 26ai vorhanden:

- `tablespace_encryption_default_algorithm`, Default AES256, ISSYS_MODIFIABLE
  IMMEDIATE, ISPDB_MODIFIABLE TRUE
- `tablespace_encryption_default_cipher_mode`, Default XTS
- `_tablespace_encryption_default_algorithm` aus aelteren Releases existiert in
  26ai nicht mehr

Kernbefund - der Datafile-Header behaelt den Schluessel-Handle:

- `ALTER TABLESPACE USERS ENCRYPTION OFFLINE USING 'AES192' ENCRYPT` scheitert
  mit ORA-28340 "A different encryption algorithm has been chosen for the table
  or tablespace" - auch dann, wenn der Tablespace zuvor vollstaendig
  entschluesselt wurde
- Nach dem Decrypt ist der Tablespace echt entschluesselt: ENCRYPTED NO, keine
  Zeile in `v$encrypted_tablespaces`, Canary mit 313 Treffern im Klartext im
  Datafile auffindbar
- **Der alte gewrappte TEK liegt danach weiterhin im Header, am selben Offset
  8977.** Der Decrypt raeumt die Datenbloecke ab, nicht den Schluessel-Handle.
- Neuverschluesseln ohne `USING` ergibt wieder AES256 mit demselben TEK
  E36623EC...934F, KEY_VERSION 2
- Damit ist erklaert, warum in allen Varianten der TEK ueberlebt

Was funktioniert - ein neuer Tablespace, mit dem Beweis in der Schluessellaenge:

| Tablespace | Alg | signifikante Bytes | = Bit |
|---|---|---|---|
| USERS aus Prod | AES256 | 32 | 256 |
| NEW_AES192 (Parameter-Default) | AES192 | 24 | 192 |
| NEW_EXPL192 (explizit USING) | AES192 | 24 | 192 |
| NEW_EXPL128 (explizit USING) | AES128 | 16 | 128 |

Die kuerzeren Schluessel sind im RAW(32)-Feld mit Nullbytes aufgefuellt. Damit
ist neues Schluesselmaterial nicht nur plausibel, sondern an der Laenge ablesbar.

Nebenbefund - XTS ist an AES256 gebunden:

- `ALTER SYSTEM SET tablespace_encryption_default_algorithm='AES192'` scheitert
  bei aktivem XTS mit ORA-38134 "not supported by currently specified default
  cipher mode XTS"
- AES192 und AES128 erfordern CFB. Wer auf AES192 wechselt, verlaesst XTS.
  Gehoert in die Kundenempfehlung, XTS ist der modernere Modus.
- Achtung bei der Messung: CDB\$ROOT und PDB koennen unterschiedliche Werte
  haben. Ein Ausgangswert aus CDB\$ROOT und ein Setzen in der PDB fuehrt zu
  falschen Schluessen.

### _db_discard_lost_masterkey - Teilergebnis

- `SCOPE=MEMORY` wird abgelehnt: ORA-02097 mit ORA-28355 "failed to initialize
  security module". Der Parameter wird beim Init des Security-Moduls gelesen,
  nicht zur Laufzeit.
- Mit `SCOPE=SPFILE` plus Neustart: SPFILE-Wert TRUE, Laufzeit-Wert FALSE. Im
  Alert Log erscheint er beim Start als `_db_discard_lost_masterkey= TRUE`.
  Deutung: ein Einmal-Flag, das beim Start konsumiert und zurueckgesetzt wird.
  Im ersten Versuch blieb er TRUE, weil die Datenbank dort nicht oeffnete - das
  Flag wurde nie verbraucht. Das erklaert beide Beobachtungen.
- Der AES192-Versuch scheiterte weiter mit ORA-28340. Die Vorbedingung war aber
  nicht erfuellt: 9 verschluesselte Tablespaces im CDB, davon SYSTEM, SYSAUX und
  UNDOTBS1 aus Variante C, die sich nicht offline entschluesseln lassen.
- Offen: Test an einem Klon, in dem nur USERS verschluesselt ist, sodass nach
  dem Decrypt tatsaechlich nichts mehr verschluesselt ist.

### Oracle bestaetigt den Hauptbefund selbst

Im Alert Log nach `ADMINISTER KEY MANAGEMENT SET KEY`:

```text
KZTDE: Set Master Key: Tablespace key rewrap done
```

Oracle nennt es woertlich **rewrap**. Ein Master-Key-Wechsel wickelt den
Tablespace-Key neu ein, mehr nicht. Das ist die Bestaetigung der Blockmessung
aus der Datenbank selbst statt aus einer Sekundaerquelle.

### Variante F - der Weg, der die Schluesselkette bricht (gemessen 2026-09-03)

Erste und einzige gemessene Variante, die einen **neuen Tablespace-Encryption-Key**
erzeugt und damit die Anforderung "keine Rueckschluesse auf Prod" erfuellt.

Ablauf, reproduzierbar:

1. Variante A: normaler `RESTORE DATABASE` mit transportiertem Quell-Keystore
2. `ALTER TABLESPACE USERS ENCRYPTION OFFLINE DECRYPT` - danach pruefen, dass
   `containers(v$encrypted_tablespaces)` **0** Zeilen liefert. Die Daten liegen in
   diesem Fenster im Klartext, das ist ein bewusster Sicherheitskompromiss.
3. Keystore-Verzeichnis beiseite legen und einen **frischen** Keystore anlegen:
   `ADMINISTER KEY MANAGEMENT CREATE KEYSTORE IDENTIFIED BY <pwd>` plus
   `SET KEYSTORE OPEN` plus `SET KEY ... CONTAINER=ALL`. Damit sind die
   Quell-MEKs weg.
4. `ALTER SYSTEM SET "_db_discard_lost_masterkey"=TRUE SCOPE=MEMORY` **in der PDB**
5. `ADMINISTER KEY MANAGEMENT SET KEY ... FORCE KEYSTORE IDENTIFIED BY <pwd>
   WITH BACKUP` in der PDB - jetzt erfolgreich
6. `ALTER TABLESPACE USERS ENCRYPTION OFFLINE ENCRYPT`

Entscheidend bei Schritt 4: der Parameter muss **in der PDB** gesetzt werden.
`ISPDB_MODIFIABLE` ist TRUE. Auf CDB-Ebene scheitert `SCOPE=MEMORY` mit ORA-02097
plus ORA-28355 "failed to initialize security module", und `SCOPE=SPFILE` plus
Neustart wirkt nicht - der SPFILE-Wert steht auf TRUE, der Laufzeitwert bleibt
FALSE. Genau daran sind meine ersten drei Versuche gescheitert.

Ergebnis, vollstaendig verifiziert:

| Pruefung | Wert |
|---|---|
| Quell-MEKs im Keystore | 0 |
| MEKs im Keystore | 5, alle ORIGIN LOCAL, im Ziel erzeugt |
| PDB Database-Key | B0A4B54D52C74AF6AC6AF07E037C0B74, vorher 01D00DF6...8F98 |
| TEK USERS | D40B030F...F03F, vorher E36623EC...934F |
| KEY_VERSION | 3 |
| Algorithmus / Cipher Mode | AES256 / XTS, unveraendert |
| Quell-TEK im Datafile-Header | 0 Treffer |
| Quell-MASTERKEYID im Header | 0 Treffer |
| Blockvergleich gegen Quelle | 2561 von 2561 Bloecken unterschiedlich |
| Canary-Datenbloecke | 313 von 313 unterschiedlich |
| Canary lesbar | 5000 Zeilen, 5000 Marker-Treffer |
| open_mode | READ WRITE ohne jeden Quell-Schluessel |

Das Werkzeug urteilt "RE-ENCRYPT INDICATED - every comparable block changed" -
derselbe Urteilsspruch, den die synthetische Positivkontrolle erzeugt.

Der Entzugstest ist hier implizit bestanden: die Quell-MEKs sind nicht bloss
unbenutzt, sie existieren im Ziel-Keystore nicht mehr, und die Datenbank laeuft.

Was `_db_discard_lost_masterkey` leistet und was nicht:

- Es verwirft den **Master-Key**-Handle und erlaubt `SET KEY`, obwohl der
  referenzierte Schluessel fehlt. Ohne das Flag: ORA-28374.
- Es verwirft **nicht** die Algorithmus-Bindung des Tablespace. `AES192` scheitert
  auch mit aktivem Flag weiter mit ORA-28340. Fuer die Trennung ist das
  unerheblich, weil der TEK ohnehin neu ist - AES256 bleibt erhalten.

Auflagen, die in Protokoll und Praesentation mitstehen muessen:

- Hidden Parameter, in einer MOS Note dokumentiert, Einsatz nur nach Freigabe
  durch Oracle Support
- fachlich nur zulaessig, wenn nachweislich kein verschluesseltes Objekt mehr
  existiert - Schritt 2 ist die Bedingung, nicht eine Option
- Sekundaerquelle warnt bei wiederholtem Einsatz vor echten Korruptionen,
  genannt ORA-01595 und ORA-28304, sowie vor der Alert-Log-Warnung zu einem
  ersetzten SYSAUX-Key
- gemessen in Oracle AI Database Free 26ai, nicht in EE
- im Fenster zwischen Schritt 2 und 6 liegen die Daten unverschluesselt

- [x] `_db_discard_lost_masterkey` korrekt gemessen

## Runde 2 - Klaerung, Aufbereitung, End-to-End (Plan 2026-09-04)

### Korrekturen an Runde 1 - zwingend vor der Praesentation

1. **ONLINE REKEY ist in Free technisch verfuegbar.** Gemessen: KEY_VERSION 3 -> 4,
   TEK D40B030F...F03F -> A4C84E43...426B, 2560 von 2561 Bloecken geaendert (nur
   Block 0, der OS-Dateikopf, bleibt gleich), altes Datafile physisch entfernt und
   durch ein neues ersetzt, alte TEKs im neuen File nicht mehr auffindbar.
   Die Licensing Restriction ist eine Lizenz- und Supportaussage, kein technischer
   Riegel. Frueherer Protokolltext "in Free nicht pruefbar" ist falsch.
2. **Variante C erzeugte kein neues Schluesselmaterial.** Der in Runde 1 als "neuer
   gemeinsamer TEK" gemeldete Wert 566B2C9C...69CE ist der **Database Key der PDB in
   der Quelle**. AS ENCRYPTED hat die fuenf unverschluesselten Tablespaces unter dem
   bereits vorhandenen Database Key verschluesselt. Die Aussage "fuer eine
   unverschluesselte Quelle entsteht nachweislich neues Schluesselmaterial" ist falsch.
3. `tde_evidence.sh --compare` paart Fingerprints ueber den Dateinamen. ONLINE REKEY
   legt ein neues Datafile an, dadurch lief der Vergleich stumm leer. Der leere Fall
   muss laut werden und der Vergleich bei genau einem Datafile je Satz namensunabhaengig.

### Drei Schluesselebenen - gemessen an odbencprod

| Ebene | Wo sichtbar | Format | Wert in der Baseline | Rolle |
|---|---|---|---|---|
| MEK | `v$encryption_keys`, Keystore | KEY_ID base64 | CDB AX6Pmn3Z..., PDB AQHQDfbA... | wickelt die Ebenen darunter ein, liegt im Keystore |
| Database Key | `v$database_key_info` | RAW(48), 32 Byte signifikant | CDB 61E7C128..., PDB 566B2C9C...69CE | je Container einer, existiert auch wenn SYSTEM/UNDO/TEMP unverschluesselt sind |
| Tablespace Key | `v$encrypted_tablespaces` | RAW(32) | USERS E36623EC...934F | je verschluesselter Tablespace einer, liegt gewrappt im Datafile-Header |

Offen und zu klaeren: wo genau liegt der Database Key physisch, wird er direkt vom
MEK gewrappt, und was passiert mit ihm bei MEK-Rekey, ONLINE REKEY und Klon.

### Arbeitspakete

- [ ] AP1 Schluesselebenen abschliessend klaeren: MEK, Database Key, TS Key -
      Speicherort, Wrapping-Beziehung, Verhalten bei jeder Operation. Messung plus
      Doku-Recherche.
- [ ] AP2 Mermaid-Grafiken: Schluesselhierarchie mit Keystore-Dateien, Varianten je
      Diagramm, Variantenvergleich, Testumgebung, Ablaufdiagramm, Stufenmodell der
      Unabhaengigkeit, Angriffsflaechen. Nur Mermaid, Stefan macht sie schoen.
- [ ] AP3 Varianten tabellarisch und grafisch konsolidieren - ein Ueberblick, der
      den Chatverlauf ersetzt.
- [ ] AP4 Testumgebung und Testfaelle dokumentieren, inkl. Architektur und Ablauf.
- [ ] AP5 Runbook separat und vollstaendig, fuer die manuelle Verifikation.
- [ ] AP6 Stufenmodell kryptografische Unabhaengigkeit: welche Stufe erreicht welches
      Verfahren, was bleibt jeweils gemeinsam.
- [ ] AP7 Angriffsflaechen: was ist mit MEK, Database Key, TS Key aus einer Test-DB
      hypothetisch und was real moeglich. Trennung zwingend.
- [ ] AP8 OKV-Argumentation gegen die beiden Kundeneinwaende.
- [ ] AP9 Praesentation im Accenture-Brand.
- [ ] AP10 End-to-End-Lauf auf gruener Wiese, alle Varianten, protokolliert.

### Abhaengigkeitsmodell MEK / Database Key / Tablespace Key - gemessen 2026-09-04

Alle Werte an odbencdev gemessen, Container ODBENCPROD, UNITED Mode.

Die drei Ebenen:

| Ebene | View | Format | Speicherort | Anzahl |
|---|---|---|---|---|
| MEK | `v$encryption_keys` | KEY_ID base64 | Keystore `ewallet.p12` | je Container ein aktiver, dazu die Historie |
| Database Key | `v$database_key_info` | RAW(48), 32 Byte signifikant | von Oracle verwaltet, vom MEK gewrappt | je Container einer |
| Tablespace Key | `v$encrypted_tablespaces` | RAW(32) | gewrappt im Datafile-Header, bei 8K in Block 1 Byte 785 | je verschluesseltem Tablespace einer |

Der zentrale, vorher unklare Punkt: **ein Tablespace hat nicht zwingend einen eigenen
Schluessel.** Gemessen:

- `ALTER TABLESPACE ... ENCRYPTION OFFLINE ENCRYPT` verschluesselt den Tablespace mit
  dem **Database Key** des Containers. Nach Variante F trug USERS als Schluessel exakt
  den DB-Key-Wert D40B030F...F03F.
- `ALTER TABLESPACE ... ENCRYPTION ONLINE ENCRYPT` und `ONLINE REKEY` erzeugen einen
  **eigenen** Tablespace Key. CANARY_PLAIN erhielt A1EBE741..., USERS nach ONLINE REKEY
  A4C84E43...426B - beide verschieden vom DB Key.
- `RMAN ... AS ENCRYPTED` verschluesselt zuvor unverschluesselte Tablespaces ebenfalls
  mit dem **Database Key der Quelle**. In Variante C erhielten SYSTEM, SYSAUX, UNDOTBS1,
  AUDIT_DATA und CANARY_PLAIN alle den Wert 566B2C9C...69CE, den DB Key der Quell-PDB.

Damit deckt sich die gemessene Mechanik mit dem Doku-Wortlaut zu Online-Operationen,
"the tablespace will have its own independent encryption keys and algorithms".

Wirkung je Operation, gemessen:

| Operation | MEK | Database Key | Tablespace Key | Datenbloecke |
|---|---|---|---|---|
| `SET KEY` MEK-Rotation | neu | neu gewrappt, Klartextschluessel gleich | neu gewrappt, KEY_VERSION unveraendert | unveraendert, 2560 von 2561 identisch, nur Header-Block 1 |
| `ONLINE REKEY` | unveraendert | unveraendert | **neuer Schluessel**, KV plus 1 | **alle neu verschluesselt**, neues Datafile, altes entfernt |
| `ONLINE ENCRYPT` | unveraendert | unveraendert | **neuer eigener Schluessel** | verschluesselt |
| `OFFLINE ENCRYPT` | unveraendert | unveraendert | **uebernimmt den Database Key** | verschluesselt |
| `OFFLINE DECRYPT` | unveraendert | unveraendert | Handle bleibt im Header stehen | entschluesselt |
| RMAN `AS ENCRYPTED` | Quelle | Quelle | unverschluesselte TS erhalten den DB Key, verschluesselte behalten ihren | bei bereits verschluesselten unveraendert |

Belege fuer die MEK-Rotation im Detail:

- MEK mkid B0A4B54D...0B74 -> DEFA0240...6A3A
- DB Key PDB gespeicherter Wert D40B030F...F03F -> 2349D6D3...9B7A, mkid folgt dem MEK
- TS Key USERS gespeicherter Wert A4C84E43...426B -> B1DB7C22...A8BE, KEY_VERSION bleibt 4
- Blockvergleich: 2560 von 2561 identisch, Verdict "RE-WRAP INDICATED"
- Alert Log woertlich: "KZTDE: Set Master Key: Tablespace key rewrap done"

**Read-only-Tablespaces werden bei der MEK-Rotation nicht umgewickelt.** CANARY_PLAIN
stand auf READ ONLY und verweist danach weiter auf den alten MEK B0A4B54D...0B74,
waehrend USERS und der DB Key auf DEFA0240...6A3A zeigen. Oracle kann den Header eines
Read-only-Tablespace nicht schreiben. Folge: der alte MEK bleibt zwingend erforderlich,
und genau deshalb muss die vollstaendige Schluesselhistorie im Keystore bleiben.
Operativ relevant, weil Archiv-Tablespaces haeufig read-only sind.

### Angriffsflaechen - gemessen 2026-09-04

Testreihe zu den beiden Kundeneinwaenden. Alle Aussagen gemessen, nicht hergeleitet.

**A1 Sind die Nutzdaten in der Produktion im Klartext auffindbar?**
Klartext-Scan des Prod-Datafiles nach dem Canary-Marker: 0 Treffer. Im
unverschluesselten Kontroll-Tablespace derselben Datenbank: 313 Treffer. Die
Verschluesselung wirkt, und der Test ist falsifizierbar.

**A2 Liegt der Tablespace-Key im Datafile?**
Ja, als gewrappte Bytefolge, genau 1 Treffer bei Offset 8977 gleich Block 1 Byte 785.
Er ist damit fuer jeden lesbar, der das Datafile hat - aber nur in mit dem MEK
verschluesselter Form.

**A3 Kann eine Test-DB ohne Prod-MEK Prod-Daten restaurieren oder lesen?**
Nein. RMAN-Restore von Prods verschluesseltem Tablespace in die Test-DB, deren Keystore
ausschliesslich eigene Schluessel enthaelt (Prod-MEKs: 0 von 6):

```text
ORA-19870: error while restoring backup piece .../0506atr0_5_1_1
ORA-28374: typed master key not found in wallet
```

Der Restore bricht ab, bevor ueberhaupt gelesen wird. Die Test-DB kennt alle
TS-Key-Werte aus ihren eigenen V$-Views - das nuetzt nichts.

**A4 Verraet byteidentisches Chiffrat etwas?**
Nach Variante A sind 313 von 313 Canary-Datenbloecken byteidentisch zur Produktion.
Nach Variante F sind 2561 von 2561 Bloecken unterschiedlich. Was identisches Chiffrat
tatsaechlich preisgibt, ist ein Existenz- und Aenderungsvergleich: wer Prod- und
Test-Datafile hat, erkennt blockweise, ob sich ein Datenblock zwischen den beiden
unterscheidet, ohne ihn zu entschluesseln. Klartext gewinnt er dadurch nicht.

**Einordnung der Kundeneinwaende, ausschliesslich auf diese Messungen gestuetzt:**

Einwand "man kann mit den TS-Key-Infos aus der Test die Prod entschluesseln" ist so
nicht zutreffend. Der Tablespace-Key ist ueberall nur gewrappt verfuegbar, im
Datafile-Header und in `v$encrypted_tablespaces`. Ohne den zugehoerigen MEK ist er
nicht verwertbar, und der Restore scheitert bereits an ORA-28374.

Der real gefaehrliche Punkt liegt anders und wird von dem Einwand verdeckt: die
gaengige Klon-Praxis, Variante A, **kopiert den Prod-Keystore in die Non-Prod**. Damit
liegt der Prod-MEK dort - dauerhaft, samt vollstaendiger Schluesselhistorie, und
`ORIGIN` zeigt fuer diese Schluessel `LOCAL` statt `IMPORTED`, die Herkunft ist an den
Views also nicht erkennbar. Wer Zugriff auf die Non-Prod hat, hat dann den
Produktionsschluessel. Zusaetzlich gemessen: eine MEK-Rotation raeumt die Historie
nicht ab, und Read-only-Tablespaces bleiben sogar an den alten MEK gebunden.

Das ist das Argument fuer eine getrennte Schluesselhoheit: nicht weil TS-Keys leaken,
sondern weil der Klon-Prozess den Master Key mitkopiert und ihn dort niemand mehr sieht.

- [ ] Offen: Gegentest, ob eine Test-DB **mit** transportiertem Prod-Keystore Prod-Daten
      restaurieren und lesen kann. Erwartung nach Variante A: ja. Im E2E-Lauf messen.

### Algorithmus-Test abgeschlossen - ONLINE REKEY erneuert das Schluesselmaterial

Gemessen 2026-09-04 an odbencprod, eigener Tablespace ALGTEST, danach wieder entfernt.
Die Baseline in USERS wurde nicht angetastet.

Zuerst die Korrektur meines frueheren Befunds: ORA-28340 kam vom **falschen Kommando**.
Oracle dokumentiert fuer den SYSTEM-Tablespace woertlich, dass die ENCRYPT-Klausel keinen
Algorithmus annimmt, weil beim ersten Mal mit dem bestehenden Database Key verschluesselt
wird, und dass man danach die REKEY-Klausel nutzen muss, um den Algorithmus zu setzen.
Quelle: Oracle Advanced Security Guide 19c, Configuring Transparent Data Encryption.
Mein Versuch lief ueber `ENCRYPTION OFFLINE USING 'AES192' ENCRYPT` - das ist der falsche
Weg. Der richtige ist `ENCRYPTION ONLINE USING 'AES192' REKEY`.

Ablauf und Ergebnis:

| Groesse | vor dem Rekey | nach dem Rekey |
|---|---|---|
| Algorithmus | AES256 | AES192 |
| Cipher Mode | XTS | CFB |
| KEY_VERSION | 0 | 2 |
| gewrappter TEK | 3792A5BB...84A0 | D1D460D8...2DD3 plus Nullbytes |
| signifikante Schluesselbytes | 32 gleich 256 Bit | 24 gleich 192 Bit |
| Datafile | o1_mf_algtest_o9ny40mp_.dbf | neu: o1_mf_algtest_o9ny6csn_.dbf |
| Canary | 5000 Zeilen | 5000 Zeilen |
| Blockvergleich | - | 2560 von 2561 geaendert, nur Block 0 gleich |
| alter TEK im neuen Datafile | - | 0 Treffer |
| neuer TEK im neuen Datafile | - | 1 Treffer |

Das ist der belastbarste Beweis der ganzen Reihe: eine andere Schluessellaenge kann
kein umgewickelter alter Schluessel sein. Damit ist unabhaengig vom Chiffratvergleich
belegt, dass ONLINE REKEY neues Schluesselmaterial erzeugt.

Nebenbefund zum Geltungsbereich des Algorithmus:

- `ALTER TABLESPACE ... ENCRYPTION ONLINE USING 'AES192' REKEY` wird akzeptiert, obwohl
  der Instanz-Default-Cipher-Mode auf XTS stand, und stellt diesen Tablespace auf CFB.
  KEY_VERSION lief von 0 auf 2, beide Rekey-Anweisungen liefen also durch.
- `ALTER SYSTEM SET tablespace_encryption_default_algorithm='AES192'` wird bei aktivem
  XTS dagegen mit ORA-38134 abgelehnt.
- Belegt in der SQL Language Reference 26ai zur encryption_spec-Klausel: XTS ist nur mit
  AES128 und AES256 erlaubt, fuer AES192 ist CFB zu verwenden. XTS existiert erst ab
  23ai, 19c kennt nur CFB.

Merkposten: `odbencdev` war fuer diesen Test nicht mehr verwendbar. Der Angriffstest
mit dem fehlgeschlagenen Restore hat das USERS-Datafile in ORA-01113 "needs media
recovery" hinterlassen, und ein INSERT scheiterte mit ORA-28374. Der Container wird im
E2E-Lauf neu aufgebaut.

## Plan zum Review - PDB-Clone als weiterer Use Case

Noch nicht umgesetzt. Nur Plan und Varianten zur Abnahme.

### Warum das ein eigener Use Case ist

Bisher gemessen wurde ausschliesslich der Weg ueber RMAN, also RESTORE und DUPLICATE auf
CDB-Ebene. Der PDB-Clone laeuft ueber einen anderen Mechanismus und hat einen eigenen,
dokumentierten Schluesseltransport: die Schluessel muessen explizit exportiert und
importiert werden, statt implizit im Keystore mitzureisen. Genau dieser Unterschied ist
fuer die Kundenfrage relevant, weil `ORIGIN` beim formalen Import `IMPORTED` zeigt statt
`LOCAL` - die Herkunft wird also nachvollziehbar, anders als beim kopierten Keystore.

Die Infrastruktur ist im Repo vorhanden: `config/common/scripts/create_pdb_archive.sql`,
`create_pdb_from_archive.sql` und `clone_pdb.sql`, und die Services odbseed und odbdemo
arbeiten bereits mit PDB-Archiven.

### Varianten

| Nr | Variante | Erwartung, zu pruefen |
|---|---|---|
| P1 | Lokaler Clone in derselben CDB, `CREATE PLUGGABLE DATABASE neu FROM alt` | gleicher Keystore, TEK bleibt, kein Transport noetig - Referenzfall |
| P2 | Unplug mit Schluesselexport, Plug in fremde CDB, `UNPLUG INTO ... ENCRYPT USING <secret>` und `... DECRYPT USING <secret>` | Schluessel reisen im Archiv, PDB oeffnet, TEK unveraendert |
| P3 | Unplug **ohne** Schluesselexport, Plug in fremde CDB | erwartet: PDB oeffnet nicht oder nur RESTRICTED, verschluesselte Tablespaces unlesbar, ORA-28374 |
| P4 | Remote Clone ueber DB-Link, `CREATE PLUGGABLE DATABASE ... FROM pdb@link` mit vorherigem `EXPORT KEYS` und `IMPORT KEYS` | Schluessel muessen separat transportiert werden |
| P5 | Nach P2 oder P4: MEK-Rotation im Ziel | erwartet: Rewrap, Bloecke unveraendert - Gegenprobe zum RMAN-Befund |
| P6 | Nach P2 oder P4: `ONLINE REKEY` im Ziel | erwartet: neuer TEK, alle Bloecke neu - der Weg zur Unabhaengigkeit |
| P7 | `ORIGIN`-Vergleich: formal importierter Schluessel gegen kopierten Keystore | erwartet: IMPORTED gegen LOCAL - Provenienz nachweisbar |
| P8 | `KEY_VERSION` nach Plug-in in eine fremde CDB | Doku sagt, KEY_VERSION wird nach Plug-in in eine fremde Datenbank auf 0 zurueckgesetzt - zu verifizieren |

### Messgroessen je Variante

Identisch zur bisherigen Reihe, damit die Ergebnisse vergleichbar bleiben:

- Schluesselkette vor und nach dem Clone: MEK je Container, Database Key, TS Key,
  MASTERKEYID, KEY_VERSION, ORIGIN
- Blockweiser Chiffratvergleich des Canary-Datafiles gegen die Quelle
- Suche des gewrappten TEK und der MASTERKEYID als Bytefolge im Ziel-Datafile
- Klartext-Scan mit dem Canary-Marker
- Entzugstest: Quell-Schluessel im Ziel entfernen, Instanz neu starten, Canary lesen

### Testumgebung

Beide bestehenden Services genuegen. `odbencprod` als Quelle mit PDB ODBENCPROD und dem
verschluesselten USERS-Tablespace, `odbencdev` als Ziel-CDB. Fuer P4 braucht es
zusaetzlich einen Datenbank-Link von dev nach prod und einen gemeinsamen Ablagepfad, den
`data/xchange` bereits bietet. Fuer P2 und P3 wird das PDB-Archiv nach
`/opt/oracle/xchange` geschrieben.

Bekannter Fallstrick aus der bisherigen Reihe, der hier wieder greift: der Servicename
ist `FREE.oradba.ch`, nicht `FREE`, und `tnsping` auf den falschen Service meldet
trotzdem OK.

### Entscheide zum Plan (2026-09-04)

1. **P3 wird gefahren.** Der Negativbeleg ist den Aufraeumzyklus wert: er zeigt, was
   passiert, wenn beim Transport der Schluessel vergessen wird.
2. **Eigene Test-PDB.** Nicht ODBENCPROD klonen, sondern eine kleinere PDB nur fuer die
   Clone-Tests anlegen. Die Baseline in ODBENCPROD bleibt damit unberuehrt und die
   bisherigen Messsaetze bleiben vergleichbar.
3. **Dedizierter Clone-Benutzer statt SYS.** Der Link von dev nach prod laeuft nicht als
   SYS - genau daran ist das RMAN-Active-Duplicate mit ORA-01017 gescheitert. Stattdessen:

   ```sql
   CREATE USER c##clone IDENTIFIED BY <passwort> CONTAINER=ALL;
   GRANT CREATE SESSION, CREATE PLUGGABLE DATABASE TO c##clone CONTAINER=ALL;
   ```

   Das Passwort wird zur Laufzeit aus der Container-Umgebung gelesen und nie ausgegeben.

### Testbed fuer die PDB-Clone-Reihe

- Quell-PDB `PDBCLONE` in `odbencprod`, klein gehalten: ein verschluesselter Tablespace
  `CLONE_ENC` mit AES256, ein unverschluesselter `CLONE_PLAIN` als Kontrolle, je 5000
  Canary-Zeilen mit deterministischem Payload wie in der bisherigen Reihe.
- Common User `c##clone` in `odbencprod` mit den beiden Rechten oben.
- Ziel-CDB `odbencdev`, PDB-Archive und Schluesselexporte ueber `data/xchange`.
- Der Testbed-Aufbau gehoert in ein eigenes Testskript zur Laufzeit, nicht in die
  Container-Setup-Skripte. Damit bleibt `config/odbencprod/` weiterhin analog zu
  `config/odbenc/` und der Startvorgang unveraendert.

### Defekt im Runner - Dry-Run verseucht die State-Datei

Gefunden 2026-09-04 beim Gegenpruefen der Gates.

Die Gates funktionieren korrekt: `--only 20` ohne vorherigen Backup-Schritt meldet
`GATE VIOLATION: prerequisite 'step 15 (backup)' not met (BACKUP_READY is unset)` und
das Ergebnis steht als `GATE` statt `PASS` in der Tabelle.

Der Dry-Run schreibt aber Platzhalter in dieselbe State-Datei
`data/xchange/evidence/lab_state.env`, unter anderem `SOURCE_DBID=DRY-RUN-DBID`,
`SOURCE_TEK=DRY-RUN-TEK` und `BACKUP_READY=TRUE`. Folge: nach einem Dry-Run sind die
Gates faelschlich offen, und ein spaeterer Einzelschritt kann eine erfundene DBID
verwenden. Das ist genau die Klasse Fehler, die wie erledigte Arbeit aussieht.

- [x] `write_state` schreibt im Dry-Run nicht mehr, sondern loggt nur.
- [x] verify: nach `run_all.sh --dry-run` existiert keine State-Datei, und
      `--only 20` meldet weiterhin GATE VIOLATION.

### Gegenpruefung der PDB-Skripte - zwei sicherheitsrelevante Korrekturen

Die Skripte kamen shellcheck-clean und mit funktionierenden Gates, zwei Stellen musste
ich aber korrigieren:

1. **Passwort im geteilten Mount.** Der Remote-Clone schrieb `ORACLE_PWD` nach
   `/opt/oracle/xchange/.clone_cred` mit dem Kommentar "prod container only". Das ist
   falsch: `/opt/oracle/xchange` ist der gemeinsame Bind-Mount, die Datei lag damit
   unter `data/xchange/` auf dem Host und war auch fuer den Ziel-Container lesbar.
   `chmod 600` im Container hilft dagegen nicht. Jetzt wird das Passwort aus dem
   Quell-Container in eine Shell-Variable gelesen und dem Ziel ueber stdin uebergeben -
   weder in argv noch in einer Datei. Dass es im `CREATE DATABASE LINK` und damit
   potenziell in `V$SQL` erscheint, ist bei DB-Links unvermeidbar und im Skript vermerkt.
2. **Hartcodierte Transport-Secrets.** `OEHRLI-CLONE-SECRET-P2` und `-P4` standen fest
   im Code. Auch im Lab ist ein festes Secret im Repository ein committetes Secret, und
   es bringt nichts: das Secret muss nur zwischen Export und Import **eines** Laufs
   passen. Wird jetzt je Lauf zufaellig erzeugt.

Nicht beanstandet, weil sachlich richtig: dass P2 und P3 die Quell-PDB nach dem Unplug
wieder zurueckstecken. Ohne das waere PDBCLONE nach dem ersten Lauf aus der Quelle
verschwunden und P4 nicht mehr fahrbar. Die Reihe bleibt so in beliebiger Reihenfolge
einzeln ausfuehrbar.

### DBID-Identitaet je Klon-Verfahren - Hinweis Stefan 2026-09-04

Fachlicher Zusammenhang, der die Autobackup-Kollision aus dem E2E-Lauf erklaert:

- **RMAN RESTORE behaelt die DBID der Quelle.** Der Klon ist fuer RMAN dieselbe
  Datenbank. Gemessen: odbencdev hatte DBID 1515139043, nach dem Restore trug es
  Prods 1515140319.
- **DUPLICATE erzeugt eine neue DBID.** Gemessen: Klon 1515081178 gegen Quelle
  1515072404.
- Wer beim Restore-Weg eine eigene DBID will, braucht `DBNEWID` (`nid`) mit neuem
  DB-Namen und neuer DBID, oder ein manuell erzeugtes Controlfile.

Konsequenzen:

1. Fuer das Lab: die gleiche DBID ist die Ursache dafuer, dass das Ziel seine
   Controlfile-Autobackups in denselben `cf_c-<DBID>-*`-Namensraum schreibt und
   `FROM AUTOBACKUP` das falsche Piece zieht. Der `--cf-piece`-Fix behandelt das
   korrekt, die saubere Loesung waere `nid` nach dem Restore.
2. Fuer den Kunden, und das gehoert in den Variantenvergleich: ein Klon per
   RESTORE ist an der DBID **nicht** von der Produktion unterscheidbar. Das
   betrifft Backup-Kataloge, Data Guard, Monitoring und die Frage, wer welche
   Datenbank vor sich hat. DUPLICATE liefert eine eigene Identitaet.

- [ ] Variantenvergleich um die Spalte DBID erweitern: behaelt Quelle gegen neu.
- [x] Entscheid 2026-09-04: `nid` wird **nicht** als Messvariante gefahren, der
      Aufwand steht nicht im Verhaeltnis. Nur dokumentieren: `DBNEWID` ist der
      Weg zu einer eigenen DBID nach einem Restore, und eine neue DBID aendert
      Identitaet, nicht Schluesselmaterial - der TEK bleibt. Als Erwartung
      kennzeichnen, nicht als Messung.

### Hinweise Stefan zu den offenen Schritten (2026-09-04)

- **Schritt 60, `_db_discard_lost_masterkey`:** bisher nur in Single-Tenant
  genutzt. Deckt sich mit unserer Messung, dass der Parameter in der PDB gesetzt
  werden muss. Fuer Multitenant ist das Verhalten damit nicht durch Praxis
  gedeckt - im Protokoll als solches kennzeichnen.
- **Schritte 63 und 64, PDB-Archiv:** eine entladene PDB kann nicht einfach
  wieder eingesteckt werden, sie muss dazwischen geloescht werden. Die Skripte
  machen das bereits: `UNPLUG INTO ... .pdb`, dann
  `DROP PLUGGABLE DATABASE ... INCLUDING DATAFILES`, dann
  `CREATE PLUGGABLE DATABASE ... USING <archiv>`.
  Offener Punkt, im Lauf zu belegen: bei der Endung `.pdb` erzeugt Oracle ein
  selbsttragendes Archiv inklusive Datafiles, bei `.xml` nur das Manifest. Nur
  im ersten Fall ist `INCLUDING DATAFILES` korrekt. Indikator ist die
  Archivgroesse - liegt sie im GB-Bereich, sind die Datafiles enthalten.
- **Schritt 65, Remote Clone:** braucht nur den DB-Link und den Benutzer, keine
  weiteren Vorkehrungen. In einer Produktionsumgebung mit einer 15 TB grossen PDB
  so durchgefuehrt. Unser Aufbau entspricht dem.

## Offene Beobachtungen aus dem Lauf ab Schritt 50 (2026-09-04)

- `ensure_autologin_for` meldet "open via local auto-login", `V$ENCRYPTION_WALLET`
  zeigt aber `WALLET_TYPE = PASSWORD`. Der Keystore ist offen, das Verdict ist
  davon nicht betroffen - die Meldung behauptet aber einen Zustand, den die View
  nicht bestaetigt. Vor dem E2E-Lauf entweder Auto-Login wirklich erzeugen oder
  die Meldung auf "open" zuruecknehmen.
- Nebenbefund mit Kundenrelevanz, direkt aus dem Log von Schritt 50:
  in der Dev-CDB stehen vier Schluessel, zwei davon stammen aus Prod - `ORIGIN`
  meldet fuer **alle vier** `LOCAL`. Die Herkunft eines transportierten MEK ist
  in der View nicht sichtbar. Das ist die empirische Grundlage fuer das
  Provenance-Argument in `doc/tde-okv-argumentation.md`.
- Zwei Defekte in der PDB-Serie vor dem ersten Lauf gefunden und behoben:
  SIGPIPE-Abbruch in der Variableninitialisierung (Schritte 63/65) und
  Secrets im Host-Prozesslisting via `docker exec bash -c` (Schritt 65).

### Messwert Variante D, isoliert auf die Canary-Bloecke (2026-09-04)

Runde 1 hatte fuer Variante D 1406 identische / 1155 abweichende Bloecke ueber
das ganze Datafile gemeldet. Die Differenz stammt aus nie benutzten Bloecken,
die RMAN nicht sichert und beim Restore neu schreibt - sie sagen nichts.
Auf die Bloecke reduziert, die tatsaechlich Canary-Zeilen tragen:

```text
canary blocks: identical 313  differing 0  total 313
```

Ein vollstaendiger `OFFLINE DECRYPT` -> neuer MEK -> `OFFLINE ENCRYPT`-Zyklus
reproduziert das Chiffrat der Quelle **byteweise**. Gewrappter TEK und
MASTERKEYID sind neu, das Chiffrat ist unveraendert. Damit ist belegt, dass die
Offline-Konversion den Database Key des Containers verwendet und kein neues
Tablespace-Schluesselmaterial erzeugt - und dass `ENCRYPTEDKEY` aus
`V$ENCRYPTED_TABLESPACES` als Beweismittel untauglich ist: der Wert aendert
sich beim reinen Re-wrap genauso wie bei neuem Schluesselmaterial.

### Der Kontrast D gegen F ist der Beweis fuer das Drei-Ebenen-Modell

Beide Varianten fuehren dieselbe Operation aus: `ALTER TABLESPACE USERS
ENCRYPTION OFFLINE ENCRYPT`. Der einzige Unterschied liegt darin, ob der
**Database Key des Containers** erneuert wurde:

| | Variante D | Variante F |
|---|---|---|
| MEK | neu (`SET KEY`) | neu (frischer Keystore) |
| Database Key | unveraendert | erneuert (`_db_discard_lost_masterkey`) |
| Operation | `OFFLINE ENCRYPT` | `OFFLINE ENCRYPT` |
| Canary-Chiffrat | **313 identisch / 0 abweichend** | muss abweichen |

Wenn F tatsaechlich abweichendes Chiffrat liefert, ist damit empirisch belegt,
dass `OFFLINE ENCRYPT` sein Tablespace-Schluesselmaterial aus dem Database Key
des Containers ableitet und nicht aus dem MEK - die MEK-Rotation allein aendert
das Chiffrat nachweislich nicht. Das ist die Messgrundlage fuer die dritte
Ebene in `doc/tde-key-architecture.md`, die Oracle selbst nur zweistufig
dokumentiert.

TODO nach Schritt 60: Verdict von Variante F zusaetzlich auf das
Canary-Chiffrat stellen (analog Variante G), damit die Aussage nicht nur am
gespeicherten Schluesselwert haengt.

### Operativer Befund fuer den Green-Field-Pfad (2026-09-04)

Wer den Schluesselstamm einer Kopie wirklich kappen will, muss den alten
Keystore aus dem **Speicher** bekommen, nicht nur von der Platte:

- `ADMINISTER KEY MANAGEMENT SET KEYSTORE CLOSE` scheitert bei einem
  Auto-Login-Keystore mit `ORA-28389: Cannot close auto login keystore`.
- Solange `cwallet.sso` im Verzeichnis liegt, oeffnet sich der Keystore nach
  einem Close sofort wieder - gemessen: Status `OPEN / LOCAL_AUTOLOGIN` in
  allen Containern direkt nach einem erfolgreichen `keystore altered`.
- Auch nach dem Entfernen der Dateien bleibt der Kontext im Speicher offen.
  Folge: `CREATE KEYSTORE` gelingt, `SET KEYSTORE OPEN` scheitert mit
  `ORA-28354`, und das anschliessende `SET KEY` mit `ORA-28417`.
- Einziger belegter Weg: Instanz neu starten, nachdem die Keystore-Dateien
  entfernt sind. Zulaessig nur, wenn nichts mehr verschluesselt ist - genau
  die Vorbedingung, die Stefan fuer `_db_discard_lost_masterkey` genannt hat.

Reihenfolge fuer das Runbook: Tablespaces entschluesseln und pruefen
(`V$ENCRYPTED_TABLESPACES` = 0 Zeilen) -> Keystore-Dateien entfernen ->
**Instanz neu starten** -> `CREATE KEYSTORE` -> `SET KEYSTORE OPEN` ->
`SET KEY` je Container -> `_db_discard_lost_masterkey` in der PDB
(`SCOPE=MEMORY`) -> `SET KEY` in der PDB -> `OFFLINE ENCRYPT`.

### Gemessen: der Database Key ist die wirksame Ebene (2026-09-04)

| | Variante D | Variante F |
|---|---|---|
| MEK | neu (`SET KEY`) | neu (frischer Keystore) |
| Database Key | unveraendert | erneuert (`_db_discard_lost_masterkey`) |
| Operation | `OFFLINE ENCRYPT` | `OFFLINE ENCRYPT` |
| Canary-Chiffrat | 313 identisch / 0 abweichend | 0 identisch / 313 abweichend |

Dieselbe Anweisung, entgegengesetztes Ergebnis, eine einzige veraenderte
Variable. Die MEK-Rotation allein aendert das Chiffrat nachweislich nicht;
neues Tablespace-Schluesselmaterial entsteht erst, wenn der Database Key des
Containers erneuert wird. Oracle dokumentiert nur zwei Ebenen - diese Messung
ist die Grundlage fuer die dritte in `doc/tde-key-architecture.md`.

### Nebenbefund: ORA-28374 beim CDB-weiten SET KEY

Nach dem Austausch des Keystores scheitert `ADMINISTER KEY MANAGEMENT SET KEY`
in `CDB$ROOT` mit `ORA-28374: typed master key not found in wallet`. Die CDB
verweist weiter auf Prods MEK-ID. Eine Datenbank, die ihren MEK verloren hat,
kann nicht einfach einen neuen annehmen - genau dafuer existiert
`_db_discard_lost_masterkey`, und der ist nur in der PDB setzbar. Das ist eine
zweite, unabhaengige empirische Widerlegung der Kundeneinwand-Logik "wir
tauschen einfach den Schluessel aus".

### Systemischer Defekt, noch offen: `sqlplus | grep` verschluckt Fehlerstatus

`sqlplus -S / as sysdba <<SQL | grep -viE "identified by"` liefert den
Exit-Status von **grep**, nicht von sqlplus. Ein fehlgeschlagenes SQL-Statement
beendet den sqlplus-Lauf mit `WHENEVER SQLERROR EXIT SQL.SQLCODE`, der Status
geht in der Pipe aber verloren - `set -e` greift nicht, und der Schritt laeuft
weiter. Genau so blieb das ORA-28374 oben ohne Folge.

Betroffen ist das Muster in mehreren Skripten (`sqlplus_prod`, `sqlplus_dev`,
alle `lib_run in_dev`/`in_prod`-Bloecke). Vor dem finalen E2E-Lauf beheben:
`set -o pipefail` in den betroffenen Container-Skripten oder
`${PIPESTATUS[0]}` auswerten.

## Zentraler neuer Befund: der PDB-Klon erzeugt neues Schluesselmaterial

Gemessen 2026-09-04, Schritt 62 (P1, lokaler Klon in derselben CDB):

| | Quelle `PDBCLONE` | Klon `PDBCLONE_P1` |
|---|---|---|
| MASTERKEYID | `F99544E45B4B4A5298EFD7D0CEBEDCA7` | `F99544E45B4B4A5298EFD7D0CEBEDCA7` |
| ENCRYPTEDKEY | `212154F58E503609D1B726C2DDDA1F36267FDD0A978001650996AE1AF832BE8C` | `0602F0724EEA2DB3BCBA408137DAB21ADD86177377E473FA5E9713631F06866C` |
| KEY_VERSION | 0 | 0 |
| Canary-Chiffrat | - | 0 identisch / 313 abweichend |
| Blockvergleich gesamt | - | 1 identisch / 6400 abweichend |

Die Beweisfuehrung steht auf zwei unabhaengigen Beinen:

1. Der **MEK ist identisch** - gleiche CDB, gleicher Keystore. Ein Re-wrap
   unter unveraendertem MEK ergaebe denselben gewrappten Wert. Der Wert weicht
   ab, also ist das Schluesselmaterial neu. Das ist ein logischer Schluss, der
   ohne Annahmen ueber die IV-Ableitung auskommt.
2. Das Chiffrat der Canary-Bloecke ist zu 100 Prozent abweichend.

`KEY_VERSION` ist auf beiden Seiten 0 und traegt hier keine Information -
ein weiteres Beispiel dafuer, dass die View-Spalten die Frage nicht beantworten.

### Konsequenz fuer die Kundenaussage

Bis hierhin galt: **kein** RMAN-Pfad erneuert den Tablespace-Key eines bereits
verschluesselten Tablespace (Varianten A, C, D gemessen; B1/B2 brechen ab).
Neues Schluesselmaterial entstand nur ueber `ONLINE REKEY` oder ueber den
Discard-Pfad (Variante F, mit Hidden Parameter und Oracle-Support-Freigabe).

Der PDB-Klon aendert diese Antwort: er liefert neues TEK-Material mit einem
einzigen, regulaer unterstuetzten Kommando. Fuer den Kunden ist das der
praktikable Weg von Prod nach Dev - vorbehaltlich der noch offenen Messungen
in Schritt 63 (Archiv-Transport) und 65 (Remote Clone), die zeigen muessen,
ob das auch ueber CDB-Grenzen hinweg gilt.

Erwartung in `doc/`-Dateien und im Plan war "P1: TEK identisch zur Quelle" -
diese Annahme ist widerlegt und muss in der Dokumentation korrigiert werden.
