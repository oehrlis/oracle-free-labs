# TDE Schluesselarchitektur

Diagramm- und Erklaerdokument zur TDE-Schluesselarchitektur in Oracle AI Database
Free 26ai. Begleitdokument zu [tde-restore-as-encrypted.md](tde-restore-as-encrypted.md).
Alle Zahlenwerte sind am Lab gemessen, Messsatz `data/xchange/evidence/`,
Services `odbencprod` und `odbencdev`, PDB `ODBENCPROD`, Tablespace `USERS`.

## Lesehinweis

Das Dokument folgt der Reihenfolge: Schluesselstruktur (Kapitel 2), eine haeufig
uebersehene Ausnahme (Kapitel 3), gemessene Wirkung je Operation (Kapitel 4),
Sonderfaelle (Kapitel 5-7), Variantenvergleich (Kapitel 8) und Stufenmodell (Kapitel 9).
Kapitel 4 enthaelt die Terminologiefalle, die den Kernbefund des Tests erklaert.

## Die drei Schluesselebenen

Drei Ebenen sind aktiv, wenn ein Tablespace mit TDE geschuetzt wird. Sie liegen an
unterschiedlichen Orten und haben unterschiedliche Rollen.

<!-- markdownlint-disable MD013 MD060 -->

| Ebene | View | Format | Speicherort | Anzahl |
|---|---|---|---|---|
| MEK | `v$encryption_keys` | KEY_ID base64 | Keystore `ewallet.p12` | je Container ein aktiver, dazu die Historie |
| Database Key | `v$database_key_info` | RAW(48), 32 Byte signifikant | von Oracle verwaltet, vom MEK gewrappt | je Container einer |
| Tablespace Key | `v$encrypted_tablespaces` | RAW(32) | gewrappt im Datafile-Header, bei 8K in Block 1 Byte 785 | je verschluesseltem Tablespace einer |

<!-- markdownlint-restore -->

```mermaid
flowchart TB
    subgraph KS["Software Keystore - WALLET_ROOT/tde"]
        P12["ewallet.p12<br/>passwortgeschuetzt"]
        SSO["cwallet.sso<br/>Local Auto-Login"]
        SEPS["tde_seps/cwallet.sso<br/>External Store fuer<br/>Keystore-Passwort"]
    end

    subgraph MEK_BOX["Master Encryption Keys - v$encryption_keys"]
        MEKC["MEK CDB con_id 1<br/>KEY_ID base64<br/>ORIGIN LOCAL"]
        MEKP["MEK PDB con_id N<br/>KEY_ID base64<br/>ORIGIN LOCAL"]
    end

    subgraph DBK["Database Key - v$database_key_info"]
        DK["RAW(48), 32 Byte signifikant<br/>je Container einer<br/>existiert auch bei unverschluesselten Tablespaces"]
    end

    subgraph DF["Datafile-Header - Block 1"]
        TEK["Tablespace Key RAW(32)<br/>Byte 785: gewrappter TEK<br/>Byte 833: MASTERKEYID"]
        DATA["Datenbloecke<br/>vom TEK verschluesselt"]
    end

    P12 --> SSO
    SEPS -.->|"oeffnet ohne Passworteingabe"| P12
    P12 --> MEKC
    P12 --> MEKP
    MEKP -->|"wrappt"| DK
    MEKP -->|"wrappt"| TEK
    TEK -->|"entschluesselt und verschluesselt"| DATA
```

Physisch nachgewiesen: der gewrappte TEK aus `v$encrypted_tablespaces.ENCRYPTEDKEY`
wurde genau einmal im Rohdatafile gefunden, bei Offset 8977 gleich Block 1 Byte 785.
Die `MASTERKEYID` liegt bei Offset 9025, 48 Byte dahinter. In einem unverschluesselten
Kontroll-Datafile kein Treffer. Gemessen in zwei unabhaengigen Aufbauten, die Offsets
waren in beiden identisch.

