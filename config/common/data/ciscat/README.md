# CIS-CAT Archive

The CIS-CAT Assessor (Lite or Pro) is **not** part of this repository. Its
license does not allow redistribution.

## Provide CIS-CAT

1. Download the Assessor zip:
   - **Lite** (free, registration):
     <https://learn.cisecurity.org/cis-cat-lite>
   - **Pro** (CIS SecureSuite membership, download from CIS WorkBench per CIS
     documentation, unverified):
     <https://www.cisecurity.org/cybersecurity-tools/cis-cat-pro>
2. Copy the zip unchanged into this folder (a symlink works for
   `make ciscat`, which copies it with `docker cp -L` into a root-owned
   directory in the container).
3. Run `make ciscat-list` or `make ciscat CONTAINER=<name>`.

`config/common/scripts/run_ciscat.sh` picks the newest zip whose name contains
`CIS-CAT` or `ciscat` (any case). Without one it stops with exit code 4 and
names both download pages.

## Lite and Pro

See [doc/ciscat-runbook.md](../../../../doc/ciscat-runbook.md#lite-and-pro).

## Notes

- `*.zip` is ignored by Git - the archive never leaves your machine.
- Reports are copied to `data/ciscat/<container>/` (ignored by Git).
- CIS-CAT needs Java 21; `make ciscat` copies a root-owned JRE 21 into the
  container (`scripts/provide_jre.sh --owner root --min-java 21`).
