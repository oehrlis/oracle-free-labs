# TDE Schluesselarchitektur - Diagramme

Begleitdokument zu [tde-restore-as-encrypted.md](tde-restore-as-encrypted.md). Alle
Zahlenwerte in den Diagrammen sind am Lab gemessen, nicht illustrativ gewaehlt.
Messsatz: `data/xchange/evidence/baseline/`, Service `odbencprod`, PDB `ODBENCPROD`,
Tablespace `USERS`, Oracle AI Database Free 26ai.

## 1 Zwei-Ebenen-Schluesselhierarchie

Der Master Encryption Key liegt im Keystore, der Tablespace Encryption Key liegt im
Datafile-Header - dort mit dem MEK eingewickelt. Nur der TEK verschluesselt Datenbloecke.

```mermaid
flowchart TB
    subgraph KS["Software Keystore - WALLET_ROOT/tde"]
        P12["ewallet.p12<br/>passwortgeschuetzter Keystore"]
        SSO["cwallet.sso<br/>Local Auto-Login"]
        SEPS["tde_seps/cwallet.sso<br/>Keystore-Passwort fuer<br/>IDENTIFIED BY EXTERNAL STORE"]
    end

    subgraph MEKS["Master Encryption Keys"]
        MEKC["MEK CDB con_id 1<br/>KEY_ID AbyhIcXQQk+XiBYrKzrI3FY...<br/>ORIGIN LOCAL"]
        MEKP["MEK PDB con_id 4<br/>KEY_ID AYonWJeWoki+lSIuWUB/+WI...<br/>MASTERKEYID 8A2758...F962<br/>ORIGIN LOCAL"]
    end

    subgraph DF["Datafile USERS - o1_mf_users_*.dbf, 2560 Bloecke"]
        HDR["Block 1 - File Header<br/>Byte 785: gewrappter TEK, 32 Byte<br/>Byte 833: MASTERKEYID, 16 Byte"]
        DATA["Bloecke 979-1407<br/>313 Datenbloecke mit Canary<br/>370 Bloecke verschluesselt"]
    end

    P12 --> SSO
    SEPS -.->|"oeffnet Keystore<br/>ohne Passworteingabe"| P12
    P12 --> MEKC
    P12 --> MEKP
    MEKP ==>|"wrappt den TEK"| HDR
    HDR ==>|"TEK entschluesselt<br/>und verschluesselt"| DATA
```

Belegt durch die Suche nach den View-Werten in der Rohdatei: der gewrappte TEK
`BAD537AD...FA55` aus `V$ENCRYPTED_TABLESPACES.ENCRYPTEDKEY` wurde genau einmal im
Datafile gefunden, bei Offset 8977 gleich Block 1 Byte 785. Die `MASTERKEYID`
`8A27589796A248BE95222E59407FF962` liegt 48 Byte dahinter bei Offset 9025. In einem
unverschluesselten Kontroll-Datafile war keine der beiden Sequenzen vorhanden.

## 2 Die Terminologiefalle - beide Operationen heissen rekey

Der Unterschied entscheidet die Kundenfrage. Eine MEK-Rotation beruehrt keinen
einzigen Datenblock.

```mermaid
flowchart LR
    subgraph ROT["MEK-Rotation - ADMINISTER KEY MANAGEMENT SET KEY"]
        R1["neuer MEK im Keystore"] --> R2["TEK wird mit dem<br/>neuen MEK neu gewrappt"]
        R2 --> R3["Datafile-Header<br/>Byte 785 und 833 aendern sich"]
        R3 --> R4["Datenbloecke<br/>unveraendert<br/>Dauer: Sekunden"]
    end

    subgraph REK["Tablespace-Rekey - ALTER TABLESPACE ... ONLINE REKEY"]
        K1["neues TEK-Material"] --> K2["Datafiles werden<br/>konvertiert neu geschrieben<br/>daher FILE_NAME_CONVERT"]
        K2 --> K3["alle Datenbloecke<br/>neu verschluesselt<br/>Dauer: proportional zur Datenmenge"]
    end
```

