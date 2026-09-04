# Rechercheergebnisse OKV und Angriffsflaechen (2026-09-04)

Arbeitsdatei. Faktenbasis fuer `doc/tde-okv-argumentation.md`. Jede Aussage mit Quelle.
Nicht belegte Punkte sind ausdruecklich als solche markiert und duerfen im Deliverable
nicht als belegt erscheinen.

## Schluesselhierarchie - Oracle-Primaerbelege

- MEK ist immer AES256 und wickelt die Data Encryption Keys im CBC-Modus ein.
  Zitat: "Master encryption keys always are AES256. They encrypt and decrypt DEKs using
  CBC operating mode."
  Quelle: <https://docs.oracle.com/en/database/oracle/oracle-database/26/dbtde/faq-tde.html>
- `V$ENCRYPTED_TABLESPACES.ENCRYPTEDKEY` ist die **verschluesselte** Fassung des
  Tablespace-Keys, `MASTERKEYID` die ID des MEK, der ihn verschluesselt hat.
  Quelle: <https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/V-ENCRYPTED_TABLESPACES.html>
- "The TDE master encryption key is used to encrypt the TDE tablespace encryption key,
  which in turn is used to encrypt and decrypt data in the tablespace."
  Quelle: <https://docs.oracle.com/en/database/oracle/oracle-database/19/asoag/introduction-to-transparent-data-encryption.html>
- Ab 26ai unterstuetzt TDE Tablespace Encryption AES XTS und nutzt es als Default.
  19c und aelter: CFB. Erklaert die gemessenen CIPHERMODE-Werte und dass AES192 auf CFB faellt.
  Quelle: <https://docs.oracle.com/en/database/oracle/oracle-database/26/dbtde/changes-this-release-oracle-database-transparent-data-encryption-guide.html>
- MEK-Rekey erfordert kein Neuverschluesseln der Daten, nur die DEK-Wrapper werden neu
  verschluesselt.
  Quelle: <https://docs.oracle.com/en/database/oracle/oracle-database/19/asoag/frequently-asked-questions-about-transparent-data-encryption.html>
- Woertlich zur Rotation: "This operation is fast and does not require database downtime.
  It does not change the tablespace keys and does not re-encrypt customer data."
  Quelle: <https://docs.oracle.com/en/cloud/paas/autonomous-database/serverless/adbsb/sec-rotate-customer-managed-keys-autonomous-database-oci-vault.html>
- Keystore haelt die Historie zurueckgezogener MEKs, damit aeltere Backups weiterhin
  entschluesselbar bleiben.
  Quelle: <https://docs.oracle.com/en/database/oracle/oracle-database/19/asoag/introduction-to-transparent-data-encryption.html>
- `ORIGIN` unterscheidet LOCAL (lokal erzeugt) und IMPORTED (formal importiert).
  Quelle: <https://docs.oracle.com/en/database/oracle/oracle-database/21/refrn/V-ENCRYPTION_KEYS.html>
- `ewallet.p12` ist ein PKCS#12-Container, ab 19.22 AES-256 statt 3DES.
  Quelle: <https://docs.oracle.com/en/database/oracle/oracle-database/26/dbseg/oracle-database-fips-140-settings.html>

**Nicht belegt:** der konkrete Byte-Offset des gewrappten Keys im Datafile-Header. Unsere
Messung (Block 1, Byte 785 bei 8K) ist eine eigene Beobachtung, keine dokumentierte Struktur.

## Angriffskette

Vollstaendige Kette, alle Glieder noetig:

`ewallet.p12` plus Passphrase -> MEK im Klartext -> `ENCRYPTEDKEY` entschluesseln ->
TEK im Klartext -> Datenbloecke entschluesseln.

Der gewrappte TEK allein ist ohne den passenden MEK kryptografisch wertlos.

## Angriffsflaechen - Einordnung

