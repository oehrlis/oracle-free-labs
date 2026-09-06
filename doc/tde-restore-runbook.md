# TDE Restore Runbook - manuelle Schritte zum Verifikationstest

Begleitdokument zu [tde-restore-as-encrypted.md](tde-restore-as-encrypted.md) und
[tde-key-architecture.md](tde-key-architecture.md).

## Zweck

Dieses Runbook fuehrt jeden Schritt des Verifikationstests einzeln und zum Kopieren auf. Jeder
automatisierte Schritt aus `scripts/tde-verify/` ist hier als manuelle Entsprechung abgebildet,
damit ein Lauf auch ohne die Skripte nachvollziehbar ist - und damit bei einem Abbruch klar ist,
welcher Einzelschritt gescheitert ist.

Aufbau je Schritt: Nummer, ein Satz zum Zweck, der Befehl, die erwartete Ausgabe oder der
erwartete Zustand, und der Skriptaufruf, der dasselbe automatisch tut.

## Voraussetzungen

- Docker Desktop laeuft, Image `oracle-free-labs:latest` lokal vorhanden
- Repo-Root ist das Arbeitsverzeichnis fuer alle Host-Befehle
- `.env` enthaelt `ODBENCPROD_LISTENER_PORT=1532`, `ODBENCDEV_LISTENER_PORT=1533`,
  `ODBENCPROD_DB_MEM=3g`, `ODBENCDEV_DB_MEM=3g`
- `python3` auf dem Host verfuegbar (fuer `block_fingerprint.py`)
- Freier Plattenplatz fuer zwei Container plus Backupsets

## Sicherheitshinweise

- **Keine Passwoerter im Klartext.** Das Keystore-Passwort wird ausschliesslich im Container aus
  `/opt/oracle/dbconfig/FREE/wallet/wallet_pwd.txt` gelesen. Es steht in keinem Befehl dieses
  Runbooks und darf in keiner Kommandozeile und keinem Log erscheinen.
- **Ein Keystore ohne Kopie ist ein Totalverlust.** Bevor der Ziel-Keystore ersetzt wird, wird
  er nach `/opt/oracle/xchange/wallet_dev_pristine` gesichert und die Sicherung geprueft.
- **Nur die Lab-Services anfassen.** `odbencprod` und `odbencdev` sind fuer diesen Test
  angelegt. Kein Schritt dieses Runbooks darf auf `odbenc`, `odbdemo` oder einen anderen Service
  gerichtet werden.
- **Kein Schritt loescht Datafiles.** Nach dem Restore der Quell-Controlfile sind nur die
  Quellpfade in Benutzung; die frueheren Ziel-Datafiles bleiben als Waisen liegen. Das kostet
  Platz und haelt den Ablauf frei von destruktiven Operationen.
- Die Alert-Log-Pruefung gehoert zu jedem Schritt, der eine Instanz oeffnet. ORA-28365 und
  ORA-28374 sind hier Messergebnisse, keine Stoerungen.

## Phase 0 - Lab aufsetzen

### 0.1 Quell-Service starten

Startet `odbencprod` und laesst die Setup-Skripte durchlaufen (PDB, TDE, verschluesselter
`USERS`-Tablespace, SCOTT/HR).

```bash
docker compose --profile odbencprod up -d
docker compose --profile odbencprod logs -f
```

Erwartet: die Setup-Phase laeuft ohne ORA- oder SP2-Fehler durch. Der erste Start dauert
mehrere Minuten.

Automatisch: `make up-odbencprod`, Logs mit `make logs-odbencprod`.

### 0.2 Ziel-Service starten

Startet `odbencdev` mit eigenem Keystore, eigenem MEK und ohne Nutzdaten.

```bash
docker compose --profile odbencdev up -d
docker compose --profile odbencdev logs -f
```

Erwartet: gleiche Fehlerfreiheit. Kein PDB-Clone, keine Canary-Daten.

Automatisch: `make up-odbencdev`, Logs mit `make logs-odbencdev`.

### 0.3 Grunddaten der Quelle festhalten

Liest DBID und `LOG_MODE` - beides wird spaeter fuer `SET DBID` und fuer die Recovery gebraucht.

```bash
docker exec -i odbencprod sqlplus -S / as sysdba <<'SQL'
SET LINESIZE 200 PAGESIZE 100
SELECT dbid, name, open_mode, log_mode FROM v$database;
EXIT
SQL
```

Erwartet: `DBID 1515066983`, `LOG_MODE ARCHIVELOG`. ARCHIVELOG kommt aus dem Image-Default
`ENABLE_ARCHIVELOG=true`, ein eigenes Skript ist nicht noetig.

Automatisch: kein Skript - der Wert geht als `--dbid` in `tde_clone.sh` ein.

### 0.4 DBID des Ziels festhalten

Dokumentiert den Zustand vor dem Klon, damit ein spaeterer Restore nachweisbar die Quell-DBID
mitbringt.

```bash
docker exec -i odbencdev sqlplus -S / as sysdba <<'SQL'
SET LINESIZE 200 PAGESIZE 100
SELECT dbid, name, open_mode, log_mode FROM v$database;
EXIT
SQL
```

Erwartet: `DBID 1515067722`.

Automatisch: kein Skript.

### 0.5 Keystore-Modus pruefen

Belegt, dass der Test im UNITED Mode laeuft und wie viele MEKs im gemeinsamen Keystore liegen.

```bash
docker exec odbencprod ls -l /opt/oracle/dbconfig/FREE/wallet
docker exec -i odbencprod sqlplus -S / as sysdba <<'SQL'
SET LINESIZE 256 PAGESIZE 100
COLUMN wrl_parameter FORMAT A60
SELECT con_id, wrl_type, wrl_parameter, status, wallet_type, keystore_mode
  FROM v$encryption_wallet ORDER BY con_id;
SELECT con_id, name, value FROM v$parameter WHERE name = 'tde_configuration';
EXIT
SQL
```

Erwartet: genau ein Keystore-Verzeichnis `tde` plus `tde_seps` und `backups`, kein PDB-eigenes
Keystore-Verzeichnis. `KEYSTORE_MODE = UNITED` fuer die PDB,
`TDE_CONFIGURATION = KEYSTORE_CONFIGURATION=FILE` nur auf CDB-Ebene.

Automatisch: `config/common/scripts/ssenc_info.sql` gibt den Ueberblick inklusive der
Hidden-Parameter-Liste.

## Phase 1 - Baseline, Canary und Backup

### 1.1 Canary im verschluesselten Tablespace anlegen

Legt 5000 Zeilen mit einem bekannten Klartext-Marker im verschluesselten `USERS`-Tablespace an
und gibt die physischen Blockadressen aus.

```bash
docker exec -i odbencprod sqlplus -S / as sysdba <<'SQL'
ALTER SESSION SET CONTAINER = ODBENCPROD;
@/opt/oracle/common/scripts/csenc_canary.sql SCOTT USERS OEHRLI-CANARY-01 5000 CANARY_TDE
EXIT
SQL
```

Erwartet: 5000 Zeilen, 313 belegte Bloecke, Bereich 979 bis 1407. `ROWID_RELATIVE_FNO` meldet
bei einem Bigfile-Tablespace 0, waehrend `DBA_DATA_FILES.RELATIVE_FNO` 1024 zeigt - erwartetes
Bigfile-Verhalten, `ROWID_BLOCK_NUMBER` traegt die absolute Blocknummer.

Automatisch: derselbe Skriptaufruf, orchestriert im Setup des Testlaufs.

### 1.2 Kontrollgruppe im unverschluesselten Tablespace anlegen

Ohne diese Kontrollgruppe ist der Klartext-Scan nicht falsifizierbar: findet der Scan den Marker
auch hier nicht, ist der Scan selbst defekt.

```bash
docker exec -i odbencprod sqlplus -S / as sysdba <<'SQL'
ALTER SESSION SET CONTAINER = ODBENCPROD;
CREATE BIGFILE TABLESPACE canary_plain DATAFILE SIZE 20M AUTOEXTEND ON;
@/opt/oracle/common/scripts/csenc_canary.sql SCOTT CANARY_PLAIN OEHRLI-CANARY-01 5000 CANARY_PLAIN_TAB
EXIT
SQL
```

Erwartet: 5000 Zeilen, 313 Bloecke, Bereich 779 bis 1279.

Automatisch: derselbe Skriptaufruf mit anderem Tablespace- und Tabellennamen.

### 1.3 Schluesselkette der Quelle sichern

Haelt MEK-Identitaet, `MASTERKEYID`, `KEY_VERSION`, `ORIGIN` und den gewrappten TEK fest. Der
Aufruf muss zweimal erfolgen: die verschluesselten Tablespace-Zeilen liegen im PDB-Container.

```bash
docker exec -i odbencprod sqlplus -S / as sysdba <<'SQL'
@/opt/oracle/common/scripts/ssenc_keyproof.sql
EXIT
SQL

docker exec -i odbencprod sqlplus -S / as sysdba <<'SQL'
ALTER SESSION SET CONTAINER = ODBENCPROD;
@/opt/oracle/common/scripts/ssenc_keyproof.sql
EXIT
SQL
```

Erwartet in der PDB: `MASTERKEYID 8A27589796A248BE95222E59407FF962`, `KEY_VERSION 1`,
gewrappter TEK `BAD537ADDD695BEE7A29F6F27B65A03D6F195CCE3388AD0119D718087A8AFA55`,
`CIPHERMODE XTS`. In `CDB$ROOT` zwei MEKs mit `ORIGIN LOCAL`, con_id 1 und con_id 4.

Automatisch: `scripts/tde-verify/tde_evidence.sh` ruft beides und legt es als
`keyproof_cdb.log` und `keyproof_pdb.log` ab.

### 1.4 Impliziten Database Key festhalten

Der Database Key verschluesselt `SYSTEM`, `UNDO` und `TEMP` und ist beim Oeffnen der Datenbank
der Schluessel, dessen Fehlen ORA-28374 ausloest.

```bash
docker exec -i odbencprod sqlplus -S / as sysdba <<'SQL'
SET LINESIZE 256 PAGESIZE 100
SELECT * FROM v$database_key_info;
EXIT
SQL
```

Erwartet: RAW(48),
`9FA346CD92BF77F2967675FD236BF54B56A5834859447E5CA76D9BE659B724DF` plus Nullbytes, unter
derselben `MASTERKEYID`, `CIPHERMODE XTS`.

Automatisch: Teil der `ssenc_keyproof.sql`-Ausgabe.

### 1.5 Datafiles und Blockgroesse ermitteln

Liefert die Pfade und die Blockgroesse, die der Fingerabdruck braucht.

```bash
docker exec -i odbencprod sqlplus -S / as sysdba <<'SQL'
ALTER SESSION SET CONTAINER = ODBENCPROD;
SET LINESIZE 256 PAGESIZE 100
COLUMN file_name FORMAT A80
SELECT df.file_name, ts.block_size, df.bytes, df.blocks
  FROM dba_data_files df JOIN dba_tablespaces ts ON ts.tablespace_name = df.tablespace_name
 WHERE df.tablespace_name IN ('USERS','CANARY_PLAIN');
EXIT
SQL
```

Erwartet fuer `USERS`: 2560 Bloecke, 20971520 Byte, Blockgroesse 8192. Die Datei auf Platte ist
20979712 Byte gross, also 2561 Bloecke - der zusaetzliche Block ist der Dateikopf.

Automatisch: `tde_evidence.sh` schreibt das als `datafiles.tsv`.

### 1.6 Beide Tablespaces auf READ ONLY setzen

`READ ONLY` haelt die Datenbloecke stabil und nimmt die Datafiles aus der spaeteren Recovery
heraus. Ohne diesen Schritt verrauscht Recovery den Blockvergleich.

```bash
docker exec -i odbencprod sqlplus -S / as sysdba <<'SQL'
ALTER SESSION SET CONTAINER = ODBENCPROD;
ALTER TABLESPACE users READ ONLY;
ALTER TABLESPACE canary_plain READ ONLY;
SELECT tablespace_name, status, encrypted FROM dba_tablespaces
 WHERE tablespace_name IN ('USERS','CANARY_PLAIN');
EXIT
SQL
```

Erwartet: `STATUS READ ONLY` fuer beide, `ENCRYPTED YES` fuer `USERS` und `NO` fuer
`CANARY_PLAIN`.

Automatisch: kein Skript - bewusst manueller Schritt, weil er den Messaufbau definiert.

### 1.7 Blockfingerabdruck der Baseline erstellen

Berechnet SHA-256 je Block. Der Vergleich dieser Datei mit dem Klon ist der eigentliche Beweis.