## Nicht jeder Tablespace hat einen eigenen Schluessel

Das ist der Punkt, an dem Erwartung und Messung auseinandergehen. Die verwendete
Verschluesselungsoperation entscheidet, ob ein Tablespace einen eigenen Schluessel
erhaelt oder den Database Key des Containers uebernimmt.

```mermaid
flowchart TB
    subgraph OFL["OFFLINE ENCRYPT"]
        OF1["kein eigener Schluessel erzeugt"]
        OF2["TEK = Database Key des Containers"]
        OF1 --> OF2
    end

    subgraph ONL["ONLINE ENCRYPT / ONLINE REKEY"]
        ON1["eigener Tablespace Key erzeugt"]
        ON2["TEK verschieden vom Database Key"]
        ON1 --> ON2
    end

    subgraph RMN["RMAN AS ENCRYPTED (zuvor unverschluesselt)"]
        RM1["verschluesselt mit Database Key<br/>der Quelldatenbank"]
        RM2["kein eigenes Schluesselmaterial<br/>fuer diese Tablespaces"]
        RM1 --> RM2
    end
```

Gemessene Belege:

- Nach Variante F trug `USERS` (per `OFFLINE ENCRYPT` verschluesselt) exakt den
  DB-Key-Wert `D40B030F...F03F` als TEK.
- `CANARY_PLAIN` erhielt per `ONLINE ENCRYPT` einen eigenen TEK `A1EBE741...`,
  `USERS` nach `ONLINE REKEY` den TEK `A4C84E43...426B` - beide verschieden vom DB Key.
- In Variante C (DUPLICATE AS ENCRYPTED) erhielten `SYSTEM`, `SYSAUX`, `UNDOTBS1`,
  `AUDIT_DATA` und `CANARY_PLAIN` alle den Wert `566B2C9C...69CE`, den Database Key
  der Quell-PDB.

Der Doku-Wortlaut "the tablespace will have its own independent encryption keys and
algorithms" bezieht sich ausschliesslich auf Online-Operationen. Das ist hier am
Verhalten belegt.

## Wirkung je Operation

<!-- markdownlint-disable MD013 MD060 -->

| Operation | MEK | Database Key | Tablespace Key | Datenbloecke |
|---|---|---|---|---|
| `SET KEY` MEK-Rotation | neu | neu gewrappt, Klartext gleich | neu gewrappt, KEY_VERSION unveraendert | unveraendert, 2560 von 2561 identisch |
| `ONLINE REKEY` | unveraendert | unveraendert | **neuer Schluessel**, KV plus 1 | **alle neu verschluesselt**, neues Datafile, altes entfernt |
| `ONLINE ENCRYPT` | unveraendert | unveraendert | **neuer eigener Schluessel** | verschluesselt |
| `OFFLINE ENCRYPT` | unveraendert | unveraendert | **uebernimmt den Database Key** | verschluesselt |
| `OFFLINE DECRYPT` | unveraendert | unveraendert | Handle bleibt im Header stehen | entschluesselt |
| RMAN `AS ENCRYPTED` | Quelle | Quelle | unverschluesselte TS erhalten DB Key, verschluesselte behalten ihren | bei verschluesselten unveraendert |

<!-- markdownlint-restore -->

### Die Terminologiefalle

Beide Operationen heissen umgangssprachlich "rekey". Der Unterschied ist
kryptografisch entscheidend.