| Angriff | Bewertung | Voraussetzungen |
|---|---|---|
| Ciphertext-Existenzvergleich Prod gegen Non-Prod | real, geringer Aufwand | Lesezugriff auf Non-Prod-Datafiles und Prod-Backups, kein Keystore |
| Rueckschluss auf Datenaenderungen ueber Backup-Generationen | real, geringer Aufwand | mehrere Prod-Backups, kein Keystore |
| Known-Plaintext gegen AES-256-XTS | theoretisch, praktisch nicht ausnutzbar | akademischer Angriff braucht 2^32 Klartextbloecke und 2^96 Operationen, fuer 128-Bit-Blockchiffren nicht praktikabel |
| Brute Force gegen AES-256 | hypothetisch | 2^256 Schluesselraum, NIST empfiehlt AES-256 bis mindestens 2031 |
| Non-Prod-Keystore plus Prod-Backup | **real und gravierend**, wenn der Keystore aus Prod kopiert wurde | Keystore-Datei und Passphrase |

Quellen: <https://www.nist.gov/publications/recommendation-block-cipher-modes-operation-xts-aes-mode-confidentiality-storage>,
<https://eprint.iacr.org/2019/825.pdf>, <https://csrc.nist.gov/pubs/sp/800/57/pt1/r5/final>

**Nicht belegt:** Ciphertext-Existenzvergleich und Aenderungsrueckschluss sind in
Oracle-Dokumentation nicht als benannte Angriffsklasse beschrieben. Sie sind
kryptografisch ableitbar und im Lab an byteidentischen Bloecken sichtbar.

## OKV - belegte Schutzmechanismen

Woertlich: "Managing keys in Oracle Key Vault mitigates risks associated with disk-based
private keys, including key theft, unauthorized copying and sharing of keys, and key loss."
Quelle: <https://docs.oracle.com/en/database/oracle/key-vault/21.11/okvag/okv_intro.html>

| Merkmal | Software-Keystore | OKV |
|---|---|---|
| Schluessel-Extraktion | Datei plus Passphrase genuegt fuer alle Schluessel | Non-Extractable Keys konfigurierbar |
| Kopierbarkeit | Datei beliebig kopierbar | kein lokales File, Zugang nur ueber KMIP/TLS |
| Audit je Schluesselzugriff | nicht vorhanden | vollstaendiger Audit-Trail |
| Separation of Duties | DBA haelt Keystore und DB | drei Rollen: Key Administrator, System Administrator, Audit Manager |
| RAC und Data Guard | Wallet manuell auf alle Knoten kopieren | Propagation ueber Endpoints |
| Zugriff je Umgebung | keine Trennung | getrennte Virtual Wallets und Endpoint Groups |
| Schluesselverlust | Passwortverlust bedeutet Datenverlust | zentrale Sicherung und Recovery |
| Compliance-Reporting | nicht vorhanden | Endpoint Activity, User Activity, TDE Key Metadata, Backup History |

Rollentrennung woertlich: "In a strict separation of duties environment, different users are
responsible for different functions. For example, for endpoints, the operations to manage an
endpoint and grant permissions to the endpoint must be done by different users."
Quelle: <https://docs.oracle.com/en/database/oracle/key-vault/21.8/okvag/stig.html>

Lifecycle woertlich: "Failed access attempts, non-compliant keys, and keys that have not been
rotated for too long will no longer go undetected."
Quelle: <https://docs.oracle.com/en/database/oracle/key-vault/21.11/okvag/okv_intro.html>

Weitere Quellen: <https://docs.oracle.com/en/database/oracle/key-vault/21.2/okvag/okv_concepts.html>,
<https://docs.oracle.com/en/database/oracle/key-vault/21.4/okvag/okv_manage_endpoints.html>,
<https://docs.oracle.com/en/database/oracle/key-vault/21.10/okvag/okv_managing_users.html>,
<https://docs.oracle.com/en/database/oracle/key-vault/18.7/okvag/monitoring.html>

## OKV - Klon-Trennung

Belegte Konstrukte: Virtual Wallets mit Rechten Read Only, Read and Modify, Manage Wallet,
je Benutzer, Gruppe, Endpoint oder Endpoint Group. Endpoint Groups fuer kollektiven
Wallet-Zugriff. Entzug jederzeit moeglich.

**Nicht belegt:** ein dediziertes, von Oracle dokumentiertes Prod/Non-Prod-Klon-Muster.
Die Konstrukte sind belegt, das Muster ist daraus ableitbar. Sekundaerquelle zum Klonen mit
OKV: <https://www.dbi-services.com/blog/clone-oracle-database-configured-with-oracle-key-vault-okv/>