```bash
python3 scripts/tde-verify/block_fingerprint.py fingerprint \
  data/odbencprod/oradata/FREE/ODBENCPROD/<users_datafile>.dbf \
  --block-size 8192 --out data/xchange/evidence/baseline/users.fp
```

Erwartet: 2561 Zeilen in der Fingerabdruck-Datei.

Automatisch: `scripts/tde-verify/tde_evidence.sh -s odbencprod -p ODBENCPROD -l baseline
-m 'OEHRLI-CANARY-01'` erledigt 1.3, 1.5 und 1.7 in einem Lauf.

### 1.8 Klartext-Scan gegen beide Datafiles

Belegt, dass `USERS` verschluesselt ist und dass der Scan funktioniert.

```bash
python3 scripts/tde-verify/block_fingerprint.py scan-plaintext \
  data/odbencprod/oradata/FREE/ODBENCPROD/<users_datafile>.dbf \
  'OEHRLI-CANARY-01' --block-size 8192 --expect-absent

python3 scripts/tde-verify/block_fingerprint.py scan-plaintext \
  data/odbencprod/oradata/FREE/ODBENCPROD/<canary_plain_datafile>.dbf \
  'OEHRLI-CANARY-01' --block-size 8192
```

Erwartet: 0 Treffer im verschluesselten Datafile (`--expect-absent` beendet mit Exit-Code 0),
313 Treffer im unverschluesselten ab Block 779. Die 313 aus dem Rohdatei-Scan muessen mit den
313 belegten Bloecken aus `DBMS_ROWID` uebereinstimmen - damit ist die Block-zu-Offset-Rechnung
unabhaengig bestaetigt.

Automatisch: `tde_evidence.sh` mit `-m 'OEHRLI-CANARY-01'`, Ablage als `plaintext_<df>.log`.

### 1.9 Gewrappten TEK und MASTERKEYID physisch lokalisieren

Sucht die Hex-Werte aus den V$-Views in der Rohdatei. Damit ist belegt, wo der TEK liegt und
dass er im Klon an derselben Stelle steht.

```bash
python3 scripts/tde-verify/block_fingerprint.py find-hex \
  data/odbencprod/oradata/FREE/ODBENCPROD/<users_datafile>.dbf \
  BAD537ADDD695BEE7A29F6F27B65A03D6F195CCE3388AD0119D718087A8AFA55 --block-size 8192

python3 scripts/tde-verify/block_fingerprint.py find-hex \
  data/odbencprod/oradata/FREE/ODBENCPROD/<users_datafile>.dbf \
  8A27589796A248BE95222E59407FF962 --block-size 8192
```

Erwartet: gewrappter TEK genau 1 Treffer bei Offset 8977, gleich Block 1 Byte 785.
`MASTERKEYID` genau 1 Treffer bei Offset 9025, gleich Block 1 Byte 833 - also 48 Byte nach dem
TEK-Beginn (32 Byte Schluessel plus 16 Byte Fuellbytes). Beide Sequenzen 0 Treffer in der
Kontrolldatei.

Automatisch: kein Skript - die Hex-Werte kommen aus 1.3 und werden hier eingesetzt.

### 1.10 Header-Block hexdumpen

Zeigt die Struktur im Rohbyte: Laengenbyte, TEK, Fuellbytes, `MASTERKEYID`.

```bash
python3 scripts/tde-verify/block_fingerprint.py hexdump \
  data/odbencprod/oradata/FREE/ODBENCPROD/<users_datafile>.dbf \
  --block 1 --block-size 8192 --length 1024
```

Erwartet: Laengenbyte `04`, dann 32 Byte gewrappter TEK, dann Fuellbytes, dann 16 Byte
`MASTERKEYID` im Klartext.

Automatisch: als zweite Quelle Oracles eigener Dump:

```bash
docker exec -i odbencprod sqlplus -S / as sysdba <<'SQL'
ALTER SESSION SET CONTAINER = ODBENCPROD;
@/opt/oracle/common/scripts/ssenc_filehdr.sql /opt/oracle/oradata/FREE/ODBENCPROD/<users_datafile>.dbf 1
EXIT
SQL
```

### 1.11 RMAN-Backup nach dem Austausch-Mount

Erzeugt Backupsets und Controlfile-Autobackup an der Stelle, an der `tde_clone.sh` sie erwartet.
Das Autobackup-Format muss gesetzt werden, sonst sucht `RESTORE ... FROM AUTOBACKUP` spaeter in
der Standard-FRA und meldet, es habe kein Autobackup gefunden.

```bash
docker exec -i odbencprod rman target / <<'RMAN'
RUN {
  ALLOCATE CHANNEL c1 DEVICE TYPE DISK;
  SET CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '/opt/oracle/xchange/backup/cf_%F';
  BACKUP DATABASE PLUS ARCHIVELOG FORMAT '/opt/oracle/xchange/backup/%U';
  RELEASE CHANNEL c1;
}
EXIT
RMAN
```

Erwartet: Backupsets unter `/opt/oracle/xchange/backup`, Controlfile-Autobackup
`cf_c-1515066983-20260903-00`. Die Laufzeit des ersten Backup-Sets ist der Vergleichswert fuer
Phase 4: 3 Sekunden.

Automatisch: kein Skript - `tde_clone.sh` setzt voraus, dass das Backup vorliegt.

### 1.12 Quell-Keystore in den Austausch-Mount stellen

`tde_clone.sh` erwartet den Quell-Keystore unter `/opt/oracle/xchange/wallet_prod`.

```bash
docker exec odbencprod bash -c \
  'mkdir -p /opt/oracle/xchange/wallet_prod && cp -a /opt/oracle/dbconfig/FREE/wallet/. /opt/oracle/xchange/wallet_prod/'
docker exec odbencprod ls -l /opt/oracle/xchange/wallet_prod/tde
```

Erwartet: `ewallet.p12` und `cwallet.sso` vorhanden und nicht leer, dazu `tde_seps`.

Automatisch: kein Skript - bewusst manueller Schritt, weil hier Schluesselmaterial die
Umgebungsgrenze verlaesst.

## Phase 2 - Variante A: normaler RESTORE mit transportiertem Prod-Wallet

### 2.1 Ziel-Keystore sichern und pruefen

Ohne geprueftes Backup darf der Ziel-Keystore nicht ersetzt werden.

```bash
docker exec odbencdev bash -c \
  'mkdir -p /opt/oracle/xchange/wallet_dev_pristine && cp -a /opt/oracle/dbconfig/FREE/wallet/. /opt/oracle/xchange/wallet_dev_pristine/'
docker exec odbencdev test -s /opt/oracle/xchange/wallet_dev_pristine/tde/ewallet.p12 \
  && echo "backup verified"
```

Erwartet: `backup verified`. Ohne diese Ausgabe hier abbrechen.

Automatisch: `tde_clone.sh --variant a` macht genau das und verweigert den Lauf, wenn die
Pruefung fehlschlaegt. Zusaetzlich ist `--delete` als Opt-in verlangt.

### 2.2 Prod-Keystore ins Ziel stellen

Ersetzt den Ziel-Keystore durch den Quell-Keystore - die aktuelle Praxis beim Kunden.

```bash
docker exec odbencdev bash -c \
  'rm -rf /opt/oracle/dbconfig/FREE/wallet/tde /opt/oracle/dbconfig/FREE/wallet/tde_seps \
   && cp -a /opt/oracle/xchange/wallet_prod/. /opt/oracle/dbconfig/FREE/wallet/'
```

Erwartet: keine Ausgabe. Der Ziel-Keystore enthaelt jetzt beide Prod-MEKs.

Automatisch: `scripts/tde-verify/tde_clone.sh --variant a --dbid 1515066983 --delete --yes`

### 2.3 Ziel NOMOUNT starten

Der Restore der Controlfile braucht eine Instanz ohne Mount.

```bash
docker exec -i odbencdev sqlplus -S / as sysdba <<'SQL'
WHENEVER SQLERROR CONTINUE
SHUTDOWN IMMEDIATE;
STARTUP NOMOUNT;
EXIT
SQL
```

Erwartet: `ORACLE instance started`, Status NOMOUNT.

Automatisch: Teil von `tde_clone.sh`.

### 2.4 Veraltete Online-Redo-Logs aus dem Weg raeumen

Die Quell-Controlfile listet dieselben Redo-Log-Pfade, die das Ziel bereits benutzt. Die Dateien
auf Platte gehoeren aber noch zur frueheren Ziel-Datenbank - Recovery bricht dann mit ORA-19698
"is from different database" ab. `OPEN RESETLOGS` legt sie neu an, deshalb wird nur verschoben,
nie geloescht.

```bash
docker exec odbencdev bash -c \
  'mkdir -p /opt/oracle/xchange/stale_redo_odbencdev && for f in /opt/oracle/oradata/FREE/redo*.log; do [ -e "$f" ] && mv "$f" /opt/oracle/xchange/stale_redo_odbencdev/ && echo "moved $f"; done; true'
```

Erwartet: eine `moved ...`-Zeile je Redo-Log-Gruppe.

Automatisch: Teil von `tde_clone.sh`.

### 2.5 Quell-Controlfile restaurieren und mounten

`SET DBID` ist noetig, weil das Ziel eine andere DBID hat. Das Autobackup-Format muss dem
entsprechen, das die Quelle in 1.11 verwendet hat.

```bash
docker exec -i odbencdev rman target / <<'RMAN'
SET DBID 1515066983;
RUN {
  ALLOCATE CHANNEL c1 DEVICE TYPE DISK;
  SET CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '/opt/oracle/xchange/backup/cf_%F';
  RESTORE CONTROLFILE FROM AUTOBACKUP;
  ALTER DATABASE MOUNT;
  RELEASE CHANNEL c1;
}
EXIT
RMAN
```

Erwartet: Autobackup `cf_c-1515066983-20260903-00` gefunden, Controlfile restauriert, Datenbank
gemountet.

Automatisch: Teil von `tde_clone.sh`.

### 2.6 Keystore-Zustand pruefen

Zeigt den Nebenbefund zum LOCAL Auto-Login: der transportierte Keystore oeffnet sich auf einem
anderen Host nicht von selbst.

```bash
docker exec -i odbencdev sqlplus -S / as sysdba <<'SQL'
SET LINESIZE 200 PAGESIZE 100
COLUMN status FORMAT A14
COLUMN wallet_type FORMAT A16
SELECT con_id, status, wallet_type FROM v$encryption_wallet ORDER BY con_id;
EXIT
SQL
```

Erwartet: `STATUS CLOSED`, `WALLET_TYPE UNKNOWN`. Ursache: der Keystore ist als LOCAL AUTO_LOGIN
erzeugt und damit an den Hostnamen `odbencprod` gebunden. Betrifft auch den SEPS-Store
`tde_seps`.

Automatisch: `tde_clone.sh` gibt diese Abfrage nach dem Oeffnen aus.

### 2.7 Keystore explizit mit Passwort oeffnen

Fuer Variante A nicht zwingend - ein normaler RESTORE kopiert Chiffrat und braucht keinen
Schluessel. Zum Lesen der Daten und fuer alle `AS ENCRYPTED`-Varianten ist es Pflicht.

```bash
docker exec odbencdev bash -c '
KSPWD=$(cat /opt/oracle/dbconfig/FREE/wallet/wallet_pwd.txt)
sqlplus -S / as sysdba <<SQL
SET LINESIZE 200 PAGESIZE 100 FEEDBACK OFF
WHENEVER SQLERROR CONTINUE
ADMINISTER KEY MANAGEMENT SET KEYSTORE OPEN FORCE KEYSTORE IDENTIFIED BY "${KSPWD}" CONTAINER=ALL;
COLUMN status FORMAT A14
COLUMN wallet_type FORMAT A16
SELECT con_id, status, wallet_type FROM v\$encryption_wallet ORDER BY con_id;
EXIT
SQL
'
```

Erwartet: `keystore altered`, danach `WALLET_TYPE PASSWORD`. Das Passwort wird im Container
gelesen und erscheint in keinem Host-Befehl.

Automatisch: Funktion `open_keystore` in `tde_clone.sh`, die die Ausgabe zusaetzlich filtert.

### 2.8 Backup-Pieces katalogisieren

Die restaurierte Controlfile kennt die Backup-Pieces unter ihren Quellpfaden; der Katalog holt
sie an der jetzigen Stelle nach.

```bash
docker exec -i odbencdev rman target / <<'RMAN'
RUN {
  ALLOCATE CHANNEL c1 DEVICE TYPE DISK;
  CATALOG START WITH '/opt/oracle/xchange/backup/' NOPROMPT;
  RELEASE CHANNEL c1;
}
EXIT
RMAN
```

Erwartet: alle Pieces katalogisiert, keine Warnung ueber fehlende Dateien.

