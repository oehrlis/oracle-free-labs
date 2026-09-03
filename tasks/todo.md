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
