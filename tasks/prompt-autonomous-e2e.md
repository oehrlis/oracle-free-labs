# Prompt - autonomer E2E-Lauf des TDE-Verifikationstests

Selbsttragend. In einer frischen Session einfuegen; setzt kein Wissen aus einer
vorherigen Sitzung voraus.

## Der Prompt

```text
Fahre den TDE-Verifikationstest im Repo /Users/stefan.oehrli/Repos/own/oehrlis/oracle-free-labs
autonom durch und liefere am Ende einen Bericht. Arbeite ohne Rueckfragen, solange nichts
Unerwartetes passiert.

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
1. Lauf-Log aus data/xchange/evidence/run_<ts>.log nach artefacts/ kopieren - es liegt sonst
   in data/xchange und wird vom naechsten --delete geloescht
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

## Sollwerte zur Selbstbeurteilung

Diese Tabelle gehoert in den Prompt oder danebengelegt. Ohne sie kann ein autonomer
Lauf einen erwarteten Fehler nicht von einer Regression unterscheiden.

<!-- markdownlint-disable MD013 MD060 -->

| Schritt | Weg | Sollergebnis | Fehler, die dazugehoeren |
|---|---|---|---|
| 00 | Reset | beide Services healthy | `ORA-01646`, `ORA-00959` beim Aufraeumen auf frischem Lab |
| 10 | Baseline | 5000 Zeilen, 313 Marker-Bloecke | - |
| 15 | RMAN-Backup | alle Pieces unter `/opt/oracle/xchange/backup` | - |
| 20 | A, normaler RESTORE | **313 identisch / 0**, TEK und MASTERKEYID unveraendert | `ORA-28365` beim Wallet-Transport ist erwartet |
| 30 | B2, AS ENCRYPTED ohne Prod-MEK | **bricht ab** | `ORA-19870` **plus** `ORA-28374` - das ist das Messergebnis |
| 35 | B1, AS ENCRYPTED mit Prod-MEK | **bricht ab** | `ORA-00600 [kcbtse_encdec_tbsblk_1]` |
| 40 | C, DUPLICATE AS ENCRYPTED | **313 identisch / 0**, neue DBID | - |
| 50 | D, DECRYPTED + SET KEY + ENCRYPT | **313 identisch / 0**, MEK neu | - |
| 60 | F, Discard-Pfad | **0 identisch / 313**, neues Material | `ORA-28304` auf Undo, wenn der Undo-Tausch fehlt |
| 61 | PDB-Testbed | `PDBCLONE_READY` gesetzt | - |
| 62 | P1, lokaler Klon | **0 identisch / 313**, MASTERKEYID unveraendert | `ORA-46697` ohne Keystore-Passwort |
| 63 | P2, Archiv-Transport | **313 identisch / 0**, gewrappter Schluessel unveraendert | - |
| 64 | P3, Unplug ohne Keys | **scheitert**, kein Archiv entsteht | `ORA-46680` - das ist das Ergebnis |
| 65 | P4, Remote-Klon | **0 identisch / 313** | - |
| 66 | P7, ORIGIN | `ORIGIN = LOCAL` im Ziel trotz Transport | - |
| 67 | P8, KEY_VERSION | unveraendert, **kein** Reset auf 0 | - |
| 68 | P5, MEK-Rotation | read-only bleibt am Quell-MEK, read-write wird neu gewrappt, Chiffrat beide unveraendert | - |
| 69 | P6, ONLINE REKEY in der PDB | **0 identisch / 313**, `KEY_VERSION` steigt | - |
| 70 | G, ONLINE REKEY | **0 identisch / 313**, `KEY_VERSION` 1 auf 2 | - |
| 80 | Positivkontrolle | **0 identisch / 313** - die Methode erkennt einen Wechsel | - |
| 90 | Entzugstest | verschluesselte Daten unlesbar | `ORA-28374`. Ob die DB gar nicht oeffnet oder nur die Daten unlesbar sind, haengt am Vorzustand - beides ist gueltig, siehe unten |

<!-- markdownlint-restore -->

## Zwei Fallen, die einen autonomen Lauf falsch urteilen lassen

**Der Entzugstest hat zwei gueltige Ausgaenge.** Nach Variante G oeffnet die Zieldatenbank
nicht und bleibt `MOUNTED` mit `ORA-28374`. Nach Variante A oeffnet sie, und nur die
verschluesselten Daten sind unlesbar - gemessen 2026-09-10. Beides belegt dieselbe
Abhaengigkeit; nur der Blast Radius unterscheidet sich. Ein Lauf, der ausschliesslich
"oeffnet nicht" als Erfolg akzeptiert, meldet einen Fehlschlag, wo keiner ist.

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