Automatisch: Teil von `tde_clone.sh`.

### 2.9 Letzte archivierte Sequenz bestimmen

Ohne `SET UNTIL SEQUENCE` fragt RMAN nach dem Log, das beim Backup noch aktives Online-Log war,
und scheitert mit RMAN-06054.

```bash
docker exec -i odbencdev sqlplus -S / as sysdba <<'SQL'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 80 TRIMSPOOL ON
SELECT NVL(MAX(sequence#), 0) FROM v$archived_log WHERE thread# = 1;
EXIT
SQL
```

Erwartet: eine Zahl. Fuer den `RECOVER`-Lauf gilt `SET UNTIL SEQUENCE <diese Zahl plus 1>`.

Automatisch: Funktion `last_archived_sequence` in `tde_clone.sh`.

### 2.10 Restore und Recover

Der eigentliche Klon-Schritt der Variante A.

```bash
docker exec -i odbencdev rman target / <<'RMAN'
RUN {
  ALLOCATE CHANNEL c1 DEVICE TYPE DISK;
  SET UNTIL SEQUENCE <letzte_sequenz_plus_1> THREAD 1;
  RESTORE DATABASE;
  RECOVER DATABASE;
  RELEASE CHANNEL c1;
}
EXIT
RMAN
```

Erwartet: Restore ohne offenen Keystore erfolgreich, Laufzeit des ersten Backup-Sets 3 Sekunden.
Recovery meldet "datafile 20 not processed because file is read-only", ebenso fuer Datafile 21 -
das ist der gewuenschte Effekt von Schritt 1.6.

Automatisch: `tde_clone.sh --variant a`, Klausel `RESTORE DATABASE;`.

### 2.11 Datenbank mit RESETLOGS oeffnen

```bash
docker exec -i odbencdev sqlplus -S / as sysdba <<'SQL'
WHENEVER SQLERROR CONTINUE
ALTER DATABASE OPEN RESETLOGS;
SELECT dbid, name, open_mode, log_mode FROM v$database;
EXIT
SQL
```

Erwartet: `OPEN_MODE READ WRITE`, `DBID 1515066983` - die Quell-DBID im Ziel.

Automatisch: Teil von `tde_clone.sh`.

### 2.12 Schluesselkette im Klon pruefen

```bash
docker exec -i odbencdev sqlplus -S / as sysdba <<'SQL'
ALTER SESSION SET CONTAINER = ODBENCPROD;
@/opt/oracle/common/scripts/ssenc_keyproof.sql
EXIT
SQL
```

Erwartet: `MASTERKEYID 8A27589796A248BE95222E59407FF962`, `KEY_VERSION 1`, gewrappter TEK
`BAD537AD...FA55` - alles identisch zur Quelle. `ORIGIN` zeigt `LOCAL`, nicht `IMPORTED`: eine
Keystore-Kopie hinterlaesst keine Spur der Herkunft.

Automatisch: `tde_evidence.sh -s odbencdev -p ODBENCPROD -l variant_a -m 'OEHRLI-CANARY-01'`

### 2.13 Blockvergleich gegen die Baseline

Der Kern des Beweises.

```bash
python3 scripts/tde-verify/block_fingerprint.py fingerprint \
  data/odbencdev/oradata/FREE/ODBENCPROD/<users_datafile>.dbf \
  --block-size 8192 --out data/xchange/evidence/variant_a/users.fp

python3 scripts/tde-verify/block_fingerprint.py compare \
  data/xchange/evidence/baseline/users.fp \
  data/xchange/evidence/variant_a/users.fp \
  --label-a baseline --label-b variant_a
```

Erwartet: 2561 Bloecke verglichen, 1269 identisch, 1292 geaendert. Alle 313 Canary-Datenbloecke
identisch. Die Abweichungen liegen in leeren Bloecken - RMAN Backup Optimization sichert leere
Bloecke nicht, sondern schreibt sie beim Restore neu.

Automatisch: `scripts/tde-verify/tde_evidence.sh --compare baseline variant_a`

### 2.14 Gegenprobe an einem leeren Block

Belegt, dass die Abweichungen aus der Backup-Optimierung stammen und nicht aus einem
Re-encrypt.

```bash
python3 scripts/tde-verify/block_fingerprint.py hexdump \
  data/odbencprod/oradata/FREE/ODBENCPROD/<users_datafile>.dbf \
  --block 2000 --block-size 8192 --length 256

python3 scripts/tde-verify/block_fingerprint.py hexdump \
  data/odbencdev/oradata/FREE/ODBENCPROD/<users_datafile>.dbf \
  --block 2000 --block-size 8192 --length 256
```

Erwartet: die Quelle traegt Zufallsbytes, der Klon nur Nullen nach dem Blockheader.

Automatisch: kein Skript - gezielte Einzelpruefung.

### 2.15 TEK-Position im Klon pruefen

```bash
python3 scripts/tde-verify/block_fingerprint.py find-hex \
  data/odbencdev/oradata/FREE/ODBENCPROD/<users_datafile>.dbf \
  BAD537ADDD695BEE7A29F6F27B65A03D6F195CCE3388AD0119D718087A8AFA55 --block-size 8192
```

Erwartet: genau 1 Treffer bei Offset 8977 - dieselbe Stelle wie in der Quelle.

Automatisch: kein Skript.

## Phase 3 - Variante B2: AS ENCRYPTED USING KEY ohne Prod-MEK

### 3.1 Ziel-Keystore auf den Ursprungszustand zuruecksetzen

Nach Variante A liegt der Prod-Keystore im Ziel. Fuer B2 muss ausschliesslich der Dev-eigene
Keystore aktiv sein.

```bash
docker exec odbencdev bash -c \
  'rm -rf /opt/oracle/dbconfig/FREE/wallet/tde /opt/oracle/dbconfig/FREE/wallet/tde_seps \
   && cp -a /opt/oracle/xchange/wallet_dev_pristine/. /opt/oracle/dbconfig/FREE/wallet/'
docker exec -i odbencdev sqlplus -S / as sysdba <<'SQL'
WHENEVER SQLERROR CONTINUE
SHUTDOWN ABORT;
STARTUP;
EXIT
SQL
```

Erwartet: nach dem Neustart ist nur der Dev-MEK `AWZuopGe2EGHqnGxulapWxw...` sichtbar.

Automatisch: kein Skript - der Zustandswechsel ist bewusst manuell.

### 3.2 Dev-MEK-ID ermitteln

Die Key-ID geht als `USING KEY` in den Restore ein.

```bash
docker exec -i odbencdev sqlplus -S / as sysdba <<'SQL'
SET LINESIZE 256 PAGESIZE 100
COLUMN key_id FORMAT A56
SELECT con_id, key_id, tag, origin, creator_dbname FROM v$encryption_keys ORDER BY con_id;
EXIT
SQL
```

Erwartet: genau die Dev-Schluessel, kein Prod-Schluessel.

Automatisch: Teil der `ssenc_keyproof.sql`-Ausgabe.

### 3.3 Restore AS ENCRYPTED ohne Prod-MEK

Prueft, ob RMAN den Quell-MEK voraussetzt.

```bash
scripts/tde-verify/tde_clone.sh --variant b2 --dbid 1515066983 --key '<dev_mek_key_id>' --yes
```

Erwartet: Abbruch mit ORA-19870 "error while restoring backup piece" plus ORA-28374 "typed
master key not found in wallet". Der Fehler ist das Messergebnis, kein Testabbruch.

Manuelle Entsprechung: Schritte 2.3 bis 2.9, dann

```bash
docker exec -i odbencdev rman target / <<'RMAN'
RUN {
  ALLOCATE CHANNEL c1 DEVICE TYPE DISK;
  SET UNTIL SEQUENCE <letzte_sequenz_plus_1> THREAD 1;
  RESTORE DATABASE AS ENCRYPTED USING KEY '<dev_mek_key_id>';
  RECOVER DATABASE;
  RELEASE CHANNEL c1;
}
EXIT
RMAN
```

### 3.4 Fehlerbild festhalten

```bash
docker exec odbencdev bash -c 'ls -t /opt/oracle/diag/rdbms/*/*/trace/alert_*.log | head -1'
```

Erwartet: die ORA-28374-Meldung im Alert Log, passend zur RMAN-Ausgabe. Der dokumentierte Ausweg
waere `MERGE KEYSTORE` aus einem Backup-Wallet - genau das ist im Klon-Szenario nicht gewuenscht.

Automatisch: kein Skript.

## Phase 4 - Variante B1: AS ENCRYPTED USING KEY mit Prod-MEK

### 4.1 Prod-Keystore ins Ziel stellen und eigenen Schluessel anlegen

Der Ziel-Keystore enthaelt danach beide Prod-Schluessel plus einen neuen, dev-eigenen.

```bash
docker exec odbencdev bash -c \
  'rm -rf /opt/oracle/dbconfig/FREE/wallet/tde /opt/oracle/dbconfig/FREE/wallet/tde_seps \
   && cp -a /opt/oracle/xchange/wallet_prod/. /opt/oracle/dbconfig/FREE/wallet/'

docker exec odbencdev bash -c '
KSPWD=$(cat /opt/oracle/dbconfig/FREE/wallet/wallet_pwd.txt)
sqlplus -S / as sysdba <<SQL
SET LINESIZE 256 PAGESIZE 100 FEEDBACK OFF
WHENEVER SQLERROR CONTINUE
ADMINISTER KEY MANAGEMENT SET KEYSTORE OPEN FORCE KEYSTORE IDENTIFIED BY "${KSPWD}" CONTAINER=ALL;
ADMINISTER KEY MANAGEMENT CREATE KEY USING TAG '"'"'devtarget-2026-09-03'"'"' FORCE KEYSTORE IDENTIFIED BY "${KSPWD}" WITH BACKUP;
COLUMN key_id FORMAT A56
SELECT con_id, key_id, tag, origin FROM v\$encryption_keys ORDER BY con_id;
EXIT
SQL
'
```

Erwartet: der neue Schluessel `AV75yf3iEUAWtYUhndGAVAg...` erscheint mit con_id 0 - angelegt,
aber nicht aktiviert. `CREATE KEY` statt `SET KEY` ist hier Absicht: der Schluessel soll fuer
`USING KEY` verfuegbar sein, ohne den aktiven MEK zu wechseln.

Automatisch: kein Skript - `tde_clone.sh --variant b1` weist ausdruecklich darauf hin, dass
Bereitstellung und Import des Schluesselmaterials separate, dokumentierte Schritte sind.

### 4.2 Keystore nach dem Instanzneustart oeffnen

Anders als bei Variante A ist das hier zwingend.

```bash
docker exec -i odbencdev sqlplus -S / as sysdba <<'SQL'
WHENEVER SQLERROR CONTINUE
SHUTDOWN IMMEDIATE;
STARTUP NOMOUNT;
EXIT
SQL
```

Danach Schritt 2.7 wiederholen.

Erwartet: `WALLET_TYPE PASSWORD`. Ohne diesen Schritt scheitert der Restore mit ORA-28365.

Automatisch: Funktion `open_keystore` in `tde_clone.sh`.

### 4.3 Restore AS ENCRYPTED mit dem Dev-Schluessel

```bash
scripts/tde-verify/tde_clone.sh --variant b1 --dbid 1515066983 \
  --key 'AV75yf3iEUAWtYUhndGAVAg...' --yes
```

Erwartet, in dieser Reihenfolge:

1. Das erste Backup-Set mit den unverschluesselten CDB-Datafiles wird erfolgreich restauriert.
   Laufzeit 5:45 gegenueber 3 Sekunden bei einem normalen Restore - auf unverschluesselten
   Quelldateien leistet `AS ENCRYPTED` echte Blockarbeit. Der dokumentierte Anwendungsfall
   funktioniert und ist am Timing messbar.
2. Sobald RMAN das bereits verschluesselte Datafile 20 erreicht, bricht es ab:

```text
ORA-00600: internal error code, arguments: [kcbtse_encdec_tbsblk_1], [4], [2],
[806], [18], [806], [20], [4294967295], [0], [0], [], []
```

Manuelle Entsprechung: Schritte 2.3 bis 2.9, dann der RMAN-Block aus 3.3 mit der Key-ID des
dev-eigenen Schluessels.

### 4.4 Reproduzierbarkeit pruefen

Belegt, dass der interne Fehler nicht Zufall ist.

```bash
scripts/tde-verify/tde_clone.sh --variant b1 --dbid 1515066983 \
  --key 'AV75yf3iEUAWtYUhndGAVAg...' --yes
```

Erwartet: dreimal derselbe Fehler, mit und ohne `FORCE`, identische ORA-00600-Argumente,
Keystore jeweils offen mit `WALLET_TYPE PASSWORD`.

