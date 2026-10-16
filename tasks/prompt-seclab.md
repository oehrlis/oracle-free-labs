# Prompt - autonome Session: Service `seclab` (unsichere Security-Baseline)

Selbsttragend. Den Codeblock unter "Der Prompt" in eine frische Claude-Code-Session im Repo
einfuegen. Er weist die Session an, **diese Datei zuerst vollstaendig zu lesen** - Szenario-Katalog,
Leitplanken und Fallen stehen hier, nicht im Block. Erstellt 2026-10-15.

## Der Prompt

```text
Baue im Repo /Users/stefan.oehrli/Repos/own/oehrlis/oracle-free-labs den neuen Service
`seclab` autonom bis zum Release. Arbeite ohne Rueckfragen, solange nichts Unerwartetes
passiert, das eine Leitplanke beruehrt.

LIES ZUERST tasks/prompt-seclab.md in diesem Repo, vollstaendig. Diese Nachricht ist nur
der Einstieg; die Datei enthaelt Ziel, Szenario-Katalog, Leitplanken, Phasen, Agent-Plan,
Release-Ablauf und Abbruchregeln. Lies danach CLAUDE.md, config/README.md,
config/common/scripts/README.md und config/labdb/ komplett - seclab baut auf labdb auf.

Autonomie: Branch, Commits, Push, PR, Merge, Minor-Release mit Tag und Tag-Push.
Plan nach tasks/todo.md, keine Rueckmeldung noetig. Am Ende: Bericht, tasks/state-<datum>.md,
Strom-Zeile in ~/notes/state.md, falls vorhanden.
```

## Ziel

Ein Lab-Container mit einer **absichtlich unsicheren, dokumentierten Security-Baseline**: eine
Oracle-Datenbank mit Demo-Schemas und bekannten Schwachstellen, an der Security-Assessment- und
Remediation-Werkzeuge (DBSAT, Data Safe, eigene Checks, KI-gestuetzte Assessments) echte Findings
finden. Jede Schwachstelle ist katalogisiert, nachweisbar und einer Remediation-Klasse zugeordnet.

Erster externer Nutzer: ein Entwickler auf **macOS Apple Silicon mit Colima**, der Images vor einem
VPN-Wechsel lokal zieht und baut. Er kennt OraDBA nicht - Quick Start muss ohne Vorwissen
funktionieren.

## Leitplanken

- **Keine redundante Konfiguration.** seclab ist ein eigener Service (wie odbencprod/odbencdev),
  aber seine Setup-/Startup-Skripte sind **duenne Wrapper** im Stil von `config/labdb/setup/` und
  rufen `config/common/scripts/` auf. Was wiederverwendbar ist, gehoert parametrisiert nach
  `config/common/scripts/` (Namenskonvention und README dort beachten), nicht in den Service.
  Vor jedem neuen Skript pruefen, ob ein bestehendes Common-Skript es schon kann
  (`create_scott.sql`, `create_tvd_hr.sql`, `create_ts_users.sql`, `init_audit_config.sql`,
  `create_pdb.sql` ...).
- **Keine Regression** an bestehenden Services. labdb, cdbfree, odb* bleiben unveraendert im
  Verhalten. Aenderungen an Common-Skripten nur rueckwaertskompatibel.
- **Repo ist public (GitHub).** Keine Namen von Firmen, Kunden, Plattformen oder Personen, keine
  internen IPs, keine Hinweise auf den Anlass. Formulierung neutral: "security assessment and
  remediation testing".
- **Unsicher nur in seclab** und dort laut markiert: README-Warnung, Kopfkommentar in jedem
  Schwachstellen-Skript ("INTENTIONALLY INSECURE - lab use only").
- **Ports nur auf localhost binden** (`127.0.0.1:${SECLAB_LISTENER_PORT}:1521`) - eine absichtlich
  unsichere DB darf nicht am LAN haengen. Naechste freie Ports: Listener 1534, OEM Express 5512
  (in .env.example pruefen).
- **Keine Passwoerter im Code.** Alles ueber .env / .env.example (Platzhalter), wie bei den
  anderen Services. Schwache Passwoerter, wenn ein Szenario sie braucht, kommen ebenfalls aus .env.