## OKV - Gegenposition, fair

- Verfuegbarkeitsabhaengigkeit: die DB braucht OKV beim Start und bei Schluesselbedarf.
  Standalone ist nur fuer Test und Dev vorgesehen.
- Mindestarchitektur: Primary-Standby mit zwei Servern fuer Produktion, oder
  Multi-Master-Cluster mit mindestens zwei Read-Write-Knoten. Woertlich: "For single data
  centers where data does not leave the data center, consider using a 2-node cluster
  deployment (one read-write pair) of Oracle Key Vault, instead of a primary-standby
  deployment."
  Quelle: <https://docs.oracle.com/en/database/oracle/key-vault/21.2/okvag/okv_concepts.html>
- Lizenz: OKV ist ein eigenstaendiges Produkt, nicht Teil der Advanced Security Option.
  Die enthaltenen Restricted-Use-Lizenzen gelten nur fuer den OKV-Betrieb selbst.
  Quelle: <https://docs.oracle.com/en/database/oracle/key-vault/18.6/okvli/licensing-information.html>
- Betriebsaufwand und Netzwerkabhaengigkeit ueber KMIP/TLS: aus der Architektur ableitbar,
  in der Doku nicht als Nachteil benannt. **Nicht belegt** als Doku-Aussage.
- **Nicht belegt:** OKV-Listenpreis, automatische zeitgesteuerte MEK-Rotation ohne
  SQL-Eingriff, granularer Zugriff auf einzelne MEK-Versionen, Unveraenderlichkeit des
  Audit-Logs.

## Standards

- DISA STIG Oracle 19c V-270574 empfiehlt TDE fuer Data at Rest, macht **keine** Vorgabe
  zur Keystore-Architektur. Quelle:
  <https://www.stigviewer.com/stigs/oracle_database_19c/2025-06-24/finding/V-270574>
- V-270571 fordert FIPS-140-validierte Kryptomodule. Quelle:
  <https://www.stigviewer.com/stigs/oracle_database_19c/2025-02-14/finding/V-270571>
- OKV bietet einen eigenen STIG-Haertungsmodus, Rollentrennung erzwingbar ab 21.9.
  Quelle: <https://docs.oracle.com/en/database/oracle/key-vault/21.8/okvag/stig.html>
- NIST SP 800-57 Part 2 definiert Separation of Duties als Prinzip. Quelle:
  <https://csrc.nist.gov/pubs/sp/800/57/pt2/r1/final>
- **Nicht belegt:** ein Control in STIG, CIS oder PCI-DSS, das externes Key Management
  gegenueber einem Software-Keystore ausdruecklich fordert. CIS-Volltext erfordert
  Registrierung, PCI-DSS-Volltext war nicht zugaenglich.

## Einordnung der beiden Kundeneinwaende

**Einwand 1, "wir aendern eh nur den MEK, dann ist Test gleich Prod":** beschreibt das
Verhalten korrekt, zieht aber den falschen Schluss. Die Frage ist nicht, ob die Bloecke
gleich bleiben - sie bleiben es. Die Frage ist, wo der Schluessel liegt. Beim file-basierten
Modell wandert der Keystore mit dem Klon, und damit der Produktionsschluessel samt Historie.
OKV loest das ueber getrennte Wallets und Endpoint-Rechte, unabhaengig von jeder Rotation.

**Einwand 2, "mit TS-Key-Infos aus der Test die Prod entschluesseln":** in der strikten
Lesart unzutreffend. `ENCRYPTEDKEY` ist mit dem MEK der jeweiligen Datenbank gewrappt, ohne
den Prod-MEK wertlos. Im Lab scheitert bereits der Restore mit ORA-28374. Der reale Kern
liegt anders: ist der Non-Prod-Keystore eine Kopie des Prod-Keystores, enthaelt er die
Prod-MEKs, und dann genuegt er zusammen mit einem Prod-Backup fuer die vollstaendige
Entschluesselung. `ORIGIN` zeigt dabei LOCAL, die Herkunft ist nicht erkennbar.