Automatisch: derselbe Aufruf, wiederholt.

## Phase 4a - Variante C: DUPLICATE ... AS ENCRYPTED

Diese Phase ist nachtraeglich eingefuegt und behaelt die Nummerierung der folgenden Phasen bei.
Automatisch laeuft sie als `scripts/tde-verify/tests/40_variant_c.sh --yes`.

### 4a.1 Ziel auf einen unveraenderten Zustand zuruecksetzen

`DUPLICATE` verlangt eine unveraenderte Auxiliary-Instanz. Hat eine vorherige Variante bereits
ein `RESTORE` gefahren oder die Ziel-Controlfile angefasst, bricht `DUPLICATE` mit ORA-01507
"database not mounted" ab. Der Reset ist deshalb Pflicht, nicht Kosmetik.

```bash
make reset SERVICE=odbencdev
make up-odbencdev
make logs-odbencdev
```

Erwartet: der Service ist frisch aufgesetzt und bereit, ohne ORA- oder SP2-Fehler im Setup-Log.

Automatisch: `40_variant_c.sh` setzt `odbencdev` selbst zurueck und wartet auf die Bereitschaft.

### 4a.2 Ziel-Keystore sichern und Quell-Keystore auf die Auxiliary stellen

Wie in Variante A wird zuerst gesichert, dann ersetzt. Ohne geprueftes Backup nicht weitermachen.

```bash
docker exec odbencdev bash -c \
  'mkdir -p /opt/oracle/xchange/wallet_dev_pristine && cp -a /opt/oracle/dbconfig/FREE/wallet/. /opt/oracle/xchange/wallet_dev_pristine/'
docker exec odbencdev test -s /opt/oracle/xchange/wallet_dev_pristine/tde/ewallet.p12 \
  && echo "backup verified"

docker exec odbencdev bash -c \
  'rm -rf /opt/oracle/dbconfig/FREE/wallet/tde /opt/oracle/dbconfig/FREE/wallet/tde_seps \
   && cp -a /opt/oracle/xchange/wallet_prod/. /opt/oracle/dbconfig/FREE/wallet/'
```

Erwartet: `backup verified`, danach liegt der Quell-Keystore im Ziel.

Automatisch: Funktion `prepare_wallet` in `tde_clone.sh`, Zweig `c`.

### 4a.3 Auto-Login-Keystore auf dem Ziel-Host neu erzeugen

`DUPLICATE` startet die Auxiliary ueber seine eigenen Memory-Skripte mehrfach neu. Ein nur per
Passwort geoeffneter Keystore ueberlebt das nicht. Der mitgebrachte `cwallet.sso` ist als LOCAL
AUTO_LOGIN an den Quell-Hostnamen gebunden und taugt hier nicht - er wird zur Seite gelegt und
aus `ewallet.p12` ein neuer Auto-Login auf diesem Host erzeugt.

```bash
docker exec -i odbencdev bash -s <<'INNER'
set -u
W="/opt/oracle/dbconfig/FREE/wallet"
XCH="/opt/oracle/xchange"
mkdir -p "${XCH}/sso_foreign"
mv "${W}"/tde/cwallet*.sso "${XCH}/sso_foreign/" 2>/dev/null || true
PW="$(cat "${W}/wallet_pwd.txt")"
sqlplus -S / as sysdba >/tmp/autologin.$$.log 2>&1 <<SQL
WHENEVER SQLERROR CONTINUE
SET LINESIZE 200 PAGESIZE 100 FEEDBACK OFF
ADMINISTER KEY MANAGEMENT SET KEYSTORE OPEN FORCE KEYSTORE IDENTIFIED BY "${PW}" CONTAINER=ALL;
ADMINISTER KEY MANAGEMENT CREATE LOCAL AUTO_LOGIN KEYSTORE FROM KEYSTORE '${W}/tde' IDENTIFIED BY "${PW}";
COLUMN status FORMAT A20
COLUMN wallet_type FORMAT A16
SELECT con_id, status, wallet_type FROM v\$encryption_wallet ORDER BY con_id;
EXIT
SQL
grep -viE "identified by" /tmp/autologin.$$.log
rm -f /tmp/autologin.$$.log
INNER
```

Erwartet: `WALLET_TYPE LOCAL_AUTOLOGIN`, `STATUS OPEN` fuer alle Container ausser `PDB$SEED` -
`PDB$SEED` haelt im Normalbetrieb einen geschlossenen Keystore und haelt keine verschluesselten
Daten. Das Passwort wird im Container gelesen und erscheint in keinem Host-Befehl; die Ausgabe
wird gefiltert.

Automatisch: Funktion `ensure_autologin` in `tde_clone.sh`. Sie prueft danach, dass kein
Container ausser `PDB$SEED` einen geschlossenen Keystore hat, und bricht sonst ab - jede Abfrage
auf verschluesselte Daten wuerde mit ORA-28365 scheitern.

### 4a.4 Auxiliary NOMOUNT starten

```bash
docker exec -i odbencdev sqlplus -S / as sysdba <<'SQL'
WHENEVER SQLERROR CONTINUE
SHUTDOWN IMMEDIATE;
STARTUP NOMOUNT;
SELECT status FROM v$instance;
EXIT
SQL
```

Erwartet: `STATUS STARTED`.

Automatisch: Funktion `do_duplicate` in `tde_clone.sh`.

### 4a.5 Veraltete Online-Redo-Logs aus dem Weg raeumen

Gleiche Begruendung wie in Schritt 2.4: die Redo-Log-Pfade kollidieren mit denen der frueheren
Ziel-Datenbank. Schritt 2.4 hier unveraendert wiederholen.

Erwartet: eine `moved ...`-Zeile je Redo-Log-Gruppe.

Automatisch: Funktion `quarantine_stale_redo` in `tde_clone.sh`.

### 4a.6 DUPLICATE aus dem Backup-Verzeichnis

Backup-basierte Duplizierung braucht keine Verbindung zur Quelle. RMAN wird deshalb ohne
`target /` gestartet: mit `target /` waere die lokale NOMOUNT-Instanz das Target und RMAN
verweigert mit RMAN-05502, "the target database must be mounted when issuing a DUPLICATE
command". `NOFILENAMECHECK` ist noetig, weil Quelle und Ziel in ihren Containern dieselben Pfade
benutzen.

```bash
docker exec -i odbencdev rman <<'RMAN'
connect auxiliary /
DUPLICATE DATABASE TO FREE
  BACKUP LOCATION '/opt/oracle/xchange/backup'
  NOFILENAMECHECK
  AS ENCRYPTED;
EXIT
RMAN
```

Erwartet: der Lauf geht durch. `DUPLICATE` vergibt eine neue DBID - anders als `RESTORE`, das
die Quell-DBID uebernimmt.

Automatisch: Funktion `do_duplicate` in `tde_clone.sh`, aufgerufen ueber
`tde_clone.sh --variant c --dbid <source_dbid> --cf-piece <cf_autobackup>`.

### 4a.7 Pluggable Databases oeffnen

```bash
docker exec -i odbencdev sqlplus -S / as sysdba <<'SQL'
WHENEVER SQLERROR CONTINUE
ALTER PLUGGABLE DATABASE ALL OPEN;
SELECT dbid, name, open_mode FROM v$database;
SELECT name, open_mode FROM v$pdbs;
EXIT
SQL
```

Erwartet: `ODBENCPROD` mit `OPEN_MODE READ WRITE`.

Automatisch: Teil von `do_duplicate`.

### 4a.8 Schluesselkette im Klon pruefen

```bash
docker exec -i odbencdev sqlplus -S / as sysdba <<'SQL'
ALTER SESSION SET CONTAINER = ODBENCPROD;
@/opt/oracle/common/scripts/ssenc_keyproof.sql
EXIT
SQL
```

Erwartet: `MASTERKEYID` und gewrappter TEK des Tablespace `USERS` identisch zur Baseline aus
Schritt 1.3. Der bereits verschluesselte Tablespace behaelt seinen TEK - `AS ENCRYPTED` legt
dafuer kein neues Schluesselmaterial an. Die zuvor unverschluesselten Tablespaces werden unter
dem bestehenden Database Key der PDB verschluesselt, ebenfalls ohne neues TEK-Material.

Automatisch: `collect_evidence` in `40_variant_c.sh`, Label `variant_c`.

### 4a.9 Blockvergleich gegen die Baseline

```bash
python3 scripts/tde-verify/block_fingerprint.py fingerprint \
  data/odbencdev/oradata/FREE/ODBENCPROD/<users_datafile>.dbf \
  --block-size 8192 --out data/xchange/evidence/variant_c/users.fp

python3 scripts/tde-verify/block_fingerprint.py compare \
  data/xchange/evidence/baseline/users.fp \
  data/xchange/evidence/variant_c/users.fp \
  --label-a baseline --label-b variant_c
```

Erwartet: die 313 Canary-Datenbloecke sind identisch, 0 sind geaendert. Der Gesamtblockvergleich
ist hier ohne Aussage - er wird von nie benutzten Bloecken dominiert, die RMAN nicht sichert und
beim Klonen frisch schreibt. Massgeblich ist allein der Canary-Bereich.

Automatisch: `compare_evidence baseline variant_c` und `compare_canary_blocks` in
`40_variant_c.sh`. Der Test wertet nur dann PASS, wenn TEK identisch **und** Canary-Chiffrat
identisch sind; eine identische TEK bei veraendertem Chiffrat gilt als widerspruechlich und
wird als FAIL gemeldet.

### 4a.10 Messwerte aus dem E2E-Lauf

Werte aus dem durchgehenden Lauf vom 2026-09-06 (`tasks/e2e-facts.md`). Die Baseline dieses
Laufs weicht von den Werten der Einzelmessungen in Phase 1 ab; verglichen wird immer innerhalb
eines Laufs.

<!-- markdownlint-disable MD013 MD060 -->
| Messwert | Baseline (Schritt 10) | nach Variante C |
|---|---|---|
| `MASTERKEYID` | `EC574AF166934D45AB5AC1F2267A297A` | unveraendert |
| `ENCRYPTEDKEY` | `059EFEB1BB6D72140B68FD768F80105B37BB912E84E6273E82227A027FD830F3` | unveraendert |
| Canary-Bloecke | - | 313 identisch / 0 geaendert |
<!-- markdownlint-restore -->

Aussage: der Schluessel bleibt. `DUPLICATE ... AS ENCRYPTED` loest die Bindung an den
Quell-MEK nicht.

## Phase 5 - Entschluesselungspfad: RESTORE FORCE AS DECRYPTED

### 5.1 Restore mit FORCE AS DECRYPTED

`FORCE` ist zwingend. Ohne `FORCE` ueberspringt die Restore-Optimierung genau die Datafiles, die
schon auf Stand sind - der Lauf sieht erfolgreich aus und hat die Datafiles 20 und 21 gar nicht
angefasst.

```bash
docker exec -i odbencdev rman target / <<'RMAN'
RUN {
  ALLOCATE CHANNEL c1 DEVICE TYPE DISK;
  SET UNTIL SEQUENCE <letzte_sequenz_plus_1> THREAD 1;
  RESTORE DATABASE FORCE AS DECRYPTED;
  RECOVER DATABASE;
  RELEASE CHANNEL c1;
}
EXIT
RMAN
```

Erwartet: Restore laeuft durch, Datafiles 20 und 21 werden angefasst.

Automatisch: kein Skript - `tde_clone.sh` deckt nur die Varianten a, b1, b2 ab.

### 5.2 Entschluesselung verifizieren

```bash
docker exec -i odbencdev sqlplus -S / as sysdba <<'SQL'
ALTER SESSION SET CONTAINER = ODBENCPROD;
SET LINESIZE 200 PAGESIZE 100
SELECT tablespace_name, encrypted FROM dba_tablespaces ORDER BY tablespace_name;
SELECT COUNT(*) FROM v$encrypted_tablespaces;
EXIT
SQL

python3 scripts/tde-verify/block_fingerprint.py scan-plaintext \
  data/odbencdev/oradata/FREE/ODBENCPROD/<users_datafile>.dbf \
  'OEHRLI-CANARY-01' --block-size 8192
```

Erwartet: `ENCRYPTED = NO` fuer alle Tablespaces, `V$ENCRYPTED_TABLESPACES` leer, Canary mit
5000 Zeilen lesbar, und der Klartext-Marker mit 313 Treffern im Datafile auffindbar ab Block
979. Die Bloecke sind echt entschluesselt.

Automatisch: `tde_evidence.sh` mit `-m 'OEHRLI-CANARY-01'` fuer den Scan-Teil.