- **DBSAT wird nicht mitgeliefert** (Oracle-Lizenz). Nur Skript + Anleitung.
- **Fakten vor Annahmen.** Jedes Szenario wird auf der tatsaechlichen DB-Version im Container
  nachgewiesen. Laesst sich ein Szenario auf 26ai nicht herstellen (z.B. weil ein Wert
  desupported ist), wird es **nicht** erzwungen, sondern im Katalog als "not reproducible on
  <version>" mit Fehlermeldung dokumentiert. Keine erfundenen DBSAT-Finding-IDs oder
  CIS-Nummern - nur Werte aus einem echten DBSAT-Lauf oder mit Quelle, sonst "to be confirmed".
- **Repo-Regeln** aus CLAUDE.md, tasks/lessons.md und den globalen Regeln gelten: SQL-Header,
  `WHENEVER SQLERROR EXIT`, Logging-Wrapper, `set -euo pipefail`, Pipe-Status-Falle (lessons.md),
  Idempotenz mit Aufraeumen davor, markdownlint, kein Skip ohne Ausgabe.

## Szenario-Katalog (Startpunkt, auf der echten Version verifizieren)

<!-- markdownlint-disable MD013 MD060 -->
| ID | Schwachstelle | Remediation-Klasse | Zweck in der Demo |
| --- | --- | --- | --- |
| S01 | Custom Grants an PUBLIC (SELECT auf Demo-Tabelle, EXECUTE auf eigenem Package) | 1 - Einzel-Change | Skript mit Rollback |
| S02 | Applikationsprozedur nutzt `UTL_FILE` ueber den PUBLIC-Grant | 2 - mit Pre-Check | Revoke wuerde sie brechen; Pre-Check findet die Abhaengigkeit |
| S03 | Niedrige `SQLNET.ALLOWED_LOGON_VERSION_SERVER` + Account mit altem Verifier | 2 - mit Pre-Check | Reihenfolge: Verifier zuerst, dann Logon-Version |
| S04 | Profil ohne Limits (keine Lockout-, Lifetime-, Verify-Function-Regeln) fuer Personen-Accounts; Service-Account mit Profil, dessen Haertung ihn ablaufen liesse | 2 - mit Pre-Check | Service-Account braucht eigenes Profil |
| S05 | Ueberprivilegierung: App-Owner mit DBA-Rolle, Entwickler mit `SELECT ANY TABLE`, Grant `WITH ADMIN OPTION` | 3 - Massnahmenpaket (Least Privilege) | Rollenmodell statt Massen-Revoke |
| S06 | Offene, nie benutzte Custom-Accounts | 1 - Einzel-Change | Lock, nicht Drop |
| S07 | Unified Audit unvollstaendig: Logon-Policy deaktiviert, keine Policy auf sensitive Tabellen, kein Trail-Management/Purge-Job | 3 - Massnahmenpaket (Audit-Konzept) | Kein Skript, Playbook |
| S08 | Sensitive Demo-Daten (HR/SCOTT) unverschluesselt, kein Keystore | 3 - Massnahmenpaket (Key Management / TDE) | Kein Skript, Playbook |
| S09 | Keine Netzwerkverschluesselung erzwungen | 3 - Massnahmenpaket | Client-Kompatibilitaet |
| S10 | Ein sicherheitsrelevanter **statischer** Parameter unsicher gesetzt (z.B. `SQL92_SECURITY`, Default und Statik verifizieren) | 1 mit Restart | Run-Plan muss Restart ausweisen |
<!-- markdownlint-restore -->

Ergaenzen erlaubt, wenn ein typisches DBSAT-/CIS-Finding fehlt und billig herzustellen ist.
Nichts einbauen, was Container oder Host gefaehrdet (keine OS-Schwachstellen, kein offenes
Netzwerk). Mindestens S01-S03, S06, S07 muessen am Ende nachweisbar stehen - das ist die
Drei-Klassen-Demo (S01, S03, S07).

## Liefergegenstaende

- `docker-compose.yml`: Service `seclab` (Profil `seclab`), Muster wie labdb, Ports auf 127.0.0.1
- `config/seclab/setup/` und `config/seclab/startup/` als duenne Wrapper; neue wiederverwendbare
  Skripte in `config/common/scripts/` mit README-Eintrag
