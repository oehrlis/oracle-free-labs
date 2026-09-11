#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: make_protocol.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026-09-06
# Version....: 0.1.0
# Purpose....: Turn a run_all.sh log into a Markdown test protocol
# Notes......: Reads the log written by run_all.sh and emits a protocol with the
#              result table, the verdict of every step and the measured values
#              (canary block counts, MASTERKEYID, ENCRYPTEDKEY, KEY_VERSION).
#              Derived from the log rather than assembled by hand, so the
#              protocol can be regenerated from the same evidence at any time.
# Reference..: https://github.com/oehrlis/oradba
# License....: Apache License Version 2.0, January 2004 as shown
#              at http://www.apache.org/licenses/
# ------------------------------------------------------------------------------
# CHANGE LOG:
# 2026-09-06  oes  Initial release                                        0.1.0
# 2026-09-11  oes  Fail loudly on an unusable log, atomic output       0.2.0
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# Default Values
# ------------------------------------------------------------------------------
set -euo pipefail
SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")
VERSION="0.3.0"
LOG_FILE=""
OUT_FILE=""

# ------------------------------------------------------------------------------
# usage: show script usage
# ------------------------------------------------------------------------------
usage() {
    cat <<EOF
${SCRIPT_NAME} ${VERSION}

Usage: ${SCRIPT_NAME} --log FILE [--out FILE]

  Turn a run_all.sh log into a Markdown test protocol.

Options:
  -h, --help       Show this help and exit
      --log FILE   The run_all.sh log to read (required)
      --out FILE   Where to write the protocol (default: stdout)

Examples:
  ${SCRIPT_NAME} --log data/xchange/evidence/run_20260906_000339.log
  ${SCRIPT_NAME} --log run.log --out doc/tde-e2e-protokoll.md

EOF
}

# ------------------------------------------------------------------------------
# Parse arguments
# ------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --log)     LOG_FILE="$2"; shift 2 ;;
        --out)     OUT_FILE="$2"; shift 2 ;;
        *) echo "ERROR: Unknown option $1" >&2; usage; exit 1 ;;
    esac
done

if [[ -z "${LOG_FILE}" || ! -f "${LOG_FILE}" ]]; then
    echo "ERROR: --log must point to an existing file" >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# main