### 5.3 Abhaengigkeit vom Prod-MEK nachweisen

Belegt, dass Entschluesseln allein die Abhaengigkeit nicht bricht.

```bash
docker exec odbencdev bash -c \
  'rm -rf /opt/oracle/dbconfig/FREE/wallet/tde /opt/oracle/dbconfig/FREE/wallet/tde_seps \
   && cp -a /opt/oracle/xchange/wallet_dev_pristine/. /opt/oracle/dbconfig/FREE/wallet/'
docker exec -i odbencdev sqlplus -S / as sysdba <<'SQL'
WHENEVER SQLERROR CONTINUE
SHUTDOWN ABORT;
STARTUP MOUNT;
ALTER DATABASE OPEN;
EXIT
SQL
```

Erwartet im Alert Log:

```text
KZTDE:kztsmptc: Missing Key ID: AbyhIcXQQk+XiBYrKzrI3FY...
Active database master key not found in the wallet!: ena 4 flag 0x4e mkloc 0x9
mkid bca121c5d0424f9788162b2b3ac8dc56
ORA-28374 signalled during ALTER DATABASE OPEN
```

Automatisch: `config/common/scripts/ssenc_canary.sql` haelt den Lesefehler als Messwert im Log
fest, ohne den Lauf abzubrechen.

### 5.4 Eigenen Master Key setzen

Dreht den Database Key auf einen dev-eigenen Wert - der dokumentierte Schritt nach einem Klon,
damit Prod- und Non-Prod-MEK auseinanderlaufen.

```bash
docker exec odbencdev bash -c '
KSPWD=$(cat /opt/oracle/dbconfig/FREE/wallet/wallet_pwd.txt)
sqlplus -S / as sysdba <<SQL
SET LINESIZE 256 PAGESIZE 100 FEEDBACK OFF
WHENEVER SQLERROR CONTINUE
ADMINISTER KEY MANAGEMENT SET KEYSTORE OPEN FORCE KEYSTORE IDENTIFIED BY "${KSPWD}" CONTAINER=ALL;
ADMINISTER KEY MANAGEMENT SET KEY FORCE KEYSTORE IDENTIFIED BY "${KSPWD}" WITH BACKUP CONTAINER=ALL;
SELECT * FROM v\$database_key_info;
EXIT
SQL
'
```

Erwartet: der CDB-Database-Key wechselt von `BCA121C5D0424F9788162B2B3AC8DC56` auf
`6E93045783B04AAAADA609B4C8CDBFB3`. Der Befehl endet zusaetzlich mit ORA-46663 "master
encryption keys not created for all PDBs for REKEY", weil `PDB$SEED` keinen Schluessel hat.

Automatisch: kein Skript.

### 5.5 Master Key in der PDB setzen

```bash
docker exec odbencdev bash -c '
KSPWD=$(cat /opt/oracle/dbconfig/FREE/wallet/wallet_pwd.txt)
sqlplus -S / as sysdba <<SQL
SET LINESIZE 256 PAGESIZE 100 FEEDBACK OFF
WHENEVER SQLERROR CONTINUE
ALTER SESSION SET CONTAINER = ODBENCPROD;
ADMINISTER KEY MANAGEMENT SET KEY FORCE KEYSTORE IDENTIFIED BY "${KSPWD}" WITH BACKUP;
SELECT * FROM v\$database_key_info;
EXIT
SQL
'
```

Erwartet: der PDB-Key wechselt auf `8252C3B0871744CBA42F15CA00FFBCA7`.

Automatisch: kein Skript.

### 5.6 Tablespace offline neu verschluesseln

```bash
docker exec -i odbencdev sqlplus -S / as sysdba <<'SQL'
WHENEVER SQLERROR CONTINUE
ALTER SESSION SET CONTAINER = ODBENCPROD;
ALTER TABLESPACE users OFFLINE;
ALTER TABLESPACE users ENCRYPTION OFFLINE ENCRYPT;
ALTER TABLESPACE users ONLINE;
SELECT tablespace_name, encrypted FROM dba_tablespaces WHERE tablespace_name = 'USERS';
EXIT
SQL
```

Erwartet: `ENCRYPTED YES`, `KEY_VERSION 3`, gewrappter TEK
`8FBDA2A856F5128B5C2D27F51A9B769608D1CA60185320DD67861E148C303E41`, `MASTERKEYID`
`8252C3B0871744CBA42F15CA00FFBCA7`, Canary mit 5000 Zeilen lesbar.

Automatisch: kein Skript. Hinweis: OFFLINE-Operationen sind laut Oracle-Doku nicht als
Rekeying-Verfahren vorgesehen - dokumentiert ist dafuer nur `ONLINE REKEY`. Entgegen der
urspruenglichen Protokollannahme ist `ONLINE REKEY` in Oracle Database Free 26ai technisch
verfuegbar, lizenzrechtlich aber ein Enterprise-Edition-Merkmal. Gemessen in Phase 5a.

### 5.7 Blockvergleich gegen die Prod-Baseline

Der zentrale Befund dieses Pfads.

```bash
python3 scripts/tde-verify/block_fingerprint.py fingerprint \
  data/odbencdev/oradata/FREE/ODBENCPROD/<users_datafile>.dbf \
  --block-size 8192 --out data/xchange/evidence/variant_d/users.fp

python3 scripts/tde-verify/block_fingerprint.py compare \
  data/xchange/evidence/baseline/users.fp \
  data/xchange/evidence/variant_d/users.fp \
  --label-a baseline --label-b variant_d
```

Erwartet: 1406 identisch, 1155 geaendert. Die abweichenden Bloecke sind 0, 1 und 1408 bis 2560.
Die Bloecke 2 bis 1407 einschliesslich aller 313 Canary-Datenbloecke sind byteidentisch zur
Quelle.

Automatisch: `scripts/tde-verify/tde_evidence.sh --compare baseline variant_d`

### 5.8 Alte und neue Schluesselspuren im Datafile pruefen

```bash
python3 scripts/tde-verify/block_fingerprint.py find-hex \
  data/odbencdev/oradata/FREE/ODBENCPROD/<users_datafile>.dbf \
  BAD537ADDD695BEE7A29F6F27B65A03D6F195CCE3388AD0119D718087A8AFA55 --block-size 8192

python3 scripts/tde-verify/block_fingerprint.py find-hex \
  data/odbencdev/oradata/FREE/ODBENCPROD/<users_datafile>.dbf \
  8FBDA2A856F5128B5C2D27F51A9B769608D1CA60185320DD67861E148C303E41 --block-size 8192
```

Erwartet: Prods gewrappter TEK und Prods `MASTERKEYID` sind physisch nicht mehr auffindbar. Der
neue Dev-TEK liegt an derselben Header-Stelle, Offset 8977.

Automatisch: kein Skript.

### 5.9 Zyklus kontrolliert wiederholen

Prueft, ob das Ergebnis stabil ist oder vom Zufall lebt.

```bash
docker exec -i odbencdev sqlplus -S / as sysdba <<'SQL'
WHENEVER SQLERROR CONTINUE
ALTER SESSION SET CONTAINER = ODBENCPROD;
ALTER TABLESPACE users OFFLINE;
ALTER TABLESPACE users ENCRYPTION OFFLINE DECRYPT;
ALTER TABLESPACE users ONLINE;
EXIT
SQL
```

Dazwischen Schritt 5.2 (Klartext-Scan, 313 Treffer erwartet), dann Schritt 5.6 erneut und
danach 5.7.

Erwartet: erneut 1406 identisch und 1155 geaendert, `KEY_VERSION 5`, gewrappter TEK unveraendert
`8FBDA2A8...3E41`. Identisches Chiffrat bei identischem Inhalt und identischer Blockadresse
bedeutet identischer TEK - der Tablespace-Encryption-Key uebersteht den Zyklus, nur seine
Verpackung wechselt.

Automatisch: kein Skript.

### 5.10 Variante F: `_db_discard_lost_masterkey` - der Pfad, der die Kette bricht

Variante D dreht den Master Key, laesst das Chiffrat der Nutzdaten aber unveraendert: nur die
Verpackung des TEK wechselt. Variante F ist der einzige gemessene RMAN-nahe Weg, der wirklich
neues Schluesselmaterial erzeugt. Er tut das ueber den Hidden Parameter
`_db_discard_lost_masterkey`, mit dem die PDB die Handles auf den verlorenen Quellschluessel
verwirft und einen eigenen setzen kann.

**Das ist ausdruecklich nicht die Empfehlung.** Der Parameter ist undokumentiert und nach
Praxisvorgabe nur nach Freigabe durch Oracle Support einzusetzen. Er ist hier gemessen, damit
belegt ist, was passiert - nicht als Betriebsverfahren. Tragfaehig sind der PDB-Klon und
`ONLINE REKEY` (Phase 5a).

Automatisch laeuft die Variante als `scripts/tde-verify/tests/60_variant_f.sh --yes`.

Weitere Warnungen aus dem Lauf: nach dem `SET KEY` steht im Alert Log "replacing lost SYSAUX key
with new database key due to prior wallet deletion". Auf Produktionsdaten koennen SYSAUX-Bloecke
danach als korrupt erscheinen. Zwischen Schritt 5.10.4 und 5.10.7 darf die PDB nicht geoeffnet
werden - die Prod-MEKs sind dann weg und der Schluessel noch nicht gesetzt.

#### 5.10.1 Ziel zuruecksetzen und Variante-A-Basis herstellen

Variante F setzt auf einem vollstaendigen Klon auf: `USERS` muss verschluesselt und unter dem
Quellschluessel lesbar sein.

```bash
make reset SERVICE=odbencdev
make up-odbencdev
make logs-odbencdev

scripts/tde-verify/tde_clone.sh --variant a --dbid 1515066983 \
  --cf-piece <cf_autobackup> --delete --yes
```

Erwartet: der Klon steht wie am Ende von Phase 2. Manuelle Entsprechung: die Schritte 2.1 bis
2.11 in unveraenderter Reihenfolge.

Automatisch: Phase 1 in `60_variant_f.sh`.

#### 5.10.2 USERS offline entschluesseln und das Ergebnis pruefen

Der Tablespace kommt aus Variante A als `READ ONLY` und muss fuer die Offline-Konvertierung erst
`READ WRITE` und dann `OFFLINE` sein - sonst scheitert der Befehl mit ORA-28440, "file is in
use".

```bash
docker exec -i odbencdev sqlplus -S / as sysdba <<'SQL'
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SESSION SET CONTAINER = ODBENCPROD;
ALTER TABLESPACE USERS READ WRITE;
ALTER TABLESPACE USERS OFFLINE NORMAL;
ALTER TABLESPACE USERS ENCRYPTION OFFLINE DECRYPT;
ALTER TABLESPACE USERS ONLINE;
ALTER SYSTEM CHECKPOINT;
SELECT COUNT(*) AS enc_ts_remaining FROM v$encrypted_tablespaces;
EXIT
SQL
```

Erwartet: `ENC_TS_REMAINING = 0`. Ist der Wert groesser als 0, hier abbrechen - der Discard
setzt voraus, dass kein verschluesselter Tablespace mehr existiert.

Automatisch: Phase 2 in `60_variant_f.sh`, samt Gate, das den Lauf bei einem Wert ungleich 0
abbricht.

#### 5.10.3 Undo-Tablespace der PDB tauschen

Dieser Schritt ist zwingend und wird leicht uebersehen. `OFFLINE DECRYPT` macht die Nutzdaten
lesbar, die Undo-Saetze aus der Zeit davor haengen aber weiter am Quellschluessel. Sobald
Schritt 5.10.4 den Keystore entfernt und Schritt 5.10.7 die Handles verwirft, sind diese
Undo-Bloecke nicht mehr entschluesselbar: die naechste Tablespace-Operation stirbt mit ORA-28304,
"Oracle encrypted block is corrupt" - auf dem **Undo-Datafile**, nicht auf `USERS`.

`V$ENCRYPTED_TABLESPACES` meldet dabei korrekt 0 Zeilen, Undo taucht dort nicht auf. Das Gate aus
5.10.2 sieht den Rest also nicht. Genau das ist die praktische Form der MOS-Vorbedingung "nur
zulaessig, wenn nichts mehr verschluesselt ist". Ob der Fehler zuschlaegt, haengt davon ab,
welche Undo-Bloecke gerade wiederverwendet werden - ein frueherer Lauf blieb deshalb gruen. Ein
frisches Undo entfernt den Rueckstand, statt sich auf diesen Zufall zu verlassen.

