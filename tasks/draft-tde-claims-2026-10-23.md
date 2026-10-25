# Entwurf: Aussagen in doc/tde-clone-independence.md nach den Messungen vom 2026-10-24

Status: in doc/tde-clone-independence.md uebernommen, PR <tbd>, 2026-10-25

Urspruenglicher Status: **Entwurf, nicht eingearbeitet.** `doc/tde-clone-independence.md`
ist kundenseitig und wurde nicht geaendert. Jeder Vorschlag nennt den alten Text, den neuen Text und den
Beleg. Belege verweisen auf `tasks/e2e-facts.md`, Abschnitt "Messwerte der Einzellaeufe vom
2026-10-24", und von dort auf `artefacts/run_20261024_*.log`. Die Schritte 30, 35, 45 und
72 liefen am 2026-10-25 mit der finalen Skriptrevision erneut (`artefacts/run_20261025_*.log`),
alle Verdicts unveraendert `PASS`; beide Laeufe sind zitiert. Keine Schluessel-ID aus diesen
Laeufen gehoert in das Kundendokument; zitiert werden nur Relationen, Blockzahlen und
Fehlercodes.

## 1. Stufe-3-Zeile der Tabelle - ONLINE REKEY braucht SET KEY in jedem Container

Alt (Tabelle "Stufenmodell", Zeile Stufe 3):

> `| 3 | eigener MEK, eigener TEK, kein Quell-MEK | P1, P4, ONLINE REKEY (G), F | ...`

Neu:

> `| 3 | eigener MEK, eigener TEK, kein Quell-MEK | P1, P4, ONLINE REKEY plus SET KEY in jedem
> Container plus ONLINE REKEY auf SYSTEM/SYSAUX/UNDO, F | ...` - Spalte "Im Lab gemessen":
> `ja, inkl. Entzugstest; Beitrag der SYSTEM/SYSAUX/UNDO-Probes nicht isoliert`

Beleg: Schritt 72 fuehrte das ganze Rezept aus - `SET KEY` in `CDB$ROOT` und in der PDB,
`ONLINE REKEY` von `USERS` **und** `ONLINE REKEY` auf die unverschluesselten `SYSTEM`,
`SYSAUX`, `UNDOTBS1` in beiden Containern (`run_20261024_095047.log:428-438`, `:454-464`;
`run_20261025_064340.log:414-450`). Die Unabhaengigkeit stuetzt sich auf den Entzug: ohne
Quell-MEK oeffnet das Ziel `READ WRITE` und liest den Canary (`run_20261024_095047.log:849`,
`:913`, `:928`; `run_20261025_064340.log:833`, `:897`, `:910`), 0 von 313 Canary-Bloecken
identisch zur Baseline (`:763` bzw. `:745`). Variante G allein (nur `ONLINE REKEY`, MEK
unveraendert) blieb im Entzugstest `MOUNTED` mit `ORA-28374` (Laeufe 2026-09-06 und
2026-09-11, Abschnitte "Kontrollen" in `tasks/e2e-facts.md`) - mit offenem Vorbehalt, siehe
Abschnitt 3. "ONLINE REKEY (G)" als Stufe-3-Weg ohne den MEK-Wechsel ist damit nicht gedeckt.

## 2. Abschnitt "ONLINE REKEY - der dokumentierte Weg nach einem Restore"

Alt:

> `ALTER TABLESPACE <name> ENCRYPTION ONLINE REKEY` ist seit Oracle Database 12.2.0.1
> dokumentiert und erzeugt nachweislich neuen TEK-Klartext. Kein Hidden Parameter, kein
> Datenfenster im Klartext.

Neu (Satz anfuegen):

> Neuer TEK allein trennt nicht: er wird unter dem aktiven MEK eingewickelt, nach einem
> Restore also unter dem Prod-MEK. Im Lab getrennt hat diese Folge: Read-only-Tablespaces
> `READ WRITE`, `ADMINISTER KEY MANAGEMENT SET KEY` in `CDB$ROOT` und in jeder PDB - einzeln,
> nicht `CONTAINER=ALL` -, dann `ONLINE REKEY` der verschluesselten Tablespaces und
> `ONLINE REKEY` auf `SYSTEM`, `SYSAUX` und `UNDO`. So durchgefuehrt oeffnet das Ziel nach
> dem Entfernen aller Prod-MEKs und liest seine Daten. Ob die Probes auf `SYSTEM`/`SYSAUX`/
> `UNDO` dazu beitragen, ist nicht isoliert.