- `config/seclab/README.md`: Zweck, Warnung, Szenario-Uebersicht, Verweis auf doc
- **Verifikationsskript** (ein Lauf, read-only): weist jedes Szenario per SQL nach, Ausgabe pro
  ID `PRESENT` / `ABSENT` / `NOT REPRODUCIBLE`, Exit-Code != 0 bei ABSENT
- **DBSAT optional**: Liegt ein DBSAT-ZIP im Common-Data-Verzeichnis (Pfad festlegen und
  dokumentieren), Collect + Report im Container, JSON nach `data/seclab/dbsat/`. Fehlt es:
  deutliche Meldung mit Download-Quelle und dem Kommando zum Nachholen - kein stiller Skip.
  DBSAT-User mit den dokumentierten Mindestrechten, nicht SYS. Voraussetzungen (Java, Python im
  Image) pruefen und dokumentieren.
- `doc/seclab.md`: Szenario-Katalog final - je ID: Schwachstelle, wie hergestellt, Nachweis-Query,
  Remediation-Klasse, Pre-Check (Klasse 2), Hinweis Remediation / Playbook-Thema (Klasse 3),
  erwartetes DBSAT-Finding (aus echtem Lauf oder "to be confirmed"). Ohne Remediation-SQL fuer
  Klasse 3.
- `doc/seclab-runbook.md`: Quick Start fuer Nutzer ohne Vorwissen - **macOS Apple Silicon mit
  Colima** als Hauptpfad (Colima-VM-Groesse, Architektur, Mount-Typ, Docker-Compose-Plugin),
  Docker Desktop / Podman als Varianten; Image vorab ziehen und bauen (Offline-/VPN-Fall),
  Start, Logs, Verifikation, Connect-Strings (sqlplus, SQLcl, JDBC/Python-Beispiel), DBSAT-Lauf,
  Reset, Remediation-Testschleife (Klasse-1-Fix anwenden -> Verifikation/DBSAT erneut ->
  Finding weg), Troubleshooting.
- Updates: README.md (Service-Tabelle), CLAUDE.md (Service-Tabelle), config/README.md,
  `.env.example`, Makefile-Targets nach bestehendem Muster (`up-seclab`, `down-seclab`,
  `logs-seclab`, `bash-seclab`, `sql-seclab`, `reset-seclab`, plus `verify-seclab`,
  `dbsat-seclab`), CHANGELOG `[Unreleased]` -> Release-Eintrag.

## Fallen

- **Colima auf Apple Silicon:** Default-VM ist zu klein fuer Oracle Free - Mindestgroesse ermitteln
  und dokumentieren (`colima start --cpu ... --memory ... --arch aarch64`). Bind-Mounts unter
  Colima (virtiofs/sshfs): UID des `oracle`-Users (54321) muss in `data/seclab/` schreiben
  koennen - testen oder mindestens nachvollziehbar dokumentieren. Lokal laeuft Docker Desktop;
  was nur unter Colima pruefbar ist, im Bericht als "nicht lokal verifiziert" markieren.
- **Image:** `build/Dockerfile` hat als Default `database/free:23.9.0.0`, CLAUDE.md spricht von
  26ai. Tatsaechlichen Stand und arm64-Verfuegbarkeit pruefen und berichten; nicht nebenbei
  umbauen, wenn es andere Services betrifft. Klaeren, ob seclab auch mit dem unveraenderten
  Oracle-Image laeuft oder `make build` Pflicht ist - im Runbook eindeutig sagen.
- **sqlnet.ora / TNS_ADMIN:** S03 und S09 brauchen Einstellungen in der sqlnet.ora des Services
  (`/opt/oracle/network/admin` -> `dbconfig/FREE`). Nur fuer seclab, persistent, idempotent.
- **Verifier-Szenario (S03):** Reihenfolge entscheidet - Logon-Version setzen, dann Passwort
  setzen, dann `PASSWORD_VERSIONS` pruefen. Auf 26ai kann der alte Wert abgelehnt werden ->
  dokumentieren, nicht umgehen.
