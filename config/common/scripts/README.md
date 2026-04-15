# Common Database Scripts

This folder contains reusable **Oracle Database administration and security scripts**
that support automation, provisioning, and cleanup tasks for pluggable databases (PDBs)
and schemas.

The scripts are intended for use in **containerized lab/demo environments** and can
also serve as reference for production-ready automation.

## Structure

```text
config/common/scripts/
├── *.sh          # Shell scripts for DB patching, audit, and automation
├── *.sql         # SQL*Plus scripts for PDB lifecycle, cleanup, and security
```

## Script Categories

### 🔧 Initialization & Maintenance

* **00\_enable\_unified\_audit.sh** - Enables unified auditing at the Oracle binary level.
* **00\_run\_datapatch.sh** - Runs datapatch for CDBs/PDBs, including JVM updates.
* **01\_check\_unified\_audit.sh** - Verifies if unified auditing is enabled, relinks if required.
* **common\_db\_config.sql** - Common database initialization/configuration script.
* **init\_audit\_config.sql** - Initializes baseline audit configuration.
* **define\_logging\_begin.sql** / **define\_logging\_end.sql** - Standardized logging wrappers.

### 🏗️ PDB Lifecycle Management

* **create\_pdb.sql** - Creates a new pluggable database.
* **clone\_pdb.sql** - Clones a PDB from a given source to a target.
* **create\_pdb\_archive.sql** - Creates an archive of a PDB for reuse.
* **create\_pdb\_from\_archive.sql** - Creates a PDB from a supplied archive.
* **drop\_pdb.sql** - Drops a specific PDB (idempotent, handles already dropped/closed).
* **post\_clone\_task\_audit.sql** - Post-cloning tasks for audit configuration.
* **post\_clone\_task\_df.sql** - Post-cloning tasks for datafiles.

### 🔐 User & Security Management

* **create\_ts\_users.sql** - Creates tablespaces and application users.
* **create\_audit\_policies.sql** - Creates custom audit policies.
* **enable\_audit\_policies.sql** - Enables the created audit policies.
* **lock\_all\_users.sql** - Locks all non-Oracle maintained users.
* **lock\_all\_tenants\_users.sql** - Locks tenant-specific users.
* **unlock\_all\_users.sql** - Unlocks all non-Oracle maintained users.
* **remove\_authentication.sql** - Cleans up authentication-related objects.

### 🧹 Tenant & Metadata Cleanup

* **remove\_users.sql** - Removes non-required schemas/users.
* **remove\_all\_tenants.sql** - Removes **all** tenants, schemas, and data.
* **remove\_classified\_tenants.sql** - Removes tenants based on classification.
* **remove\_all\_metadata.sql** - Purges metadata objects after tenant removal.
* **remove\_classified\_metadata.sql** - Removes metadata marked as classified.
* **review\_classified\_data.sql** - Reviews remaining data for non-confidential tenants.

### 📜 Security Definitions

* **sdsec\_sysobj.sql** - System object security definitions.
* **sdsec\_syspriv.sql** - System privilege security definitions.
* **sdts.sql** - Security-related data transformation script.
* **require\_cdb\_root.sql** - Ensures script execution in CDB\$ROOT only.
* **require\_pdb.sql** - Ensures script execution inside a PDB only.

### 📦 Application Base Schemas

* **EABase\_1558\_Oracle.sql** - Base schema for OraDBA demo.
* **EASchema\_1558\_Oracle.sql** - Schema definition for OraDBA demo.
* **setup\_ea\_baseline.sql** - Sets up OraDBA demo baseline.

### 📑 Templates

* **template\_cdbroot\_wrapper\_script.sql** - Wrapper template for CDB\$ROOT scripts.
* **template\_pdb\_wrapper\_script.sql** - Wrapper template for PDB scripts.

### 📦 Data Export & Import

* **export\_full\_data.sql** - Runs a full Data Pump export for a PDB.
* **import\_full\_network.sql** - Imports full schema/data using network link.

---

## Usage Notes

* SQL scripts are written for **SQL\*Plus** and assume execution as `SYSDBA`
  (or a user with equivalent privileges).
* Scripts log actions to spool files in the format:

  ```bash
  <script_name>*<db_name>*<pdb_name>_<timestamp>.log
  ```

* Most scripts include **safety checks** (e.g., not running in `CDB$ROOT`).
* Shell scripts rely on environment variables such as `ORACLE_HOME` and `ORACLE_SID`.

## Maintenance Guidelines

* Keep script headers consistent (author, date, revision, purpose, license).
* Prefer **modular SQL/PLSQL blocks** with `dbms_output` for clarity in logs.
* When deprecating, move scripts to a dedicated `legacy/` folder rather than deleting.
* Use the provided **template scripts** for new development.