Beleg fuer die Unabhaengigkeit: der Entzug, `run_20261024_095047.log:849`, `:913`, `:928`
und `run_20261025_064340.log:833`, `:897`, `:910`. Die `v$`-Zeilen (`:377`, `:404`, `:406`,
`:575` im Lauf vom 2026-10-24) zeigen nur, worauf die Schluessel zeigen, nicht dass das Ziel
ohne Quell-MEK auskommt. Beleg fuer "einzeln, nicht `CONTAINER=ALL`": `ORA-46663` bei
`CONTAINER=ALL` in Variante D (`scripts/tde-verify/tests/50_variant_d.sh:301`, Notiz zur
Messung). Beleg fuer "`READ WRITE` noetig": P5 in `tasks/e2e-facts.md` (Tabellen-Zeilen "P5
MEK-Rotation, Tablespace READ ONLY": read-only bleibt an den Quellschluessel gebunden).

## 3. Abschnitt "Entzugstest - was ohne den Quell-MEK passiert"

Alt:

> Der Entzugstest wurde nach dem `ONLINE REKEY` gemessen und faellt deutlicher aus, als die
> Formulierung "ein Tablespace ist nicht mehr lesbar" nahelegt: nach dem Entfernen des
> Quell-MEK **oeffnet die Zieldatenbank nicht mehr**.

Neu:

> Der Entzugstest wurde nach einem `ONLINE REKEY` **ohne MEK-Wechsel** gemessen: nach dem
> Entfernen des Quell-MEK **oeffnete die Zieldatenbank nicht mehr** (`MOUNTED`,
> `ORA-28374`). Vorbehalt: dieser Befund ist nicht nachgemessen und moeglicherweise derselbe
> Open-/Saved-State-Mechanismus wie unten - ob die CDB mit geschlossener PDB oeffnen und nur
> deren Daten verlieren wuerde, ist offen. Mit `SET KEY` in jedem Container vor dem Rekey
> besteht dasselbe Ziel den Entzugstest (siehe Stufe 3). In einer CDB mit mehreren PDBs wurde
> beobachtet: war die abhaengige PDB beim Shutdown offen, blieb die CDB auf `MOUNTED`; wurde
> sie vorher geschlossen, oeffnete die CDB, und nur die Daten dieser PDB scheiterten. Dass
> die offene PDB die Ursache ist, ist eine Hypothese (nicht isoliert).

Beleg: Variante G wie unter 1; Schritt 72 wie unter 2. Symptom `MOUNTED`:
`run_20261024_090859.log:871`, `:878` und `run_20261024_092534.log:870`, `:877`. Die
Ursache stuetzt sich auf ein live gelesenes, nicht versioniertes Alert-Log und auf einen Lauf,
der `CLOSE IMMEDIATE` und `DISCARD STATE` gleichzeitig einfuehrte. Mit geschlossener PDB:
CDB `READ WRITE` `run_20261024_094125.log:890`, Auxiliary `ORA-01187` `:986`, Alert-Log
`ORA-28374` `:1008`; wiederholt `run_20261025_064027.log:839`, `:935`, `:957`.

## 4. Stufe 2 - Status unveraendert, Begruendung schaerfen

Alt (Tabelle, Spalte Variante / Gemessen): `kein Verfahren direkt gemessen` / `nein, abgeleitet`

Neu: Status bleibt "nicht als gelungen gemessen", aber mit einem **gemessenen Negativ-
Datenpunkt** statt "nicht gemessen". Stufe 2 (eigener MEK, **Prod-TEK**, Quell-MEK entfernt):
die Auxiliary-PDB in Schritt 45 ist genau dieser Fall - `SET KEY` in `CDB$ROOT` und in der
PDB, kein Rekey, der `USERS`-TEK danach unter dem Dev-MEK eingewickelt
(`run_20261024_094125.log:525-526`, `:663`; `run_20261025_064027.log:496-497`, `:612`). Nach
dem Entzug scheitert Datafile 20 mit `ORA-01187`, Alert-Log `ORA-28374`
(`run_20261024_094125.log:986`, `:1008`; `run_20261025_064027.log:935`, `:957`).
Einschraenkung: `USERS` war hier sehr wahrscheinlich `READ ONLY` (Baseline
`run_20261024_081906.log:643`, dasselbe restaurierte `USERS` in Schritt 72
`run_20261024_095047.log:307`); nach P5 bleibt ein read-only Tablespace an den
Quellschluessel gebunden. Der Datenpunkt zeigt also "nur `SET KEY` bei read-only `USERS`
reicht nicht", nicht "nur `SET KEY` reicht nie". Vorschlag fuer einen Zusatzsatz:

> Gemessen ist, dass `SET KEY` je Container ohne Rekey nicht genuegte: der Tablespace war
> danach unter dem neuen MEK gefuehrt, nach dem Entzug des Quell-MEK aber nicht lesbar - bei
> einem Tablespace, der sehr wahrscheinlich `READ ONLY` war. Ein `READ WRITE`-Tablespace mit
> nur `SET KEY` ist nicht gemessen.

## 5. PDB-Klon - Auxiliary-Kette (ZDLRA-Szenario)

Neu (Absatz im Abschnitt "PDB-Klon - der praktisch empfohlene Weg"):

> Auch ein PDB-Klon aus einer per RMAN restaurierten Auxiliary-CDB erhaelt neues
> Tablespace-Schluesselmaterial, nachdem in der Auxiliary `SET KEY` in `CDB$ROOT` und
> in der Quell-PDB lief: 0 von 313 Canary-Bloecken identisch, Klon-TEK unter dem neuen MEK.
> Nach dem Entfernen des Quell-MEK liest der Klon seine Daten; die Auxiliary scheitert mit
> `ORA-01187`, Ursache laut Alert-Log `ORA-28374`. Gemessen mit Auxiliary und Klon in
> derselben CDB; getrennte CDBs mit getrennten Keystores sind nicht gemessen.

Beleg: `run_20261024_094125.log:793`, `:795`, `:950`, `:986`, `:1008`, `:1027`; wiederholt
`run_20261025_064027.log:741`, `:899`, `:935`, `:957`, `:972`.

## 6. "Was nicht funktioniert" - B1

Alt:

> Die unverschluesselten CDB-Datafiles werden konvertiert. Sobald RMAN das bereits
> verschluesselte Datafile erreicht, bricht der Lauf mit
> `ORA-00600 [kcbtse_encdec_tbsblk_1]` ab.

Neu:

> Die unverschluesselten CDB-Datafiles werden restauriert. Sobald RMAN das bereits
> verschluesselte Datafile erreicht, bricht der Lauf mit
> `ORA-00600 [kcbtse_encdec_tbsblk_1]` ab.

Begruendung: der Abbruch ist jetzt geloggt (`run_20261024_082444.log:227-228`, Verdict
`:244`; wiederholt `run_20261025_063809.log:227-228`, `:244`). "Konvertiert" ist nicht belegt:
das CDB-Set lief in 3 Sekunden durch (`:210`), und
weil der Restore danach abbricht, laesst sich nicht pruefen, ob `AS ENCRYPTED` diese Dateien
tatsaechlich verschluesselt hat. Die 5:45 aus dem manuellen Lauf sind nicht reproduziert.

## 7. "Was nicht funktioniert" - B2, Praezisierung

Alt: `Scheitert sofort beim ersten Backup-Piece.`

Neu: unveraendert, jetzt mit Beleg - das erste Piece enthielt nur unverschluesselte
CDB-Datafiles, der Abbruch kommt trotzdem mit `ORA-28374` (`run_20261024_082753.log:197-201`, `:208-210`;
wiederholt `run_20261025_063549.log:212-213`, ohne `ORA-00600`, Verdict nach der strengeren Regel `:229`).
