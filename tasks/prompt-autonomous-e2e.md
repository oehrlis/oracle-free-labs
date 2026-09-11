# Prompt - autonomer E2E-Lauf des TDE-Verifikationstests

Selbsttragend. Den Codeblock unter "Der Prompt" in eine frische Session einfuegen -
er weist die Session an, **diese Datei zuerst vollstaendig zu lesen**, weil die
Sollwerte und die Fallen hier stehen und nicht im Block. Setzt kein Wissen aus einer
vorherigen Sitzung voraus.

## Der Prompt

```text
Fahre den TDE-Verifikationstest im Repo /Users/stefan.oehrli/Repos/own/oehrlis/oracle-free-labs
autonom durch und liefere am Ende einen Bericht. Arbeite ohne Rueckfragen, solange nichts
Unerwartetes passiert.

LIES ZUERST tasks/prompt-autonomous-e2e.md in diesem Repo, vollstaendig. Diese Nachricht
ist nur der Einstieg; die Datei enthaelt den Werkzeugstand, die Sollwerttabelle ueber alle
21 Schritte und drei Fallen, die zu Falschurteilen fuehren. Ohne die Sollwerte kannst du
einen erwarteten Fehler nicht von einer Regression unterscheiden - und in diesem Test sind
mehrere Fehler das Messergebnis.

VORBEDINGUNGEN pruefen, bevor du startest:
- Docker Desktop laeuft
- kein anderer run_all.sh-Prozess aktiv (pgrep -f run_all.sh)
- mindestens 30 GB frei auf der Platte (df -h .)
- .env vorhanden mit ODBENCPROD_LISTENER_PORT und ODBENCDEV_LISTENER_PORT
Wenn eine Vorbedingung fehlt: melden und stoppen, nicht improvisieren.

STARTEN:
  nohup ./scripts/tde-verify/run_all.sh --delete --yes > /tmp/e2e_run.out 2>&1 &
Der Lauf dauert 25 bis 40 Minuten und faehrt 21 Schritte.

UEBERWACHEN, nicht pollen: setz einen Monitor auf /tmp/e2e_run.out mit einem Filter,
der Fortschritt UND Fehlschlaege erfasst, zum Beispiel
  tail -f /tmp/e2e_run.out | grep -E --line-buffered '^  STEP [0-9]+:|VERDICT:|FAILED|GATE |Traceback|Killed'
Erwartete ORA-Fehler nicht als Problem behandeln - siehe Sollwerte unten.

ABBRUCHREGEL: wenn ein Schritt FAIL oder GATE meldet, den Lauf NICHT neu starten.
Zustand einfrieren, die letzten 80 Zeilen des Logs sichern, den Zustand beider Container
festhalten (docker ps, v$database, v$encryption_wallet, v$pdbs) und berichten. Ein blinder
Neuversuch zerstoert die Fehlerursache.

NACH DEM LAUF, in dieser Reihenfolge:
1. Der Lauf-Log liegt seit run_all.sh 0.3.0 direkt in artefacts/ - kein Kopieren mehr.
   Vor dem Versionieren den Secret-Check aus artefacts/README.md fahren
2. Protokoll neu erzeugen:
     ./scripts/tde-verify/make_protocol.sh --log artefacts/<log> --out doc/tde-e2e-protokoll.md
3. Die Messwerte gegen tasks/e2e-facts.md vergleichen und JEDE Abweichung nennen.
   e2e-facts.md nicht aendern - Abweichungen berichten, nicht wegschreiben.
4. Nichts committen. Kundenartefakte liegen ausserhalb dieses Repos und werden
   nicht angefasst - dieser Lauf schreibt ausschliesslich in artefacts/, doc/ und
   data/xchange/.

BERICHT am Ende, kurz:
- Ergebnistabelle: Schritt, PASS/FAIL, Dauer
- je Variante der Kernmesswert (Marker-Bloecke identisch/abweichend, MASTERKEYID, gewrappter TEK)
- jede Abweichung von den Sollwerten unten, mit Belegzeile aus dem Log
- alles, was auffiel und in keiner Erwartung steht
```

## Werkzeugstand, Stand 2026-09-11