# ------------------------------------------------------------------------------
main() {
    python3 - "${LOG_FILE}" <<'PYEOF'
import re, sys, pathlib, datetime

log = pathlib.Path(sys.argv[1]).read_text(errors="replace").splitlines()

steps = []          # ordered step records
cur = None
result_rows = []
in_results = False

step_re    = re.compile(r'^\s+STEP (\d+): (.+)$')
verdict_re = re.compile(r'^VERDICT: (PASS|FAIL) - (.*)$')
# Not anchored: some steps log the line through lib_info, which prefixes a
# timestamp, and anchoring silently dropped those measurements.
canary_re  = re.compile(r'canary[^:]*:\s+(identical \d+ differing \d+ total \d+)')
cmp_re     = re.compile(r'^(blocks compared|identical|differing):\s*(\d+)')
mkid_re    = re.compile(r'MASTERKEYID\s*:\s*([0-9A-Fa-f]{32})')
tek_re     = re.compile(r'Wrapped TEK\s*:\s*([0-9A-Fa-f]{64})')
row_re     = re.compile(r'^(\d{2})\s+(PASS|FAIL|SKIP)\s+(\S+)\s+(.*)$')
ora_re     = re.compile(r'\b(ORA-\d{5}|RMAN-\d{5})\b')

for line in log:
    m = step_re.match(line)
    if m:
        cur = {"nr": m.group(1), "desc": m.group(2).strip(),
               "verdict": None, "msg": "", "canary": [], "cmp": {},
               "mkid": [], "tek": [], "ora": []}
        steps.append(cur)
        continue
    if line.startswith("NR    Result"):
        in_results = True
        continue
    if in_results:
        r = row_re.match(line)
        if r:
            result_rows.append(r.groups())
            continue
    if cur is None:
        continue
    m = verdict_re.match(line)
    if m:
        cur["verdict"], cur["msg"] = m.group(1), m.group(2).strip()
        continue
    m = canary_re.search(line)
    if m:
        cur["canary"].append(m.group(1))
        continue
    m = cmp_re.match(line)
    if m:
        cur["cmp"][m.group(1)] = m.group(2)
        continue
    for m in mkid_re.finditer(line):
        if m.group(1) not in cur["mkid"]:
            cur["mkid"].append(m.group(1))
    for m in tek_re.finditer(line):
        if m.group(1) not in cur["tek"]:
            cur["tek"].append(m.group(1))
    for m in ora_re.finditer(line):
        if m.group(1) not in cur["ora"]:
            cur["ora"].append(m.group(1))

durations = {r[0]: r[2] for r in result_rows}
results   = {r[0]: r[1] for r in result_rows}

out = []
w = out.append
w("# TDE Verifikationslauf - Testprotokoll")
w("")
w(f"Erzeugt: {datetime.datetime.now().strftime('%Y-%m-%d %H:%M')}  ")
w(f"Quelle: `{pathlib.Path(sys.argv[1]).name}`")
w("")
w("Dieses Protokoll ist aus dem Lauf-Log abgeleitet und laesst sich jederzeit")
w("aus demselben Log neu erzeugen. Die Zahlen stammen nicht aus einer")
w("Nacherzaehlung, sondern aus den Messzeilen des Laufs.")
w("")

total = len(result_rows)
passed = sum(1 for r in result_rows if r[1] == "PASS")

# A log with neither step headers nor a result table is not an aborted run, it
# is the wrong input file. Saying "aborted" here once turned a 21-of-21 run into
# a protocol that claimed the opposite, and the claim looked well-formed enough
# to pass markdownlint. Refuse instead of guessing, and name the fix.
if not steps and not result_rows:
    sys.stderr.write(
        "ERROR: no 'STEP nn:' headers and no result table found in "
        f"{sys.argv[1]}\n"
        "       This log cannot produce a protocol. Most likely it is the\n"
        "       evidence log (data/xchange/evidence/run_<ts>.log), which does\n"
        "       not carry them; use the stdout capture of the run instead.\n"
        "       Nothing was written.\n")
    sys.exit(2)

# The result table and the detail section are parsed from different markers, so
# they can disagree - and a protocol whose summary says 21 while its detail holds
# 20 is worse than no protocol, because nothing in it points at the gap. Measured
# 2026-09-11: with the run log kept under data/xchange, step 00 deleted the
# directory and with it the log's head, so the table had 21 rows and the detail
# had 20. The log now lives in artefacts/, but a generator that can emit a
# self-contradicting document must say so rather than rely on that.
missing = sorted({nr for nr, *_ in result_rows} - {s["nr"] for s in steps})
if missing:
    sys.stderr.write(
        f"WARNING: the result table lists {len(result_rows)} step(s) but only "
        f"{len(steps)} have a detail section.\n"
        f"         Missing in detail: {', '.join(missing)}\n"
        "         The log is incomplete for those steps - most often the head of\n"
        "         the log was lost. The protocol says so on its face.\n")

w("## Ergebnis")
w("")
if total:
    w(f"{passed} von {total} Schritten bestanden.")
    if missing:
        w("")
        # Wrapped by hand: markdownlint holds this file to 120 columns, and a
        # generator that emits a line the project's own linter rejects is a
        # generator that breaks the build it feeds.
        w(f"**Unvollstaendig:** fuer Schritt {', '.join(missing)} fehlt der Detailabschnitt -")
        w("das Log enthaelt dazu keine Ausgabe. Die Ergebniszeile stammt aus der")
        w("Ergebnistabelle, der Ablauf ist nicht dokumentiert.")
else:
    # Steps but no table: run_all.sh prints the table even when a step fails,
    # so a missing table means the run was cut off (kill, crash, lost stdout).
    sys.stderr.write(
        f"WARNING: {len(steps)} step(s) found but no result table - the run was "
        "cut off. Protocol is partial.\n")
    w(f"Der Lauf hat keine Ergebnistabelle geschrieben - er wurde abgebrochen. "
      f"{len(steps)} Schritt(e) sind im Log dokumentiert.")
w("")
w("| Nr | Ergebnis | Dauer | Schritt |")
w("|----|----------|-------|---------|")
for nr, res, dur, desc in result_rows:
    w(f"| {nr} | {res} | {dur} | {desc} |")
w("")

w("## Schritte im Detail")
w("")
for s in steps:
    res = results.get(s["nr"], s["verdict"] or "-")
    w(f"### Schritt {s['nr']} - {s['desc']}")
    w("")
    w(f"Ergebnis: **{res}**" + (f", Dauer {durations[s['nr']]}" if s["nr"] in durations else ""))
    w("")
    if s["msg"]:
        w("Verdict:")
        w("")
        w("```text")
        for chunk in re.findall(r'.{1,110}(?:\s|$)', s["msg"]):
            w(chunk.rstrip())
        w("```")
        w("")
    if s["canary"]:
        w("Canary-Blockvergleich:")
        w("")
        for c in s["canary"]:
            w(f"- `{c}`")
        w("")
    if s["cmp"]:
        parts = ", ".join(f"{k} {v}" for k, v in s["cmp"].items())
        w(f"Blockvergleich gesamt: `{parts}`")
        w("")
    if s["mkid"] or s["tek"]:
        w("Gemessene Schluesselwerte:")
        w("")
        for v in s["mkid"]:
            w(f"- MASTERKEYID `{v}`")
        for v in s["tek"]:
            w(f"- ENCRYPTEDKEY `{v}`")
        w("")
    if s["ora"]:
        w(f"Beobachtete Fehlercodes: {', '.join('`' + o + '`' for o in s['ora'])}")
        w("")

# Collapse consecutive blank lines so the result satisfies MD012.
collapsed = []
for line in out:
    if line == "" and collapsed and collapsed[-1] == "":
        continue
    collapsed.append(line)
print("\n".join(collapsed).rstrip() + "\n", end="")
PYEOF
}

if [[ -n "${OUT_FILE}" ]]; then
    # Write via a temp file. "main > ${OUT_FILE}" truncates the target before
    # the parser runs, so a parser failure left the previous protocol destroyed
    # and replaced by nothing. Only move into place once main succeeded.
    TMP_OUT="$(mktemp "${TMPDIR:-/tmp}/${SCRIPT_NAME}.XXXXXX")"
    trap 'rm -f "${TMP_OUT}"' EXIT
    if main > "${TMP_OUT}"; then
        mv "${TMP_OUT}" "${OUT_FILE}"
        trap - EXIT
        echo "protocol written to ${OUT_FILE}"
    else
        rc=$?
        echo "ERROR: protocol not generated, ${OUT_FILE} left unchanged" >&2
        exit "${rc}"
    fi
else
    main
fi
# --- EOF ----------------------------------------------------------------------