```mermaid
flowchart TB
    subgraph ROT["MEK-Rotation - ADMINISTER KEY MANAGEMENT SET KEY"]
        direction TB
        R1["neuer MEK im Keystore<br/>B0A4B54D...0B74 -> DEFA0240...6A3A"]
        R2["TEK neu gewrappt<br/>Klartext unveraendert<br/>A4C84E43...426B -> B1DB7C22...A8BE"]
        R3["Block 1 Byte 785 und 833 geaendert<br/>Datenbloecke unveraendert<br/>2560 von 2561 identisch"]
        R1 --> R2
        R2 --> R3
    end

    subgraph REK["ONLINE REKEY - ALTER TABLESPACE ... ENCRYPTION ONLINE REKEY"]
        direction TB
        K1["neues TEK-Material<br/>D40B030F...F03F -> A4C84E43...426B<br/>KEY_VERSION 3 -> 4"]
        K2["alle Datenbloecke neu verschluesselt<br/>neues Datafile angelegt<br/>altes physisch entfernt"]
        K3["alte TEKs im neuen File<br/>nicht mehr auffindbar<br/>2560 von 2561 Bloecke unterschiedlich"]
        K1 --> K2
        K2 --> K3
    end
```

Belege fuer die MEK-Rotation:

- Alert Log woertlich: `KZTDE: Set Master Key: Tablespace key rewrap done`
- Blockvergleich: 2560 von 2561 Bloecken identisch, Verdict "RE-WRAP INDICATED"
- KEY_VERSION des TEK unveraendert bei 4

Belege fuer `ONLINE REKEY`:

- KEY_VERSION 3 auf 4, TEK `D40B030F...F03F` auf `A4C84E43...426B`
- Neues Datafile angelegt, altes physisch entfernt
- Alte TEKs im neuen File nicht mehr auffindbar
- `ONLINE REKEY` ist in Oracle Database Free 26ai technisch ausfuehrbar. Die
  Licensing Restriction ist eine Lizenz- und Supportaussage, kein technischer Riegel.

## Read-only-Tablespaces

Bei der MEK-Rotation werden Read-only-Tablespaces nicht umgewickelt. Oracle kann
den Datafile-Header eines Read-only-Tablespace nicht schreiben.

```mermaid
flowchart LR
    subgraph KS["Keystore nach SET KEY"]
        NK["neuer MEK DEFA0240...6A3A<br/>aktiv"]
        OK["alter MEK B0A4B54D...0B74<br/>in der Historie"]
    end

    subgraph TS["Tablespaces nach SET KEY"]
        USERS_TS["USERS (READ WRITE)<br/>zeigt auf DEFA0240...6A3A"]
        CP_TS["CANARY_PLAIN (READ ONLY)<br/>zeigt weiter auf B0A4B54D...0B74"]
    end

    NK --> USERS_TS
    OK --> CP_TS
    OK -.->|"zwingend erforderlich"| CP_TS
```

Gemessen: `CANARY_PLAIN` stand auf `READ ONLY` und verwies nach der MEK-Rotation
weiter auf den alten MEK `B0A4B54D...0B74`, waehrend `USERS` und der Database Key
auf `DEFA0240...6A3A` zeigten.

Folge: der alte MEK bleibt zwingend erforderlich. Die vollstaendige Schluesselhistorie
muss im Keystore bleiben. Operativ relevant, weil Archiv-Tablespaces haeufig read-only
sind. Wer den alten MEK entfernt, verliert den Zugriff auf jeden read-only Tablespace,
der ihn referenziert.

## UNITED gegen ISOLATED

Im Lab laeuft alles im UNITED Mode. Gemessen an `odbencprod`:

- ein Keystore-Verzeichnis `WALLET_ROOT/tde` plus `tde_seps` und `backups`
- kein PDB-eigenes Keystore-Verzeichnis
- `KEYSTORE_MODE = UNITED` fuer die PDB
- `TDE_CONFIGURATION = KEYSTORE_CONFIGURATION=FILE` ausschliesslich auf CDB-Ebene
- Alert Log: `KZTDE:kztsmptc: keystore mode: United`