- **Unified Audit:** Das Image laeuft ggf. schon in Pure Mode; seclab soll ihn nicht ausschalten,
  sondern die Policy-Lage unvollstaendig machen. labdb aktiviert Policies - seclab ruft
  `enable_audit_policies.sql` gerade nicht oder nur teilweise auf.
- **Idempotenz:** Setup laeuft einmal, Startup bei jedem Start. Zweiter Start und
  `make reset-seclab` + Neustart muessen sauber durchlaufen (lessons.md 2026-09-05).
- **Pipe-Status** in Shell-Wrappern um sqlplus (lessons.md).

## Phasen und Agent-Plan

1. **Bestand (parallel, je ein Agent, `Explore` mit Haiku):** (a) Common-Skripte: Funktionen,
   Parameter, Namenskonvention; (b) Compose/Makefile/.env-Muster der bestehenden Services;
   (c) Doku-Stil und Struktur in `doc/`. Ergebnisse knapp, keine Datei-Dumps.
2. **Plan** nach `tasks/todo.md`: finale Szenarioliste, neue vs. wiederverwendete Common-Skripte,
   Dateiliste. Keine Rueckfrage.
3. **Umsetzung** sequenziell im Hauptkontext (geteilte Dateien: compose, Makefile, README).
   Branch `feat/seclab`.
4. **Lauf und Nachweis:** `make build` falls noetig, `make up-seclab`, Setup-Logs auf ORA-/SP2-
   Fehler pruefen, Verifikationsskript, DBSAT-Lauf falls ein ZIP vorhanden ist (sonst Meldung
   pruefen), zweiter Start, Reset + Neustart. Ergebnisse in `doc/seclab.md` nachtragen.
5. **Review (parallel):** `review-oracle-verify` (SQL, Audit-Policies, Privilegien),
   `scan-bash-static` (Shell), `scan-markdown`, `scan-secrets` (Pflicht vor jedem Push - public).
   Befunde beheben. Nach jedem Agent mit Schreibrechten `git diff` auf die genannten Dateien.
6. **Release** (siehe unten).

## Git und Release

- Ausgangslage: `main` hat **fremde uncommittete Aenderungen** (`.gitignore`) und untracked
  Artefakte (`artefacts/`, `data/xchange/`, `.claude/settings.json.bak`,
  `tasks/state-2026-09-22.md`). Diese Prompt-Datei `tasks/prompt-seclab.md` wird mit dem Feature
  committet. **Nicht anfassen, nicht
  committen, nicht verwerfen.** Nie `git add .`/`-A` - nur eigene Pfade explizit stagen. Vor dem
  Branch-Wechsel `git status --short` lesen.
- Conventional Commits (`feat(seclab): ...`, `docs(seclab): ...`), kein Co-Authored-By.
- `make lint` muss gruen sein.
- PR via `gh` nach `main`, Merge nach gruenem Lint, Verifikation und Secret-Scan.
- Release auf `main`: `make version-bump-minor` (-> 1.4.0, CHANGELOG-Eintrag pruefen), `make tag`,
  dann `git push origin main` **und** `git push origin v1.4.0`.
  Nachweis: `git ls-remote --tags origin` enthaelt v1.4.0.

## Abbruchregeln

- Build oder Container-Start scheitert, und die Ursache liegt nicht im eigenen Code: Zustand
  sichern (Logs, `docker ps`, `colima status`/Docker-Info), berichten, **kein Merge, kein Release**.
- Ein Szenario ist nicht herstellbar: dokumentieren und weiter (kein Abbruch).
- Eine Aenderung wuerde einen bestehenden Service im Verhalten aendern: nicht machen, im Bericht
  als Vorschlag.
- Secret-Scan meldet etwas: nicht pushen, berichten.

## Bericht am Ende

- Szenario-Tabelle: ID, PRESENT / NOT REPRODUCIBLE, Nachweis, DBSAT-Finding (falls Lauf)
- Neue und geaenderte Common-Skripte, mit Begruendung, warum nicht redundant
- Lauf-Ergebnisse: Build, erster Start, zweiter Start, Reset - Dauer und Fehler
- Was nur dokumentiert, nicht verifiziert ist (Colima)
- Release: PR-Link, Tag, `ls-remote`-Nachweis
- Offene Punkte und Vorschlaege