Zwei Skripte wurden nach einem Lauf mit stillen Fehlern repariert. Der naechste
Lauf prueft diese Reparaturen mit, also gehoert der Sollzustand hierher.

| Skript | Version | Was sich geaendert hat |
|---|---|---|
| `run_all.sh` | 0.3.0 | Schritt-Banner, Ergebnistabelle und Schlusszeile gehen jetzt durch einen `emit`-Filter in **beide** Senken. Der Evidence-Log enthaelt damit selbst die 21 `STEP nn:`-Header und die Ergebnistabelle. Ein **Dry-Run schreibt keinen Log mehr** und kuendigt auch keinen an |
| `make_protocol.sh` | 0.3.0 | Ein Log ohne Schritt-Header **und** ohne Ergebnistabelle ist die falsche Eingabedatei, nicht ein abgebrochener Lauf: Exit 2, Ursache und Fix benannt, **nichts geschrieben**. Ausgabe laeuft ueber eine Temp-Datei und wird erst bei Erfolg an ihren Platz bewegt |

Daraus folgen zwei pruefbare Sollwerte:

- **Das Protokoll muss sich direkt aus dem Evidence-Log erzeugen lassen**, ohne den
  stdout-Log. Wenn `make_protocol.sh --log artefacts/run_<ts>.log` mit Exit 2
  abbricht oder ein Teilprotokoll schreibt, ist der `emit`-Filter nicht wirksam
  geworden - das ist ein Fund, kein Bedienfehler.
- **Nach einem Dry-Run darf kein `run_<ts>.log` existieren.** Falls doch, ist der
  `DRY_RUN`-Guard nicht wirksam. Empirisch bestaetigt am 2026-09-11.
- **Das erzeugte Protokoll darf keinen Unvollstaendigkeits-Hinweis tragen.**
  `make_protocol.sh` 0.3.0 vergleicht Ergebnistabelle und Detailabschnitte und
  schreibt eine Warnung auf die Protokollseite, wenn sie sich widersprechen. Steht
  dort "**Unvollstaendig:** fuer Schritt nn fehlt der Detailabschnitt", dann ist im
  Log etwas verloren gegangen - melden, nicht uebergehen.

## Sollwerte zur Selbstbeurteilung

Diese Tabelle gehoert in den Prompt oder danebengelegt. Ohne sie kann ein autonomer
Lauf einen erwarteten Fehler nicht von einer Regression unterscheiden.

<!-- markdownlint-disable MD013 MD060 -->

| Schritt | Weg | Sollergebnis | Fehler, die dazugehoeren |
|---|---|---|---|
| 00 | Reset | beide Services healthy | `ORA-01646`, `ORA-00959` beim Aufraeumen auf frischem Lab |
| 10 | Baseline | 5000 Zeilen, 313 Marker-Bloecke | - |
| 15 | RMAN-Backup | alle Pieces unter `/opt/oracle/xchange/backup` | - |
| 20 | A, normaler RESTORE | **313 identisch / 0**, TEK und MASTERKEYID unveraendert | keine. `ORA-28365` **soll nicht** auftreten: `15_backup.sh` stagt bewusst nur `ewallet.p12` und nicht `cwallet.sso`, der Harness stellt die Bedingung also nie her. Nur der manuelle Runbook-Weg laeuft hinein |
| 30 | B2, AS ENCRYPTED ohne Prod-MEK | **bricht ab** | `ORA-19870` **plus** `ORA-28374` - das ist das Messergebnis |
| 35 | B1, AS ENCRYPTED mit Prod-MEK | **bricht ab** | `ORA-00600 [kcbtse_encdec_tbsblk_1]` |
| 40 | C, DUPLICATE AS ENCRYPTED | **313 identisch / 0**, neue DBID | - |
| 50 | D, DECRYPTED + SET KEY + ENCRYPT | **313 identisch / 0**, MEK neu | - |
| 60 | F, Discard-Pfad | **0 identisch / 313**, neues Material | `ORA-28304` auf Undo, wenn der Undo-Tausch fehlt |
| 61 | PDB-Testbed | `PDBCLONE_READY` gesetzt | - |
| 62 | P1, lokaler Klon | **0 identisch / 313**, MASTERKEYID unveraendert | `ORA-46697` ohne Keystore-Passwort |
| 63 | P2, Archiv-Transport | **313 identisch / 0**, gewrappter Schluessel unveraendert | - |
| 64 | P3, Unplug ohne Keys | **scheitert**, kein Archiv entsteht | `ORA-46680` - das ist das Ergebnis |
| 65 | P4, Remote-Klon | **0 identisch / 313** | `ORA-46655` "no valid keys in the file" beim Key-Import - **erwartet**, siehe unten. Der Schritt laeuft danach korrekt durch |
| 66 | P7, ORIGIN | `ORIGIN = LOCAL` im Ziel trotz Transport | - |
| 67 | P8, KEY_VERSION | unveraendert, **kein** Reset auf 0 | - |
| 68 | P5, MEK-Rotation | read-only bleibt am Quell-MEK, read-write wird neu gewrappt, Chiffrat beide unveraendert | - |
| 69 | P6, ONLINE REKEY in der PDB | **0 identisch / 313**, `KEY_VERSION` steigt | - |
| 70 | G, ONLINE REKEY | **0 identisch / 313**, `KEY_VERSION` 1 auf 2 | - |
| 80 | Positivkontrolle | **0 identisch / 313** - die Methode erkennt einen Wechsel | - |
| 90 | Entzugstest | verschluesselte Daten unlesbar | `ORA-28374`. Ob die DB gar nicht oeffnet oder nur die Daten unlesbar sind, haengt am Vorzustand - beides ist gueltig, siehe unten |

