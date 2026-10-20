# DBSAT Archive

The Oracle Database Security Assessment Tool (DBSAT) is **not** part of this
repository. Its license does not allow redistribution.

## Provide DBSAT

1. Download DBSAT with an Oracle account from
   <https://www.oracle.com/database/technologies/security/dbsat.html>
2. Copy the downloaded `dbsat*.zip` unchanged into this folder.
3. Run `make dbsat-seclab`.

The folder is mounted into every service at `/opt/oracle/data/dbsat`.
`config/common/scripts/run_dbsat.sh` picks the newest `dbsat*.zip`. Without a
zip it stops with exit code 4 and prints these steps.

## Notes

- `*.zip` is ignored by Git - the archive never leaves your machine.
- Reports are written to `data/seclab/dbsat/` (`make dbsat-seclab`, the
  service's bind-mounted `/opt/oracle/oradata/dbsat`) and to
  `data/dbsat/<container>/` (`make dbsat CONTAINER=<name>`, copied back from
  the container). Both are ignored by Git.
- DBSAT 4.x needs Java 17+ for the report; both make targets copy a JRE 21
  into the container first (`scripts/provide_jre.sh`, see
  `doc/dbsat-runbook.md`).