Korrektur zu einer frueheren Annahme: `TDE_CONFIGURATION` unterscheidet die Modi
**nicht** ueber seinen Wert. Beide nutzen `KEYSTORE_CONFIGURATION=FILE`. Der Wechsel
laeuft ueber `ADMINISTER KEY MANAGEMENT ISOLATE KEYSTORE ... FROM ROOT KEYSTORE`
in der PDB und zurueck ueber `UNITE KEYSTORE`.

```mermaid
flowchart TB
    subgraph U["UNITED - TDE_CONFIGURATION nur in CDB ROOT"]
        UKS["ein Keystore<br/>WALLET_ROOT/tde/ewallet.p12"]
        UM1["MEK CDB ROOT con_id 1"]
        UM2["MEK PDB con_id N"]
        UKS --> UM1
        UKS --> UM2
        UM2 --> UTS["TEK des PDB-Tablespace"]
    end

    subgraph I["ISOLATED - ISOLATE KEYSTORE ausgefuehrt"]
        IKS1["Keystore CDB ROOT<br/>WALLET_ROOT/tde"]
        IKS2["eigenes Keystore-File der PDB"]
        IM1["MEK CDB ROOT"]
        IM2["MEK PDB"]
        IKS1 --> IM1
        IKS2 --> IM2
        IM2 --> ITS["TEK des PDB-Tablespace"]
    end
```

Die Praxisbeobachtung, dass ein in der PDB gesetztes `TDE_CONFIGURATION` ein eigenes
Keystore-File erzeugt, ist nicht durch die Oracle-Primaerdokumentation belegt und
bleibt ein offener Pruefpunkt. Beides kann zusammenpassen, wenn das Setzen des
Parameters in der PDB die Isolierung nach sich zieht - gemessen ist das nicht.

Ein eigener PDB-MEK ist in UNITED nicht optional. Ein dokumentierter Weg, PDB-Tablespace-
Keys direkt mit dem MEK von `CDB$ROOT` zu wrappen, ist nicht belegt. Nur eine Non-CDB
haette naturgemaess einen einzigen MEK.

## Keystore-Portabilitaet

Ein `LOCAL` Auto-Login-Keystore ist an den erzeugenden Host gebunden. Das hat
Konsequenzen beim Transport.

```mermaid
flowchart TB
    SRC["odbencprod<br/>ewallet.p12 und cwallet.sso LOCAL"]
    COPY["Kopie auf Zielhost<br/>beide Dateien uebertragen"]
    ERR1["v$encryption_wallet: CLOSED<br/>WALLET_TYPE: UNKNOWN<br/>ORA-28365 beim Zugriff"]
    ERR2["cwallet.sso blockiert<br/>Neuerzeugung: ORA-46630"]
    FIX["Loesung:<br/>cwallet.sso beiseite legen<br/>ewallet.p12 behalten<br/>LOCAL AUTO_LOGIN am Ziel neu erzeugen"]
    OK["Keystore OPEN<br/>WALLET_TYPE: LOCAL_AUTOLOGIN"]

    SRC -->|"sso + p12 kopiert"| COPY
    COPY --> ERR1
    COPY --> ERR2
    ERR2 --> FIX
    FIX --> OK
```

Gemessen in drei Varianten unabhaengig aufgetreten. Das funktionierende Vorgehen:

```sql
ADMINISTER KEY MANAGEMENT CREATE LOCAL AUTO_LOGIN KEYSTORE
  FROM KEYSTORE '/opt/oracle/dbconfig/FREE/wallet/tde' IDENTIFIED BY <pwd>;
```

Wichtiger Nebenbefund: `ORIGIN` zeigt fuer transportierte Schluessel im Ziel `LOCAL`,
nicht `IMPORTED`. Wer die Keystore-Datei kopiert, hinterlaesst keine Spur der Herkunft.
`ORIGIN` taugt nicht als Nachweis lokaler Schluesselerzeugung. Betrifft auch den
SEPS-Store `tde_seps`, der ebenfalls als `LOCAL AUTO_LOGIN` angelegt wird.

## Die Varianten im Vergleich

