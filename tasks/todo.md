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
- [x] 5.3 Explizite Targets: `up-<service>`, `down-<service>`, `logs-<service>`, `bash-<service>`, `sql-<service>`, `reset-<service>` für alle 6 Services
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
