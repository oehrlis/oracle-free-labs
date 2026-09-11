# Artefact Folder

The `artefacts/` folder stores external artefacts such as software packages and
generated files used to customize the containers, plus the evidence logs of
verification runs.

## What is versioned, and what is not

The folder is ignored by default, so large binaries and throwaway output never
reach the repository. Two named patterns are excluded from that rule in
`.gitignore` and **are** versioned:

| Pattern | Why |
|---|---|
| `artefacts/tde-e2e-run-*.log` | The end-to-end run log. `doc/tde-e2e-protokoll.md` is generated from it, so the protocol can be reproduced from its own source. |
| `artefacts/p4b-*.log` | Evidence of the manual measurement runs cited in `tasks/e2e-facts.md` and `doc/tde-restore-runbook.md`. A citation that does not resolve inside the repository is not evidence. |

Everything else in this folder stays local. Diagnostic snapshots and superseded
evidence sets are deliberately **not** committed: only material that
documentation actually refers to belongs in the repository, or it fills up with
output nobody reads.

## Before adding a log

Run logs carry whatever the scripts printed. Check for secrets first - keystore
passwords, `IDENTIFIED BY` clauses, `WITH SECRET` values, `ORACLE_PWD`:

```bash
grep -icE 'identified by|with secret|oracle_pwd|password *[=:]' artefacts/<file>.log
```

Expected: `0`. The test scripts filter these patterns from their output, so a
non-zero count means a script leaked something and needs fixing before the log
is committed.