<!-- markdownlint-disable MD013 MD060 -->

| Variante | Vorgehen | Canary-Bloecke identisch | TEK USERS | Ergebnis |
|---|---|---|---|---|
| A | normaler RESTORE, Prod-Wallet transportiert | 313 von 313 | unveraendert | laeuft; Entzugstest: ORA-28374 |
| B1 | AS ENCRYPTED USING KEY mit Prod-MEK | - | - | ORA-00600 [kcbtse\_encdec\_tbsblk\_1], dreimal reproduziert |
| B2 | AS ENCRYPTED USING KEY ohne Prod-MEK | - | - | ORA-19870 plus ORA-28374 |
| C | DUPLICATE BACKUP LOCATION AS ENCRYPTED | 313 von 313 | unveraendert | laeuft, neue DBID; unverschluesselte TS erhalten DB Key der Quelle |
| D | FORCE AS DECRYPTED, SET KEY, OFFLINE ENCRYPT | 313 von 313 | unveraendert | MEK neu, Chiffrat identisch; kein kryptografischer Neuanfang |
| F | RESTORE, OFFLINE DECRYPT, Undo-Tausch, frischer Keystore, \_db\_discard\_lost\_masterkey, SET KEY, OFFLINE ENCRYPT | 0 von 313 | **neu** | Quell-TEK und Quell-MASTERKEYID physisch verschwunden, kein Quell-MEK, Canary lesbar |
| G | ONLINE REKEY | 0 von 313 | **neu** | neues Datafile, altes entfernt, alte TEKs nicht mehr auffindbar |
| P1 | PDB-Klon in derselben CDB | 0 von 313 | **neu** | MASTERKEYID identisch zur Quelle, gewrappter Schluessel verschieden - unter unveraendertem MEK kein Re-wrap moeglich |
| P2 | PDB-Archiv in eine fremde CDB | 313 von 313 | unveraendert | gewrappter Schluessel identisch; Transport erhaelt Schluessel und Chiffrat |
| P4 | PDB-Remote-Klon ueber DB-Link | 0 von 313 | **neu** | wie P1, ueber CDB-Grenze hinweg |
| Positivkontrolle | zwei frische verschluesselte TS mit identischem Inhalt und verschiedenen TEKs | 0 von 313 | verschieden | die Methode erkennt einen Schluesselwechsel in jedem Canary-Block |

<!-- markdownlint-restore -->

Anmerkung zu Variante B1: das erste Backup-Set mit unverschluesselten CDB-Datafiles
wurde in 5:45 erfolgreich konvertiert, gegenueber 3 Sekunden bei normalem Restore.
Beide Zeiten sind Einzelbeobachtungen und wurden nicht wiederholt gemessen; sie belegen
die Richtung, nicht einen Kennwert.
`AS ENCRYPTED` leistet bei unverschluesselter Quelle echte Blockarbeit - das Abbrechen
tritt erst beim bereits verschluesselten Datafile auf.

### Der Kontrast D gegen F belegt die dritte Ebene

Beide Varianten fuehren dieselbe Anweisung aus:
`ALTER TABLESPACE USERS ENCRYPTION OFFLINE ENCRYPT`. Sie unterscheiden sich in genau einer
Variablen - ob der Database Key des Containers erneuert wurde.

<!-- markdownlint-disable MD013 MD060 -->
| | Variante D | Variante F |
|---|---|---|
| MEK | neu gesetzt | neu, frischer Keystore |
| Database Key | unveraendert | erneuert ueber den Discard-Pfad |
| Operation | `OFFLINE ENCRYPT` | `OFFLINE ENCRYPT` |
| Canary-Chiffrat | 313 von 313 identisch | 0 von 313 identisch |
<!-- markdownlint-restore -->