<!-- markdownlint-restore -->

## Drei Fallen, die einen autonomen Lauf falsch urteilen lassen

**Der Entzugstest hat zwei gueltige Ausgaenge.** Nach Variante G oeffnet die Zieldatenbank
nicht und bleibt `MOUNTED` mit `ORA-28374`. Nach Variante A oeffnet sie, und nur die
verschluesselten Daten sind unlesbar - gemessen 2026-09-10. Beides belegt dieselbe
Abhaengigkeit; nur der Blast Radius unterscheidet sich. Ein Lauf, der ausschliesslich
"oeffnet nicht" als Erfolg akzeptiert, meldet einen Fehlschlag, wo keiner ist.

**`ORA-46655` in Schritt 65 ist ein Sollwert, keine Stoerung.** Der Remote-Klon
bringt den Master Key der Quelle selbst ins Ziel-Keystore mit, ohne `EXPORT KEYS`
und ohne `IMPORT KEYS`, und meldet dort `ORIGIN = LOCAL`. Der anschliessende
explizite Key-Import findet deshalb nichts mehr zu importieren und quittiert mit
"no valid keys in the file from which keys are to be imported". Gemessen am
2026-09-10 von Hand an den Hex-Werten, am 2026-09-11 in der Suite bestaetigt.
Belege in `tasks/e2e-facts.md`. Wer das als Fehlschlag meldet, meldet den
zentralen Befund des Auftrags als Stoerung.

**Die Gesamtblockzahlen schwanken, die Marker-Blockzahl nicht.** Bei Variante A waren es
im dokumentierten Lauf 1269 identisch / 1292 abweichend, am 2026-09-10 1271 / 1290. Die
Differenz liegt in nie benutzten Bloecken und ist bedeutungslos. Beurteilt wird
ausschliesslich `313 identisch / 0` gegen `0 identisch / 313`.

## Wenn nur ein Teil gefahren werden soll

`run_all.sh` kann Teilmengen und schreibt trotzdem ein Log:

```bash
./scripts/tde-verify/run_all.sh --only 62 --yes            # nur P1
./scripts/tde-verify/run_all.sh --from 61 --to 69 --yes     # nur die PDB-Reihe
./scripts/tde-verify/run_all.sh --from 20 --to 70 --yes     # nur die RMAN-Wege
```

Die Abhaengigkeiten stehen in `doc/tde-restore-runbook.md`, Abschnitt "Einstiegspunkte -
was brauche ich fuer welchen Test". Kurz: die PDB-Reihe braucht **kein** Backup, nur
Schritt 00 und 61. Die Schritte 66 bis 69 brauchen ein Ziel aus 63 oder 65.