```bash
docker exec -i odbencdev sqlplus -S / as sysdba <<'SQL'
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SESSION SET CONTAINER = ODBENCPROD;
CREATE UNDO TABLESPACE UNDOTBS_CLEAN DATAFILE SIZE 100M AUTOEXTEND ON;
ALTER SYSTEM SET undo_tablespace='UNDOTBS_CLEAN' SCOPE=BOTH;
EXIT
SQL

docker exec -i odbencdev sqlplus -S / as sysdba <<'SQL'
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SESSION SET CONTAINER = ODBENCPROD;
DROP TABLESPACE UNDOTBS1 INCLUDING CONTENTS AND DATAFILES;
EXIT
SQL

docker exec -i odbencdev sqlplus -S / as sysdba <<'SQL'
SET LINESIZE 200 PAGESIZE 100
ALTER SESSION SET CONTAINER = ODBENCPROD;
SELECT tablespace_name, status, contents FROM dba_tablespaces WHERE contents = 'UNDO';
EXIT
SQL
```

Erwartet: am Ende genau ein Undo-Tablespace, `UNDOTBS_CLEAN`, `STATUS ONLINE`. Das `DROP`
schlaegt fehl, solange noch Undo-Segmente aktiv sind - dann einige Sekunden warten und
wiederholen. Laesst sich `UNDOTBS1` nicht loeschen, hier abbrechen.

Automatisch: Phase 2b in `60_variant_f.sh`, mit sechs Versuchen im Abstand von 10 Sekunden und
Abbruch, wenn das `DROP` nicht durchgeht.

#### 5.10.4 Prod-Keystore entfernen

Der Quell-Keystore wird zur Seite gelegt, nicht geloescht, und das Keystore-Verzeichnis muss
danach wirklich leer sein: ein liegengebliebenes `cwallet.sso` oder `ewallet.p12` laesst das
spaetere `CREATE KEYSTORE` mit ORA-46630 scheitern.

```bash
docker exec -i odbencdev bash -s <<'INNER'
set -e
ks_dir=/opt/oracle/dbconfig/FREE/wallet/tde
aside=/opt/oracle/xchange/wallet_prod_used_f
if [ -d "${ks_dir}" ]; then
    rm -rf "${aside}"
    mv "${ks_dir}" "${aside}" || { echo "ERROR: could not move ${ks_dir} aside" >&2; exit 1; }
    echo "prod keystore moved to ${aside}"
fi
mkdir -p "${ks_dir}"
if [ -n "$(ls -A "${ks_dir}")" ]; then
    echo "ERROR: ${ks_dir} is not empty:" >&2
    ls -la "${ks_dir}" >&2
    exit 1
fi
echo "fresh empty keystore directory: ${ks_dir}"
INNER
```

Erwartet: `prod keystore moved to ...` und `fresh empty keystore directory: ...`. Quell- und
Ablageverzeichnis liegen auf verschiedenen Bind-Mounts, `mv` kopiert und loescht also. Ein
Ueberrest aus einem frueheren Lauf liess `mv` mit "Directory not empty" scheitern, waehrend der
Ablauf weiterlief - der Prod-Keystore blieb liegen und die folgenden Schritte benutzten still
weiter die Prod-Schluessel. Deshalb die Leerpruefung.

Automatisch: Phase 3 in `60_variant_f.sh`.

#### 5.10.5 Instanz neu starten

Ein Auto-Login-Keystore laesst sich nicht per SQL schliessen, `ADMINISTER KEY MANAGEMENT SET
KEYSTORE CLOSE` endet mit ORA-28389. Der Speicherkontext ueberlebt zudem das Loeschen der
Dateien - deshalb scheiterte das Oeffnen weiter mit ORA-28354 und `SET KEY` mit ORA-28417. Nur
ein Instanz-Neustart entfernt ihn. Er ist an dieser Stelle unbedenklich, weil das Gate aus
5.10.2 belegt hat, dass kein verschluesselter Tablespace mehr existiert.

```bash
docker exec -i odbencdev sqlplus -S / as sysdba <<'SQL'
WHENEVER SQLERROR EXIT SQL.SQLCODE
SHUTDOWN IMMEDIATE
STARTUP
WHENEVER SQLERROR CONTINUE
ALTER PLUGGABLE DATABASE ALL OPEN;
SET LINESIZE 200 PAGESIZE 100
SELECT con_id, status, wallet_type FROM v$encryption_wallet ORDER BY con_id;
EXIT
SQL
```

Erwartet: die Instanz kommt hoch, `V$ENCRYPTION_WALLET` zeigt keinen offenen Auto-Login-Keystore
mehr.

Automatisch: Schritt "Restart instance to drop the auto-login keystore from memory" in
`60_variant_f.sh`.

#### 5.10.6 Neuen Keystore anlegen und oeffnen

`CREATE KEYSTORE` steht hier ohne Pfadangabe: `WALLET_ROOT` ist konfiguriert, Oracle leitet
`WALLET_ROOT/tde` selbst ab. Mit explizitem Pfad endet der Befehl mit ORA-46633. Es ist dieselbe
Syntax wie in `config/common/scripts/csenc_swkeystore.sql`.

```bash
docker exec odbencdev bash -c '
KSPWD=$(cat /opt/oracle/dbconfig/FREE/wallet/wallet_pwd.txt)
sqlplus -S / as sysdba <<SQL 2>&1 | grep -viE "identified by"
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET LINESIZE 256 PAGESIZE 100
ADMINISTER KEY MANAGEMENT CREATE KEYSTORE IDENTIFIED BY "${KSPWD}";
WHENEVER SQLERROR CONTINUE
ADMINISTER KEY MANAGEMENT SET KEYSTORE OPEN IDENTIFIED BY "${KSPWD}" CONTAINER=ALL;
COLUMN key_id FORMAT A56
SELECT con_id, key_id, keystore_type, origin FROM v\$encryption_keys ORDER BY con_id;
EXIT
SQL
'
```

Erwartet: `keystore altered`, danach ein leerer Schluesselbestand - kein Prod-MEK mehr. Ein
ORA-28354 beim `SET KEYSTORE OPEN` ist tolerierbar: der Keystore ist dann bereits offen, der
Zielzustand also erreicht. Das Passwort wird im Container gelesen und erscheint in keinem
Host-Befehl; die Ausgabe wird gefiltert.

Kein `SET KEY` in `CDB$ROOT`. Gemessen: der Befehl scheitert an dieser Stelle mit ORA-28374,
"typed master key not found in wallet", weil die CDB weiterhin die MEK-ID der Quelle fuehrt. Eine
Datenbank, die ihren Master Key verloren hat, kann nicht einfach einen neuen uebernehmen - genau
dafuer ist der Hidden Parameter da, und der ist nur in der PDB setzbar. Der Schluessel wird
deshalb in 5.10.7 in der PDB gesetzt; fuer Variante F genuegt das.

Automatisch: Phase 3 in `60_variant_f.sh`.

#### 5.10.7 In der PDB: Handles verwerfen und eigenen Schluessel setzen

`_db_discard_lost_masterkey` muss in der PDB mit `SCOPE=MEMORY` gesetzt werden. Auf CDB-Ebene
endet `SCOPE=MEMORY` mit ORA-28355; `SCOPE=SPFILE` plus Neustart wird still nicht wirksam. Nur
der Weg in der PDB funktioniert.

```bash
docker exec odbencdev bash -c '
KSPWD=$(cat /opt/oracle/dbconfig/FREE/wallet/wallet_pwd.txt)
sqlplus -S / as sysdba <<SQL 2>&1 | grep -viE "identified by"
WHENEVER SQLERROR CONTINUE
SET LINESIZE 256 PAGESIZE 100
ALTER SESSION SET CONTAINER = ODBENCPROD;
ALTER SYSTEM SET "_db_discard_lost_masterkey"=TRUE SCOPE=MEMORY;
ADMINISTER KEY MANAGEMENT SET KEY FORCE KEYSTORE IDENTIFIED BY "${KSPWD}" WITH BACKUP;
COLUMN key_id FORMAT A56
SELECT con_id, key_id, keystore_type, origin FROM v\$encryption_keys ORDER BY con_id;
SELECT COUNT(*) AS prod_keys_remaining FROM v\$encryption_keys WHERE origin != '"'"'LOCAL'"'"';
EXIT
SQL
'
```

Erwartet: `System altered`, danach `keystore altered` - `SET KEY` geht durch, obwohl der
Prod-MEK fehlt. `PROD_KEYS_REMAINING` ist 0. Im Alert Log steht die erwartete Warnung zum
ersetzten SYSAUX-Schluessel.

Automatisch: Phase 4+5 in `60_variant_f.sh`.

#### 5.10.8 USERS offline neu verschluesseln

```bash
docker exec -i odbencdev sqlplus -S / as sysdba <<'SQL'
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SESSION SET CONTAINER = ODBENCPROD;
ALTER TABLESPACE USERS OFFLINE NORMAL;
ALTER TABLESPACE USERS ENCRYPTION OFFLINE ENCRYPT;
ALTER TABLESPACE USERS ONLINE;
ALTER SYSTEM CHECKPOINT;
SELECT tablespace_name, status, encrypted FROM dba_tablespaces WHERE tablespace_name = 'USERS';
SELECT RAWTOHEX(masterkeyid), RAWTOHEX(encryptedkey), key_version
  FROM v$encrypted_tablespaces
 WHERE ts# = (SELECT ts# FROM v$tablespace
               WHERE name = 'USERS' AND con_id = sys_context('userenv','con_id'));
EXIT
SQL
```

Erwartet: `ENCRYPTED YES`, `MASTERKEYID C7A38A0C0653495F882671BF2ED974A3`, gewrappter Schluessel
`A0BB56AF4790B1C12B2F21D8263CBBE470EA04CDCBE7DCE5A062F6C177D8E2AC` - beides abweichend von der
Baseline des Laufs.

Automatisch: Phase 6 in `60_variant_f.sh`.

#### 5.10.9 Blockvergleich gegen die Baseline

```bash
python3 scripts/tde-verify/block_fingerprint.py fingerprint \
  data/odbencdev/oradata/FREE/ODBENCPROD/<users_datafile>.dbf \
  --block-size 8192 --out data/xchange/evidence/variant_f/users.fp

python3 scripts/tde-verify/block_fingerprint.py compare \
  data/xchange/evidence/baseline/users.fp \
  data/xchange/evidence/variant_f/users.fp \
  --label-a baseline --label-b variant_f
```

Erwartet: 0 der 313 Canary-Datenbloecke sind identisch, alle 313 sind geaendert.

Das ist die Gegenprobe zu Variante D. Beide fahren dasselbe
`ALTER TABLESPACE ... ENCRYPTION OFFLINE ENCRYPT`; der einzige Unterschied ist der erneuerte
Database Key. Variante D reproduzierte das Quell-Chiffrat trotz neuem MEK byteidentisch - wenn
sich das Chiffrat hier aendert, stammt das Tablespace-Schluesselmaterial nachweislich aus dem
Database Key und nicht aus dem MEK. Ohne diese Pruefung stuende das Urteil allein auf dem
gespeicherten Schluesselwert, und den aendert ein blosses Re-wrap ebenso.

Automatisch: `compare_evidence baseline variant_f` und `compare_canary_blocks` in
`60_variant_f.sh`. Der Test wertet nur dann PASS, wenn der TEK gewechselt hat **und** das
Canary-Chiffrat mitgewechselt ist. Ein neuer TEK bei unveraendertem Chiffrat gilt als Re-wrap
und wird als FAIL gemeldet.

#### 5.10.10 Parameter zur Laufzeit pruefen

```bash
docker exec -i odbencdev sqlplus -S / as sysdba <<'SQL'
SET LINESIZE 200 PAGESIZE 100
COLUMN ksppinm FORMAT A40
COLUMN ksppstvl FORMAT A20
SELECT p.ksppinm, v.ksppstvl
  FROM x$ksppi p JOIN x$ksppsv v ON p.indx = v.indx
 WHERE p.ksppinm = '_db_discard_lost_masterkey';
EXIT
SQL
```

Automatisch: `config/common/scripts/ssenc_info.sql` fragt den Parameter bereits in der
Hidden-Parameter-Liste ab.

#### 5.10.11 Messwerte aus dem E2E-Lauf

Werte aus dem durchgehenden Lauf vom 2026-09-06 (`tasks/e2e-facts.md`).

<!-- markdownlint-disable MD013 MD060 -->
| Messwert | Baseline (Schritt 10) | nach Variante F |
|---|---|---|
| `MASTERKEYID` | `EC574AF166934D45AB5AC1F2267A297A` | `C7A38A0C0653495F882671BF2ED974A3` |
| `ENCRYPTEDKEY` | `059EFEB1BB6D72140B68FD768F80105B37BB912E84E6273E82227A027FD830F3` | `A0BB56AF4790B1C12B2F21D8263CBBE470EA04CDCBE7DCE5A062F6C177D8E2AC` |
| Canary-Bloecke | - | 0 identisch / 313 geaendert |
<!-- markdownlint-restore -->