Dieselbe Anweisung, entgegengesetztes Ergebnis. Damit ist gemessen, dass `OFFLINE ENCRYPT`
sein Tablespace-Schluesselmaterial aus dem **Database Key des Containers** ableitet und nicht
aus dem MEK: eine MEK-Rotation allein aendert das Chiffrat nachweislich nicht. Oracle
dokumentiert nur zwei Ebenen; diese Messung ist die Grundlage fuer die dritte in diesem
Dokument.

Anmerkung zu Variante C: der als "neuer gemeinsamer TEK" gemessene Wert
`566B2C9C...69CE` ist der Database Key der PDB in der Quelle. AS ENCRYPTED hat die
fuenf unverschluesselten Tablespaces unter dem vorhandenen Database Key der Quelle
verschluesselt.

```mermaid
flowchart TB
    SRC["Quelle odbencprod<br/>USERS: TEK E36623EC...934F<br/>DB Key: 566B2C9C...69CE<br/>313 Canary-Datenbloecke"]

    SRC --> A["A: normaler RESTORE<br/>Prod-Wallet transportiert"]
    SRC --> B1["B1: AS ENCRYPTED<br/>mit Prod-MEK"]
    SRC --> B2["B2: AS ENCRYPTED<br/>ohne Prod-MEK"]
    SRC --> C["C: DUPLICATE AS ENCRYPTED<br/>aus Backup"]
    SRC --> D["D: AS DECRYPTED<br/>SET KEY, OFFLINE ENCRYPT"]
    SRC --> F["F: RESTORE, DECRYPT<br/>frischer Keystore, SET KEY<br/>OFFLINE ENCRYPT"]
    SRC --> G["G: ONLINE REKEY"]
    SRC --> P1["P1/P4: PDB-Klon<br/>lokal oder ueber DB-Link"]
    SRC --> P2["P2: PDB-Archiv<br/>unplug und plug"]
    SRC --> PK["Positivkontrolle<br/>zwei TS, gleicher Inhalt"]

    A --> AR["313 von 313 identisch<br/>TEK unveraendert<br/>ORA-28374 beim Entzug"]
    B1 --> B1R["ORA-00600<br/>kcbtse_encdec_tbsblk_1"]
    B2 --> B2R["ORA-19870<br/>ORA-28374"]
    C --> CR["313 von 313 identisch<br/>USERS TEK unveraendert<br/>unverschluesselte TS: DB Key der Quelle"]
    D --> DR["313 von 313 identisch<br/>TEK unveraendert<br/>MEK neu"]
    F --> FR["0 von 313 identisch<br/>TEK neu, kein Quell-MEK<br/>Canary lesbar"]
    G --> GR["0 von 313 identisch<br/>TEK neu, neues Datafile"]
    P1 --> P1R["0 von 313 identisch<br/>TEK neu bei gleichem MEK"]
    P2 --> P2R["313 von 313 identisch<br/>TEK und Chiffrat erhalten"]
    PK --> PKR["0 von 313 identisch<br/>TEK-Wechsel nachweisbar"]
```

## Stufenmodell der kryptografischen Unabhaengigkeit

Die Stufen leiten sich ausschliesslich aus den Messergebnissen ab.

```mermaid
flowchart LR
    S0["Stufe 0<br/>Prod-Keystore und<br/>Prod-Schluessel im Ziel<br/>Varianten A, C-USERS"]
    S1["Stufe 1<br/>eigener MEK<br/>Prod-TEK, identisches Chiffrat<br/>Variante D"]
    S2["Stufe 2<br/>eigener MEK<br/>eigener TEK<br/>Prod-MEK noch vorhanden"]
    S3["Stufe 3<br/>eigener MEK<br/>eigener TEK<br/>kein Quell-MEK im Keystore<br/>Varianten F, G"]

    S0 --> S1
    S1 --> S2
    S2 --> S3
```

<!-- markdownlint-disable MD013 MD060 -->