In Oracle Database Free ist die Online-Variante nicht unterstuetzt, siehe Licensing
Restrictions. Im Lab wird die Referenz daher ueber einen neuen verschluesselten
Tablespace mit Datenumzug gebildet.

## 3 Wo liegt welcher MEK und was aktualisiert ihn

```mermaid
flowchart TB
    subgraph PROD["odbencprod - Quelle, Port 1532"]
        PW["WALLET_ROOT<br/>/opt/oracle/dbconfig/FREE/wallet<br/>Host: data/odbencprod/dbconfig/FREE/wallet"]
        PM["MEK PDB, ORIGIN LOCAL<br/>MASTERKEYID 8A2758...F962<br/>KEY_VERSION 1"]
        PW --> PM
    end

    subgraph DEV["odbencdev - Ziel, Port 1533"]
        DW["WALLET_ROOT<br/>/opt/oracle/dbconfig/FREE/wallet<br/>Host: data/odbencdev/dbconfig/FREE/wallet"]
        DM["MEK CDB, ORIGIN LOCAL<br/>KEY_ID AWZuopGe2EGHqnGxulapWxw...<br/>eigenstaendig erzeugt"]
        DW --> DM
    end

    XCH["data/xchange<br/>/opt/oracle/xchange<br/>RMAN-Backupsets, Wallet-Kopien"]

    PROD -->|"Backup + Wallet-Kopie"| XCH
    XCH -->|"je Variante unterschiedlich"| DEV
```

Beide Container nutzen denselben containerinternen Pfad, der aber auf getrennte
Host-Verzeichnisse zeigt. Das ist genau die Kundenkonstellation: identische
Konfiguration, getrennte Schluesselbestaende.

Was den MEK aendert:

<!-- markdownlint-disable MD013 MD060 -->

| Ereignis | Wirkung auf den MEK | Wirkung auf den TEK | Wirkung auf Datenbloecke |
|---|---|---|---|
| `ADMINISTER KEY MANAGEMENT SET KEY` | neuer aktiver MEK, alter bleibt im Keystore | wird neu gewrappt | keine |
| Keystore-Kopie nach Dev | derselbe MEK, `ORIGIN` bleibt `LOCAL` in der Kopie | unveraendert | keine |
| `EXPORT`/`IMPORT KEYS` | MEK erscheint im Ziel mit `ORIGIN IMPORTED` | unveraendert | keine |
| `RESTORE ... AS ENCRYPTED USING KEY` | Ziel-MEK wird verwendet | offen - Messung | offen - Messung |
| Tablespace-Rekey | unveraendert | neues Material | alle neu verschluesselt |

<!-- markdownlint-restore -->

Die beiden mit "offen" markierten Zellen sind der Gegenstand des Tests. Sie sind in der
oeffentlichen Oracle-Dokumentation fuer den Fall verschluesselt nach verschluesselt
nicht belegt.

## 4 UNITED gegen ISOLATED Keystore-Modus

Im Lab laeuft alles im UNITED Mode. Gemessen an `odbencprod`: genau ein
Keystore-Verzeichnis `WALLET_ROOT/tde` plus `tde_seps` und `backups`, kein
PDB-eigenes Keystore-Verzeichnis, `KEYSTORE_MODE = UNITED` fuer die PDB, und
`TDE_CONFIGURATION = KEYSTORE_CONFIGURATION=FILE` ausschliesslich auf CDB-Ebene
gesetzt - die PDB hat keinen eigenen Wert und erbt.

Zum Moduswechsel gibt es zwei Aussagen, die sich nicht deckten und die hier
getrennt stehen bleiben, bis das Lab entscheidet:

- Oracle-Primaerdokumentation: der Wechsel laeuft ueber
  `ADMINISTER KEY MANAGEMENT ISOLATE KEYSTORE ... FROM ROOT KEYSTORE` in der PDB
  und zurueck ueber `UNITE KEYSTORE`. `TDE_CONFIGURATION` unterscheidet die Modi
  **nicht** ueber seinen Wert - beide nutzen `KEYSTORE_CONFIGURATION=FILE`. Eine
  isolierte PDB kann den Parameter danach separat setzen.
  Quelle: Administering United Mode und TDE_CONFIGURATION, Oracle 26ai.
- Praxisbeobachtung: wird `TDE_CONFIGURATION` in der PDB gesetzt, entsteht dort
  ein eigenes Keystore-File.

Beides kann zusammenpassen, wenn das Setzen des Parameters in der PDB die
Isolierung in der Praxis nach sich zieht. Belegt ist das nicht - der Punkt ist
im Lab zu pruefen und steht als offener Pruefpunkt in `tasks/todo.md`.

```mermaid
flowchart TB
    subgraph U["UNITED - TDE_CONFIGURATION nur in CDB\$ROOT"]
        UKS["ein Keystore<br/>WALLET_ROOT/tde/ewallet.p12"]
        UM1["MEK CDB\$ROOT<br/>con_id 1"]
        UM2["MEK PDB<br/>con_id 4"]
        UKS --> UM1
        UKS --> UM2
        UM2 --> UTS["TEK des PDB-Tablespace"]
    end

    subgraph I["ISOLATED - TDE_CONFIGURATION in der PDB gesetzt"]
        IKS1["Keystore CDB\$ROOT<br/>WALLET_ROOT/tde"]
        IKS2["eigenes Keystore-File der PDB"]
        IM1["MEK CDB\$ROOT"]
        IM2["MEK PDB"]
        IKS1 --> IM1
        IKS2 --> IM2
        IM2 --> ITS["TEK des PDB-Tablespace"]
    end
```

Beide Modi halten containerspezifische MEKs. Der Unterschied liegt darin, ob
diese Schluessel in einem gemeinsamen Keystore-File liegen oder in getrennten.
Fuer einen Klon von Prod nach Non-Prod heisst das: in UNITED wandert eine
Keystore-Datei mit allen MEKs, in ISOLATED wandern mehrere und die Zuordnung
muss stimmen.

Ein eigener PDB-MEK ist in UNITED nicht optional. Die Oracle-Dokumentation zu
United Mode sagt dazu, der Keystore werde vom CDB-Root verwaltet, muesse aber
einen fuer die PDB spezifischen TDE-Master-Key enthalten, damit die PDB TDE
nutzen kann. Ein dokumentierter Weg, PDB-Tablespace-Keys direkt mit dem
MEK von CDB\$ROOT zu wrappen und so mit einem einzigen MEK fuer die ganze
Datenbank zu arbeiten, ist nicht belegt. Nur eine Non-CDB haette naturgemaess
einen einzigen MEK.

Bei einer Single-Tenant-Umgebung mit genau einer PDB ist UNITED damit der
einfachere Weg, aber auch dort existieren zwei MEKs. Am Prinzip der Messung
aendert der Modus nichts - der TEK liegt in beiden Faellen im Datafile-Header
und wird von einem MEK gewrappt. ISOLATED erhoeht nur den Verwaltungsaufwand
beim Transport, und laut einer Sekundaerquelle ist ISOLATED von AutoUpgrade und
OCI-Tooling noch nicht vollstaendig unterstuetzt.

> Quellenstand: die Aussage, dass `TDE_CONFIGURATION` auf PDB-Ebene ein eigenes
> Keystore-File erzeugt, ist Praxiswissen und deckt sich nicht mit der
> Oracle-Primaerdokumentation, die den Moduswechsel ueber `ISOLATE KEYSTORE`
> beschreibt. Der Punkt wird im Lab gemessen.

## 5 Die Varianten im Vergleich