Aussage: Variante F erzeugt neues Schluesselmaterial und bricht die Kette zur Quelle. Der Preis
ist ein undokumentierter Parameter, ein Keystore-Verlust als Ausgangslage und ein Ablauf, in dem
mehrere Zwischenzustaende die Datenbank unbrauchbar machen koennen. Fuer den Regelbetrieb bleiben
der PDB-Klon und `ONLINE REKEY` die tragfaehigen Wege.

## Phase 5a - Variante G: ALTER TABLESPACE ... ENCRYPTION ONLINE REKEY

Diese Phase ist nachtraeglich eingefuegt und behaelt die Nummerierung der folgenden Phasen bei.
Automatisch laeuft sie als `scripts/tde-verify/tests/70_variant_g.sh --yes`.

Variante G ist die Gegenprobe zu Variante D. Dort blieb das Canary-Chiffrat trotz neuem MEK
byteidentisch, weil nur die Verpackung des TEK wechselte. `ONLINE REKEY` muss das Gegenteil tun:
neues TEK-Material erzeugen und die Bloecke neu schreiben. Die Online-Konvertierung behaelt die
ROWIDs, die Canary-Zeilen liegen danach also an denselben Blockadressen - erst dadurch ist der
Blockvergleich ueberhaupt aussagekraeftig.

**Lizenzhinweis:** `ONLINE REKEY` ist in Oracle Database Free 26ai technisch nicht gesperrt,
lizenzrechtlich aber ein Enterprise-Edition-Merkmal. Der Lauf im Lab ist eine Messung, keine
Freigabe fuer den Einsatz unter einer Free- oder Standard-Edition-Lizenz.

### 5a.1 Ziel zuruecksetzen und Variante-A-Basis herstellen

`ONLINE REKEY` braucht einen verschluesselten `USERS`-Tablespace im Ziel. Den liefert Variante A.

```bash
make reset SERVICE=odbencdev
make up-odbencdev
make logs-odbencdev

scripts/tde-verify/tde_clone.sh --variant a --dbid 1515066983 \
  --cf-piece <cf_autobackup> --delete --yes
```

Erwartet: der Klon steht wie am Ende von Phase 2, `USERS` ist verschluesselt und `READ ONLY`.

Manuelle Entsprechung: die Schritte 2.1 bis 2.11 in unveraenderter Reihenfolge.

Der Quell-Autobackup-Name muss explizit mitgegeben werden. Ohne `--cf-piece` faellt der Klon auf
`FROM AUTOBACKUP` zurueck und zieht die neueste Controlfile - die kennt zu diesem Zeitpunkt
bereits die PDBs aus den spaeteren Schritten, waehrend das Backup aus Schritt 1.11 aelter ist.
RMAN bricht dann mit RMAN-06023 fuer nie gesicherte Datafiles ab.

### 5a.2 Schluesselkette vor dem Rekey festhalten

Der Vorher-Wert entscheidet spaeter, ob sich wirklich etwas geaendert hat.

```bash
docker exec -i odbencdev sqlplus -S / as sysdba <<'SQL'
SET LINESIZE 256 PAGESIZE 100
ALTER SESSION SET CONTAINER = ODBENCPROD;
SELECT RAWTOHEX(masterkeyid), RAWTOHEX(encryptedkey), key_version, ciphermode
  FROM v$encrypted_tablespaces
 WHERE ts# = (SELECT ts# FROM v$tablespace
               WHERE name = 'USERS' AND con_id = sys_context('userenv','con_id'));
EXIT
SQL
```

Erwartet: `MASTERKEYID` und `ENCRYPTEDKEY` identisch zur Quelle - Variante A veraendert sie
nicht. `KEY_VERSION 1`.

Automatisch: `get_encryptedkey` und die `KEY_VERSION`-Abfrage in `70_variant_g.sh`. Das Skript
bricht ab, wenn die `KEY_VERSION`-Abfrage leer zurueckkommt - ein leerer Wert wuerde sonst in den
Vergleich laufen und eine gescheiterte Messung als PASS ausweisen.

### 5a.3 USERS auf READ WRITE setzen

Aus dem Restore kommt der Tablespace `READ ONLY` zurueck, weil Schritt 1.6 ihn so gesetzt hat.
`ONLINE REKEY` verlangt `READ WRITE`.

```bash
docker exec -i odbencdev sqlplus -S / as sysdba <<'SQL'
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SESSION SET CONTAINER = ODBENCPROD;
ALTER TABLESPACE USERS READ WRITE;
SELECT tablespace_name, status FROM dba_tablespaces WHERE tablespace_name = 'USERS';
EXIT
SQL
```

Erwartet: `STATUS ONLINE`.

Automatisch: Phase 2 in `70_variant_g.sh`.

### 5a.4 ONLINE REKEY ausfuehren

```bash
docker exec -i odbencdev sqlplus -S / as sysdba <<'SQL'
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SESSION SET CONTAINER = ODBENCPROD;
ALTER TABLESPACE USERS ENCRYPTION ONLINE REKEY;
SELECT tablespace_name, encrypted FROM dba_tablespaces WHERE tablespace_name = 'USERS';
SELECT RAWTOHEX(masterkeyid), RAWTOHEX(encryptedkey), key_version, ciphermode
  FROM v$encrypted_tablespaces
 WHERE ts# = (SELECT ts# FROM v$tablespace
               WHERE name = 'USERS' AND con_id = sys_context('userenv','con_id'));
EXIT
SQL
```

Erwartet: der Befehl laeuft durch, `ENCRYPTED YES`, `KEY_VERSION` von 1 auf 2, `ENCRYPTEDKEY`
weicht sowohl vom Vorher-Wert als auch vom Quellwert ab.

`ONLINE REKEY` legt ein neues Datafile auf Platte an und entfernt das alte danach selbst. Der
Dateiname bleibt derselbe, der Fingerabdruckvergleich sieht deshalb alle belegten Bloecke als
geaendert.

Automatisch: Phase 3 in `70_variant_g.sh`.

### 5a.5 Blockvergleich gegen die Baseline

```bash
python3 scripts/tde-verify/block_fingerprint.py fingerprint \
  data/odbencdev/oradata/FREE/ODBENCPROD/<users_datafile>.dbf \
  --block-size 8192 --out data/xchange/evidence/variant_g/users.fp

python3 scripts/tde-verify/block_fingerprint.py compare \
  data/xchange/evidence/baseline/users.fp \
  data/xchange/evidence/variant_g/users.fp \
  --label-a baseline --label-b variant_g
```

Erwartet: 0 der 313 Canary-Datenbloecke sind identisch, alle 313 sind geaendert - das genaue
Gegenteil von Variante A, C und D.

Automatisch: `compare_evidence baseline variant_g` und `compare_canary_blocks` in
`70_variant_g.sh`. Der Test wertet nur dann PASS, wenn der TEK gewechselt hat **und** das
Canary-Chiffrat mitgewechselt ist. Ein neuer TEK bei unveraendertem Chiffrat gilt als
widerspruechlich und wird als FAIL gemeldet.

### 5a.6 Entzugstest nach Variante G

Prueft, ob das neue Schluesselmaterial die Abhaengigkeit vom Quell-MEK loest. Ablauf wie Schritt
7.1: dev-eigenes Wallet zurueckspielen, Instanz neu starten.

Erwartet: die Datenbank oeffnet nicht, sie bleibt `MOUNTED` und meldet ORA-28374. Ohne den
Quell-MEK ist nicht ein einzelner Tablespace unlesbar, sondern die ganze Datenbank unbrauchbar -
der Database Key haengt weiter am alten Material.

Automatisch: `scripts/tde-verify/tests/90_withdrawal_test.sh`.

### 5a.7 Messwerte aus dem E2E-Lauf

Werte aus dem durchgehenden Lauf vom 2026-09-06 (`tasks/e2e-facts.md`).

<!-- markdownlint-disable MD013 MD060 -->
| Messwert | Ergebnis |
|---|---|
| `KEY_VERSION` | 1 -> 2 |
| Canary-Bloecke | 0 identisch / 313 geaendert |
| Entzugstest | Datenbank oeffnet nicht, bleibt `MOUNTED` mit ORA-28374 |
<!-- markdownlint-restore -->

Aussage: `ONLINE REKEY` erzeugt neues Schluesselmaterial. Es ist damit der einzige der
gemessenen RMAN- und Tablespace-Wege, der das Chiffrat der Nutzdaten wirklich austauscht.

## Phase 6 - Positivkontrolle: erkennt die Methode einen TEK-Wechsel?

### 6.1 Zwei frische verschluesselte Tablespaces in der Quelle anlegen

Identische DDL, damit der einzige Unterschied das TEK-Material ist.

```bash
docker exec -i odbencprod sqlplus -S / as sysdba <<'SQL'
ALTER SESSION SET CONTAINER = ODBENCPROD;
CREATE BIGFILE TABLESPACE ctrl_enc_a DATAFILE SIZE 20M AUTOEXTEND ON
  ENCRYPTION USING 'AES256' DEFAULT STORAGE (ENCRYPT);
CREATE BIGFILE TABLESPACE ctrl_enc_b DATAFILE SIZE 20M AUTOEXTEND ON
  ENCRYPTION USING 'AES256' DEFAULT STORAGE (ENCRYPT);
EXIT
SQL
```

Erwartet: beide `ENCRYPTED YES`, unterschiedliche gewrappte TEKs unter derselben
`MASTERKEYID 8A27589796A248BE95222E59407FF962`.

Automatisch: kein Skript.

### 6.2 Identischen Canary-Inhalt in beide schreiben

```bash
docker exec -i odbencprod sqlplus -S / as sysdba <<'SQL'
ALTER SESSION SET CONTAINER = ODBENCPROD;
@/opt/oracle/common/scripts/csenc_canary.sql SCOTT CTRL_ENC_A OEHRLI-CANARY-01 5000 CANARY_CTRL_A
@/opt/oracle/common/scripts/csenc_canary.sql SCOTT CTRL_ENC_B OEHRLI-CANARY-01 5000 CANARY_CTRL_B
EXIT
SQL
```

Erwartet: beide belegen die Bloecke 779 bis 1279 mit je 313 belegten Bloecken.

Automatisch: derselbe Skriptaufruf.

### 6.3 Gewrappte TEKs vergleichen

```bash
docker exec -i odbencprod sqlplus -S / as sysdba <<'SQL'
ALTER SESSION SET CONTAINER = ODBENCPROD;
@/opt/oracle/common/scripts/ssenc_keyproof.sql
EXIT
SQL
```

Erwartet:

- `CTRL_ENC_A`: `6B6A512AC8BFAEF411C5F6C1BAEB8845E618E0B6F9C66F7DD1A3361982D83B07`
- `CTRL_ENC_B`: `F29E623B3D421496F54A8BE21F80E35DF2CC3739DBEBEC04D4390E7C0B491C79`
- beide unter `MASTERKEYID 8A27589796A248BE95222E59407FF962`

Automatisch: `tde_evidence.sh` mit `-t CTRL_ENC_A` bzw. `-t CTRL_ENC_B`.

### 6.4 Blockvergleich der beiden Kontroll-Datafiles

```bash
python3 scripts/tde-verify/block_fingerprint.py fingerprint \
  data/odbencprod/oradata/FREE/ODBENCPROD/<ctrl_enc_a_datafile>.dbf \
  --block-size 8192 --out data/xchange/evidence/ctrl_a/ctrl.fp

python3 scripts/tde-verify/block_fingerprint.py fingerprint \
  data/odbencprod/oradata/FREE/ODBENCPROD/<ctrl_enc_b_datafile>.dbf \
  --block-size 8192 --out data/xchange/evidence/ctrl_b/ctrl.fp

python3 scripts/tde-verify/block_fingerprint.py compare \
  data/xchange/evidence/ctrl_a/ctrl.fp \
  data/xchange/evidence/ctrl_b/ctrl.fp \
  --label-a ctrl_enc_a --label-b ctrl_enc_b
```

Erwartet: von den 501 Bloecken im Bereich 779 bis 1279 unterscheiden sich 367, identisch sind
134. Damit ist die Methode nachweislich sensitiv fuer einen TEK-Wechsel - der Nullbefund in
Phase 2 und Phase 5 ist keine Blindheit des Messverfahrens.

Automatisch: `scripts/tde-verify/tde_evidence.sh --compare ctrl_a ctrl_b`

## Phase 7 - Entzugstests

### 7.1 Dev-eigenes Wallet zurueckspielen und neu starten