| Stufe | Merkmal | Varianten | Was gemeinsam bleibt | Kryptografische Trennung |
|---|---|---|---|---|
| 0 | Prod-Keystore und Prod-TEK im Ziel | A, C (USERS-Teil) | MEK, TEK, Chiffrat | keine |
| 1 | Eigener MEK, Prod-TEK | D | TEK-Klartext, Chiffrat identisch | MEK-Trennung, kein Schutz des Chiffrats |
| 2 | Eigener MEK, eigener TEK, Prod-MEK noch im Keystore | Zwischenzustand nach F vor Keystore-Bereinigung | Prod-MEK vorhanden | TEK getrennt, Keystore-Kontrolle noch nicht vollstaendig |
| 3 | Eigener MEK, eigener TEK, kein Quell-MEK | F, G | nichts Schluesselrelevantes | vollstaendig |

<!-- markdownlint-restore -->

Hinweis zu Variante F: `_db_discard_lost_masterkey` ist ein Hidden Parameter,
dokumentiert in einer MOS Note. Einsatz nur nach Abklaerun mit Oracle Support.
Fachlich zulaessig ausschliesslich nach vollstaendigem `AS DECRYPTED`, wenn
nachweislich kein verschluesseltes Objekt mehr existiert. Eine Sekundaerquelle
warnt bei wiederholtem Einsatz vor echten Korruptionen (ORA-01595, ORA-28304).
Gemessen in Oracle AI Database Free 26ai, nicht in Enterprise Edition.

Im Fenster zwischen `OFFLINE DECRYPT` und `OFFLINE ENCRYPT` in Variante F liegen
die Daten unverschluesselt. Das ist ein bewusster Sicherheitskompromiss.

## Quellen

- Oracle Backup and Recovery Reference 19c, RESTORE:
  <https://docs.oracle.com/en/database/oracle/oracle-database/19/rcmrf/RESTORE.html>
- Oracle Backup and Recovery Reference 26ai, RESTORE:
  <https://docs.oracle.com/en/database/oracle/oracle-database/26/rcmrf/RESTORE.html>
- Oracle Backup and Recovery Reference 19c, DUPLICATE:
  <https://docs.oracle.com/en/database/oracle/oracle-database/19/rcmrf/DUPLICATE.html>
- Oracle Database Free 26ai, Licensing Restrictions:
  <https://docs.oracle.com/en/database/oracle/oracle-database/26/xeinl/licensing-restrictions.html>
- Oracle TDE 26ai, Encryption Conversions for Tablespaces:
  <https://docs.oracle.com/en/database/oracle/oracle-database/26/dbtde/encryption-conversions-tablespaces-and-databases1.html>
- Oracle Reference 19c, V$ENCRYPTED\_TABLESPACES:
  <https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/V-ENCRYPTED_TABLESPACES.html>
- Oracle TDE 26ai, Administering United Mode:
  <https://docs.oracle.com/en/database/oracle/oracle-database/26/dbtde/administering-united-mode1.html>
- Oracle Reference 26ai, TDE\_CONFIGURATION:
  <https://docs.oracle.com/en/database/oracle/oracle-database/26/refrn/TDE_CONFIGURATION.html>
- Oracle Advanced Security 19c, Managing Keystores in United Mode:
  <https://docs.oracle.com/en/database/oracle/oracle-database/19/asoag/managing-keystores-encryption-keys-in-united-mode.html>
- Oracle TDE 26ai, ORA-28374:
  <https://docs.oracle.com/en/database/oracle/oracle-database/26/dbtde/error-ora-28374-typed-master-key-not-found.html>
- Oracle Advanced Security 19c, Configuring TDE:
  <https://docs.oracle.com/en/database/oracle/oracle-database/19/asoag/configuring-transparent-data-encryption.html>
- Asanga Pradeep Blog, 19c Encryption (Sekundaerquelle):
  <https://asanga-pradeep.blogspot.com/2019/10/19c-encryption.html>