Alle Varianten starten bei derselben Quelle: PDB `ODBENCPROD`, Tablespace `USERS`
verschluesselt mit AES256, gewrappter TEK `BAD537AD...FA55` unter MASTERKEYID
`8A2758...F962`, 313 Canary-Datenbloecke.

```mermaid
flowchart TB
    SRC["Quelle odbencprod<br/>USERS verschluesselt<br/>TEK BAD537AD...FA55<br/>313 Datenbloecke"]

    SRC --> A["A: RESTORE DATABASE<br/>Prod-Wallet transportiert"]
    SRC --> B2["B2: AS ENCRYPTED USING KEY<br/>ohne Prod-MEK"]
    SRC --> B1["B1: AS ENCRYPTED USING KEY<br/>mit Prod-MEK"]
    SRC --> D["D: FORCE AS DECRYPTED<br/>dann SET KEY<br/>dann OFFLINE ENCRYPT"]
    SRC --> P["Positivkontrolle<br/>neuer verschluesselter<br/>Tablespace"]

    A --> AR["313 von 313 Datenbloecken<br/>byteidentisch<br/>TEK unveraendert<br/>Entzug: ORA-28374"]
    B2 --> B2R["Restore scheitert<br/>ORA-19870 plus ORA-28374<br/>kein Ergebnis"]
    B1 --> B1R["Restore scheitert<br/>ORA-00600<br/>kcbtse_encdec_tbsblk_1<br/>dreimal reproduziert"]
    D --> DR["313 von 313 Datenbloecken<br/>byteidentisch<br/>MEK neu, TEK unveraendert"]
    P --> PR["367 von 501 Bloecken<br/>unterschiedlich<br/>TEK nachweislich neu"]

    AR --> NO1["untauglich"]
    B2R --> NO2["nicht nutzbar"]
    B1R --> NO3["nicht nutzbar"]
    DR --> NO4["MEK getrennt,<br/>Chiffrat identisch"]
    PR --> YES["erfuellt die<br/>Trennungsanforderung"]
```

Die Positivkontrolle ist der Beweis, dass die Messung ueberhaupt greift: zwei
Tablespaces mit identischem Inhalt, identischen Blockadressen und verschiedenen
TEKs liefern unterschiedliches Chiffrat. Wo Quelle und Klon byteidentisch sind,
ist der TEK also wirklich derselbe und nicht nur die Messung blind.

## 6 Entscheidungsbaum fuer den Kunden

```mermaid
flowchart TB
    Q1{"Soll der Klon<br/>kryptografisch von Prod<br/>getrennt sein?"}
    Q1 -->|nein| A1["RESTORE DATABASE<br/>Prod-Keystore mitgeben<br/>einfachster Weg"]
    Q1 -->|ja| Q2{"Darf der Prod-Schluessel<br/>voruebergehend ins Ziel?"}
    Q2 -->|nein| X["kein RMAN-Weg vorhanden<br/>gemessen: ORA-28374<br/>Alternative: logischer Export"]
    Q2 -->|ja| Q3{"Enterprise Edition<br/>verfuegbar?"}
    Q3 -->|ja| R1["Klon, dann SET KEY,<br/>dann ONLINE REKEY<br/>Doku verspricht<br/>independent keys<br/>im Lab nicht pruefbar"]
    Q3 -->|nein| R2["Klon, dann SET KEY,<br/>dann neuen verschluesselten<br/>Tablespace anlegen und<br/>Daten umziehen<br/>gemessen: neuer TEK"]
    R1 --> CLEAN["danach Keystore-Hygiene:<br/>frischer Keystore mit<br/>selektivem Import,<br/>sonst bleiben alle<br/>historischen Prod-Schluessel"]
    R2 --> CLEAN
```

Der Kasten zur Keystore-Hygiene ist kein Nebenschauplatz. Ein kopierter Keystore
enthaelt die vollstaendige Schluesselhistorie der Quelle, und `ORIGIN` zeigt fuer
diese Schluessel im Ziel `LOCAL` - die Herkunft ist an den Views nicht erkennbar.