Entzieht dem Ziel den Prod-Schluessel. Erst wenn der Canary danach lesbar ist, ist
kryptografische Unabhaengigkeit belegt.

```bash
docker exec odbencdev bash -c \
  'rm -rf /opt/oracle/dbconfig/FREE/wallet/tde /opt/oracle/dbconfig/FREE/wallet/tde_seps \
   && cp -a /opt/oracle/xchange/wallet_dev_pristine/. /opt/oracle/dbconfig/FREE/wallet/'
docker exec -i odbencdev sqlplus -S / as sysdba <<'SQL'
WHENEVER SQLERROR CONTINUE
SHUTDOWN ABORT;
STARTUP;
EXIT
SQL
```

Erwartet: nur der Dev-MEK `AWZuopGe2EGHqnGxulapWxw...` mit `ORIGIN LOCAL` sichtbar.

Automatisch: kein Skript - der Zustandswechsel ist bewusst manuell.

### 7.2 Canary lesen

```bash
docker exec -i odbencdev sqlplus -S / as sysdba <<'SQL'
ALTER SESSION SET CONTAINER = ODBENCPROD;
@/opt/oracle/common/scripts/ssenc_canary.sql SCOTT OEHRLI-CANARY-01 CANARY_TDE
EXIT
SQL
```

Erwartet nach Variante A: ORA-28374 "typed master key not found in wallet". Das Skript
verwendet absichtlich kein `WHENEVER SQLERROR EXIT`, damit der Fehler als Messergebnis im Log
bleibt.

Automatisch: derselbe Skriptaufruf, orchestriert je Variante.

### 7.3 Schluesselkette nach dem Entzug festhalten

```bash
docker exec -i odbencdev sqlplus -S / as sysdba <<'SQL'
@/opt/oracle/common/scripts/ssenc_keyproof.sql
EXIT
SQL
```

Erwartet: kein Prod-Schluessel mehr im Keystore. Der dokumentierte Ausweg zurueck waere
`MERGE KEYSTORE` aus einem Backup-Wallet oder `IMPORT KEYS` aus einem Export.

Automatisch: `tde_evidence.sh` mit einem eigenen Label je Entzugstest.

## Phase 8 - Aufraeumen und Reset

### 8.1 Beide Services zuruecksetzen

Destruktiv - vernichtet alle Daten beider Lab-Services.

```bash
make reset SERVICE=odbencprod
make reset SERVICE=odbencdev
```

Erwartet: Container und Volumes entfernt, `data/odbencprod/` und `data/odbencdev/` geloescht.

Automatisch: `make reset-odbencprod` und `make reset-odbencdev` sind die Kurzformen.

### 8.2 Austausch-Mount leeren

Entfernt Backupsets, Wallet-Kopien, Quarantaene-Redologs und Evidence-Saetze.

```bash
rm -rf data/xchange/backup data/xchange/wallet_prod data/xchange/wallet_dev_pristine \
       data/xchange/stale_redo_odbencdev data/xchange/evidence
```

Erwartet: `data/xchange` ist leer. Vorher pruefen, ob die Evidence-Saetze noch gebraucht werden -
sie sind die Belege des Protokolls.

Automatisch: kein Skript - bewusst manuell, weil hier Belege verloren gehen.

### 8.3 Lauf auf gruener Wiese wiederholen

Der Reproduzierbarkeitsnachweis: aus dem committeten Stand neu aufsetzen und die Phasen 1 bis 7
ausschliesslich ueber die Skripte durchlaufen, ohne Zwischenkorrekturen.

```bash
make up-odbencprod
make up-odbencdev
make logs-odbencprod
```

Erwartet: keine ORA- oder SP2-Fehler in den Setup-Logs, insbesondere kein SP2-0734 und kein
SP2-0042. Danach die Messwerte gegen den Abschnitt "Sollwerte zum Abgleich" pruefen. Erst dann
gilt das Protokoll als abgenommen.

Automatisch: die Phasen 1 bis 7 ueber `tde_evidence.sh` und `tde_clone.sh`.

## Sollwerte zum Abgleich

### Baseline odbencprod

<!-- markdownlint-disable MD013 MD060 -->
| Messwert | Sollwert |
|---|---|
| DBID Quelle | 1515066983 |
| DBID Ziel vor dem Klon | 1515067722 |
| `LOG_MODE` Quelle | ARCHIVELOG |
| Keystore-Modus | UNITED, ein Keystore-Verzeichnis `tde` plus `tde_seps` und `backups` |
| Tablespace `USERS` | bigfile, AES256, `CIPHERMODE` XTS, TS# 6, 2560 Bloecke, 20971520 Byte |
| Datafile `USERS` auf Platte | 20979712 Byte, 2561 Bloecke bei 8192 Byte Blockgroesse |
| `MASTERKEYID` | 8A27589796A248BE95222E59407FF962 |
| `KEY_VERSION` | 1 |
| gewrappter TEK | BAD537ADDD695BEE7A29F6F27B65A03D6F195CCE3388AD0119D718087A8AFA55 |
| MEK `CDB$ROOT` | AbyhIcXQQk+XiBYrKzrI3FY..., ORIGIN LOCAL, con_id 1 |
| MEK PDB | AYonWJeWoki+lSIuWUB/+WI..., ORIGIN LOCAL, con_id 4 |
| Canary `CANARY_TDE` | 5000 Zeilen, Segment 384 Bloecke / 3145728 Byte, 313 belegte Bloecke, Bereich 979 bis 1407 |
| Kontrollgruppe `CANARY_PLAIN_TAB` | 5000 Zeilen, 313 Bloecke, Bereich 779 bis 1279 |
| Klartext-Scan verschluesselt | 0 Treffer |
| Klartext-Scan unverschluesselt | 313 Treffer ab Block 779 |
| gewrappter TEK physisch | Offset 8977 = Block 1 Byte 785, genau 1 Treffer |
| `MASTERKEYID` physisch | Offset 9025 = Block 1 Byte 833, genau 1 Treffer |
| Database Key | RAW(48), 9FA346CD92BF77F2967675FD236BF54B56A5834859447E5CA76D9BE659B724DF plus Nullbytes |
| Controlfile-Autobackup | cf_c-1515066983-20260903-00 |
| Laufzeit erstes Backup-Set beim normalen Restore | 3 Sekunden |
<!-- markdownlint-restore -->

### Je Variante

<!-- markdownlint-disable MD013 MD060 -->
| Variante | Sollwert |
|---|---|
| A - normaler RESTORE | Restore ohne offenen Keystore erfolgreich. `MASTERKEYID`, `KEY_VERSION` und gewrappter TEK identisch zur Quelle, TEK physisch bei Offset 8977. Blockvergleich 2561 verglichen: 1269 identisch, 1292 geaendert; Canary-Datenbloecke 313 identisch, 0 geaendert; Header 0 und 1 geaendert; Bloecke 1408 bis 2560 alle geaendert. Recovery meldet "datafile 20 not processed because file is read-only". Keystore nach Transfer CLOSED / `WALLET_TYPE UNKNOWN`, nach `SET KEYSTORE OPEN FORCE KEYSTORE` PASSWORD. `ORIGIN` des transportierten Prod-Schluessels: LOCAL. Entzugstest: ORA-28374. |
| B2 - AS ENCRYPTED ohne Prod-MEK | Abbruch mit ORA-19870 plus ORA-28374 |
| B1 - AS ENCRYPTED mit Prod-MEK | Keystore muss offen sein, sonst ORA-28365. Erstes Backup-Set mit unverschluesselten CDB-Datafiles erfolgreich, Laufzeit 5:45. Beim verschluesselten Datafile 20: ORA-00600 `[kcbtse_encdec_tbsblk_1], [4], [2], [806], [18], [806], [20], [4294967295], [0], [0], [], []`, dreimal reproduziert, mit und ohne `FORCE` |
| D - FORCE AS DECRYPTED plus SET KEY plus OFFLINE ENCRYPT | Nach `AS DECRYPTED`: alle Tablespaces `ENCRYPTED NO`, `V$ENCRYPTED_TABLESPACES` leer, Klartext-Marker 313 Treffer ab Block 979. Ohne Prod-MEK oeffnet die DB nicht: ORA-28374, `mkid bca121c5d0424f9788162b2b3ac8dc56`. `SET KEY CONTAINER=ALL` dreht BCA121C5...DC56 auf 6E930457...BFB3, endet mit ORA-46663. `SET KEY` in der PDB dreht auf 8252C3B0...BCA7. Nach OFFLINE ENCRYPT: `KEY_VERSION` 3, gewrappter TEK 8FBDA2A8...3E41, Blockvergleich 1406 identisch / 1155 geaendert, abweichend sind 0, 1 und 1408 bis 2560. Wiederholter Zyklus: erneut 1406 / 1155, `KEY_VERSION` 5, TEK unveraendert |
| Positivkontrolle CTRL_ENC_A gegen CTRL_ENC_B | gewrappte TEKs 6B6A512A...3B07 und F29E623B...1C79 unter derselben `MASTERKEYID` 8A2758...F962. Von 501 Bloecken im Bereich 779 bis 1279: 367 unterschiedlich, 134 identisch |
| C - DUPLICATE AS ENCRYPTED | Gemessen im E2E-Lauf vom 2026-09-06: `MASTERKEYID` und `ENCRYPTEDKEY` unveraendert gegenueber der Baseline dieses Laufs (`EC574AF166934D45AB5AC1F2267A297A` / `059EFEB1BB6D72140B68FD768F80105B37BB912E84E6273E82227A027FD830F3`), Canary-Bloecke 313 identisch / 0 geaendert. Der Schluessel bleibt. Siehe Phase 4a |
| G - ONLINE REKEY | Gemessen im E2E-Lauf vom 2026-09-06: neues Schluesselmaterial, `KEY_VERSION` 1 -> 2, Canary-Bloecke 0 identisch / 313 geaendert. Entzugstest danach: Datenbank oeffnet nicht, bleibt `MOUNTED` mit ORA-28374. Siehe Phase 5a |
| F - Discard-Pfad mit `_db_discard_lost_masterkey` | Gemessen im E2E-Lauf vom 2026-09-06: neues Schluesselmaterial, `MASTERKEYID` `C7A38A0C0653495F882671BF2ED974A3`, gewrappter Schluessel `A0BB56AF4790B1C12B2F21D8263CBBE470EA04CDCBE7DCE5A062F6C177D8E2AC`, Canary-Bloecke 0 identisch / 313 geaendert. Der Undo-Tausch ist Vorbedingung, sonst ORA-28304 auf dem Undo-Datafile. Hidden Parameter, nur nach Freigabe durch Oracle Support - keine Empfehlung. Siehe Schritt 5.10 |
<!-- markdownlint-restore -->

### Bekannte Stolpersteine und ihre Loesung

<!-- markdownlint-disable MD013 MD060 -->
| Symptom | Ursache | Loesung |
|---|---|---|
| ORA-28365 beim Lesen oder beim `AS ENCRYPTED`-Restore | transportierter Keystore ist LOCAL AUTO_LOGIN und an den Quell-Hostnamen gebunden | `ADMINISTER KEY MANAGEMENT SET KEYSTORE OPEN FORCE KEYSTORE IDENTIFIED BY <pwd> CONTAINER=ALL`, Schritt 2.7 |
| ORA-19698 "is from different database" | die Online-Redo-Logs des Ziels liegen auf denselben Pfaden wie in der Quell-Controlfile | Redo-Logs verschieben, Schritt 2.4; `OPEN RESETLOGS` legt sie neu an |
| RMAN-06054 | die Sequenz war beim Backup noch aktives Online-Log | `SET UNTIL SEQUENCE <letzte plus 1> THREAD 1`, Schritte 2.9 und 2.10 |
| `RESTORE ... FROM AUTOBACKUP` findet kein Autobackup | das Autobackup-Format weicht vom Format der Quelle ab | `SET CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '/opt/oracle/xchange/backup/cf_%F'`, Schritt 2.5 |
| `AS DECRYPTED` sieht erfolgreich aus, aendert aber nichts | die Restore-Optimierung ueberspringt Datafiles, die schon auf Stand sind | `FORCE` verwenden, Schritt 5.1 |
| ORA-46663 bei `SET KEY ... CONTAINER=ALL` | `PDB$SEED` hat keinen Master Key | `SET KEY` zusaetzlich in der PDB, Schritt 5.5 |
| ORA-28374 nach dem Entzug des Prod-Schluessels | der aktive Master Key fehlt im Keystore | dokumentierter Ausweg: `MERGE KEYSTORE` aus einem Backup-Wallet oder `IMPORT KEYS` - im Klon-Szenario nicht gewuenscht |
<!-- markdownlint-restore -->
