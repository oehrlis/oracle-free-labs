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
