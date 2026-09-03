#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: tde_evidence.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026-09-03
# Version....: 0.1.0
# Purpose....: Collect one labelled evidence set for the TDE restore verification:
#              V$ key chain snapshots from the database plus block level
#              fingerprints of the encrypted datafiles on the host.
# Notes......: Read-only by design. It never writes to a datafile, never changes
#              the database and never deletes an evidence set, so there is no
#              --yes and no --delete flag - there is nothing to confirm.
#              Datafiles are read on the host through the oradata bind mount:
#              /opt/oracle/oradata in the container maps to data/<service> here.
# Reference..: https://github.com/oehrlis/oracle-free-labs
# License....: Apache License Version 2.0, January 2004 as shown
#              at http://www.apache.org/licenses/
# ------------------------------------------------------------------------------
# CHANGE LOG:
# 2026-09-03  oes  Initial release                                        0.1.0
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# Default Values
# ------------------------------------------------------------------------------
set -euo pipefail
SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VERSION="0.1.0"
VERBOSE=${VERBOSE:-"FALSE"}
DRY_RUN=${DRY_RUN:-"FALSE"}

FINGERPRINT_TOOL="${SCRIPT_DIR}/block_fingerprint.py"
EVIDENCE_ROOT="${REPO_DIR}/data/xchange/evidence"
CONTAINER_ORADATA="/opt/oracle/oradata"
CONTAINER_XCHANGE="/opt/oracle/xchange"

SERVICE=""
PDB_NAME=""
LABEL=""
TABLESPACE="USERS"
MARKER=""
COMPARE_A=""
COMPARE_B=""
MODE="collect"

# ------------------------------------------------------------------------------
# Function: log, log_info, log_warn, log_error, log_debug
# Purpose.: Consistent logging to stdout/stderr
# ------------------------------------------------------------------------------
log_info()  { echo "$(date '+%Y-%m-%d %H:%M:%S') INFO  $*"; }
log_warn()  { echo "$(date '+%Y-%m-%d %H:%M:%S') WARN  $*" >&2; }
log_error() { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR $*" >&2; }
log_debug() {
    [[ "${VERBOSE}" == "TRUE" ]] || return 0
    echo "$(date '+%Y-%m-%d %H:%M:%S') DEBUG $*"
}

# ------------------------------------------------------------------------------
# usage: show script usage
# ------------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} --service <name> --pdb <name> --label <label> [OPTIONS]
       ${SCRIPT_NAME} --compare <label_a> <label_b>

  Collect or compare evidence sets for the TDE restore verification test.

  A collected set contains, per label:
    keyproof_cdb.log      ssenc_keyproof.sql output from CDB\$ROOT
    keyproof_pdb.log      ssenc_keyproof.sql output from the PDB
    datafiles.tsv         encrypted tablespace datafiles with block size
    <datafile>.fp         one block level fingerprint per datafile
    plaintext_<df>.log    clear-text marker scan, when --marker is given
    manifest.txt          label, timestamp, service, PDB and file inventory

Options:
  -s, --service NAME    Compose service / container name (e.g. odbencprod)
  -p, --pdb NAME        PDB holding the encrypted tablespace
  -l, --label LABEL     Name of this evidence set (e.g. baseline, restore_b)
  -t, --tablespace NAME Encrypted tablespace to inspect (default: ${TABLESPACE})
  -m, --marker STRING   Canary marker to scan the datafiles for in clear text
  -c, --compare A B     Compare two already collected evidence sets
  -h, --help            Show this help and exit
  -v, --verbose         Enable verbose output
  -d, --dry-run         Show what would run, change nothing

Examples:
  ${SCRIPT_NAME} -s odbencprod -p ODBENCPROD -l baseline -m 'OEHRLI-CANARY-01'
  ${SCRIPT_NAME} -s odbencdev  -p ODBENCPROD -l restore_as_encrypted
  ${SCRIPT_NAME} --compare baseline restore_as_encrypted

EOF
}

# ------------------------------------------------------------------------------
# Function: run
# Purpose.: Execute a command, or only report it in dry-run mode
# Args....: $@  command and arguments
# Returns.: exit code of the command, 0 in dry-run
# Output..: command output, or the DRY-RUN line
# Depends.: none
# Example.: run mkdir -p /tmp/evidence
# ------------------------------------------------------------------------------
run() {
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        log_info "DRY-RUN: $*"
        return 0
    fi
    "$@"
}

# ------------------------------------------------------------------------------
# Function: require_container
# Purpose.: Fail early unless the given container is running
# Args....: $1  container name
# Returns.: 0   container is running
#           1   container is missing or not running
# Output..: error message on stderr when not running
# Depends.: docker
# Example.: require_container odbencprod
# ------------------------------------------------------------------------------
require_container() {
    local name="$1"
    local state
    state="$(docker inspect -f '{{.State.Status}}' "${name}" 2>/dev/null || echo "absent")"
    if [[ "${state}" != "running" ]]; then
        log_error "container '${name}' is ${state}, expected running"
        return 1
    fi
    log_debug "container '${name}' is running"
    return 0
}

# ------------------------------------------------------------------------------
# Function: sqlplus_run
# Purpose.: Run a SQL*Plus snippet as SYSDBA inside a lab container
# Args....: $1  container name
#           $2  SQL text, fed to SQL*Plus on stdin
# Returns.: exit code of SQL*Plus
# Output..: SQL*Plus output on stdout
# Depends.: docker, sqlplus inside the container
# Example.: sqlplus_run odbencprod 'SELECT 1 FROM dual;'
# ------------------------------------------------------------------------------
sqlplus_run() {
    local name="$1"
    local sql="$2"
    log_debug "sqlplus on ${name}: $(echo "${sql}" | head -1)"
    printf '%s\n' "${sql}" | docker exec -i "${name}" sqlplus -S / as sysdba
}

# ------------------------------------------------------------------------------
# Function: collect_key_evidence
# Purpose.: Spool the TDE key chain snapshot from CDB$ROOT and from the PDB
# Args....: $1  container name
#           $2  PDB name
#           $3  target directory on the host
# Returns.: 0   success
# Output..: writes keyproof_cdb.log and keyproof_pdb.log
# Depends.: docker, config/common/scripts/ssenc_keyproof.sql in the container
# Example.: collect_key_evidence odbencprod ODBENCPROD /path/to/evidence/baseline
# ------------------------------------------------------------------------------
collect_key_evidence() {
    local name="$1" pdb="$2" outdir="$3"
    local rel
    rel="${outdir#"${REPO_DIR}/data/xchange"}"

    log_info "collecting key chain evidence from ${name} (CDB\$ROOT)"
    run sqlplus_run "${name}" "
SET ECHO OFF TERMOUT ON
SPOOL ${CONTAINER_XCHANGE}${rel}/keyproof_cdb.log
@/opt/oracle/common/scripts/ssenc_keyproof.sql
SPOOL OFF
EXIT
"
    log_info "collecting key chain evidence from ${name} (PDB ${pdb})"
    run sqlplus_run "${name}" "
SET ECHO OFF TERMOUT ON
ALTER SESSION SET CONTAINER=${pdb};
SPOOL ${CONTAINER_XCHANGE}${rel}/keyproof_pdb.log
@/opt/oracle/common/scripts/ssenc_keyproof.sql
SPOOL OFF
EXIT
"
}

# ------------------------------------------------------------------------------
# Function: collect_datafile_list
# Purpose.: Write the encrypted tablespace datafiles with their block size
# Args....: $1  container name
#           $2  PDB name
#           $3  tablespace name
#           $4  target directory on the host
# Returns.: 0   success
# Output..: writes datafiles.tsv as "container_path<TAB>block_size"
# Depends.: docker, sqlplus
# Example.: collect_datafile_list odbencprod ODBENCPROD USERS /tmp/ev
# ------------------------------------------------------------------------------
collect_datafile_list() {
    local name="$1" pdb="$2" tbs="$3" outdir="$4"
    log_info "listing datafiles of tablespace ${tbs} in PDB ${pdb}"
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        log_info "DRY-RUN: would query dba_data_files for ${tbs}"
        return 0
    fi
    sqlplus_run "${name}" "
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 400 TRIMSPOOL ON ECHO OFF
ALTER SESSION SET CONTAINER=${pdb};
SELECT df.file_name||CHR(9)||ts.block_size
FROM   dba_data_files df, dba_tablespaces ts
WHERE  df.tablespace_name = ts.tablespace_name
AND    df.tablespace_name = UPPER('${tbs}')
ORDER  BY df.relative_fno;
EXIT
" | grep -E "^/.*\s[0-9]+$" > "${outdir}/datafiles.tsv"
    log_info "found $(wc -l < "${outdir}/datafiles.tsv" | tr -d ' ') datafile(s)"
}

# ------------------------------------------------------------------------------
# Function: host_path
# Purpose.: Translate a container datafile path to its host path
# Args....: $1  container path under /opt/oracle/oradata
#           $2  compose service name
# Returns.: 0   success, 1 if the path is outside the oradata mount
# Output..: host path on stdout
# Depends.: none
# Example.: host_path /opt/oracle/oradata/FREE/users01.dbf odbencprod
# ------------------------------------------------------------------------------
host_path() {
    local cpath="$1" svc="$2"
    if [[ "${cpath}" != "${CONTAINER_ORADATA}/"* ]]; then
        log_error "datafile '${cpath}' is not under ${CONTAINER_ORADATA}, cannot map to host"
        return 1
    fi
    echo "${REPO_DIR}/data/${svc}/${cpath#"${CONTAINER_ORADATA}/"}"
}

# ------------------------------------------------------------------------------
# Function: collect_fingerprints
# Purpose.: Fingerprint every listed datafile and optionally scan for the marker
# Args....: $1  compose service name
#           $2  target directory on the host
#           $3  canary marker, may be empty
# Returns.: 0   success
# Output..: writes <basename>.fp and, with a marker, plaintext_<basename>.log
# Depends.: python3, block_fingerprint.py
# Example.: collect_fingerprints odbencprod /tmp/ev 'OEHRLI-CANARY-01'
# ------------------------------------------------------------------------------
collect_fingerprints() {
    local svc="$1" outdir="$2" marker="$3"
    local cpath bsize hpath base
    if [[ ! -s "${outdir}/datafiles.tsv" ]]; then
        log_warn "no datafiles.tsv in ${outdir}, skipping fingerprints"
        return 0
    fi
    while IFS=$'\t' read -r cpath bsize; do
        [[ -n "${cpath}" ]] || continue
        bsize="${bsize//[[:space:]]/}"
        hpath="$(host_path "${cpath}" "${svc}")"
        base="${cpath##*/}"
        if [[ ! -f "${hpath}" ]]; then
            log_error "datafile not readable on host: ${hpath}"
            return 1
        fi
        log_info "fingerprinting ${base} (block size ${bsize})"
        run python3 "${FINGERPRINT_TOOL}" fingerprint "${hpath}" \
            --block-size "${bsize}" --out "${outdir}/${base}.fp"
        if [[ -n "${marker}" ]]; then
            log_info "scanning ${base} for the clear-text marker"
            if [[ "${DRY_RUN}" == "TRUE" ]]; then
                log_info "DRY-RUN: would scan ${hpath} for '${marker}'"
            else
                # A hit means the data sits in the clear; do not abort on it,
                # the finding belongs in the protocol.
                python3 "${FINGERPRINT_TOOL}" scan-plaintext "${hpath}" "${marker}" \
                    --block-size "${bsize}" > "${outdir}/plaintext_${base}.log" 2>&1 || true
                grep -E "^(HITS|no hits)" "${outdir}/plaintext_${base}.log" || true
            fi
        fi
    done < "${outdir}/datafiles.tsv"
}

# ------------------------------------------------------------------------------
# Function: write_manifest
# Purpose.: Record what this evidence set is and what it contains
# Args....: $1  target directory, $2 service, $3 pdb, $4 label, $5 tablespace
# Returns.: 0   success
# Output..: writes manifest.txt
# Depends.: docker, git
# Example.: write_manifest /tmp/ev odbencprod ODBENCPROD baseline USERS
# ------------------------------------------------------------------------------
write_manifest() {
    local outdir="$1" svc="$2" pdb="$3" label="$4" tbs="$5"
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        log_info "DRY-RUN: would write ${outdir}/manifest.txt"
        return 0
    fi
    {
        echo "label: ${label}"
        echo "collected: $(date '+%Y-%m-%d %H:%M:%S %z')"
        echo "service: ${svc}"
        echo "pdb: ${pdb}"
        echo "tablespace: ${tbs}"
        echo "image: $(docker inspect -f '{{.Config.Image}}' "${svc}" 2>/dev/null || echo unknown)"
        echo "repo_commit: $(git -C "${REPO_DIR}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
        echo "tool_version: ${SCRIPT_NAME} ${VERSION}"
        echo "files:"
        (cd "${outdir}" && ls -1)
    } > "${outdir}/manifest.txt"
    log_info "manifest written to ${outdir}/manifest.txt"
}

# ------------------------------------------------------------------------------
# Function: do_collect
# Purpose.: Collect a complete labelled evidence set
# Args....: none, uses the parsed globals
# Returns.: 0   success
# Output..: progress on stdout, files under data/xchange/evidence/<label>
# Depends.: docker, python3
# Example.: do_collect
# ------------------------------------------------------------------------------
do_collect() {
    local outdir="${EVIDENCE_ROOT}/${LABEL}"
    require_container "${SERVICE}"
    run mkdir -p "${outdir}"
    log_info "evidence set '${LABEL}' -> ${outdir}"
    collect_key_evidence   "${SERVICE}" "${PDB_NAME}" "${outdir}"
    collect_datafile_list  "${SERVICE}" "${PDB_NAME}" "${TABLESPACE}" "${outdir}"
    collect_fingerprints   "${SERVICE}" "${outdir}" "${MARKER}"
    write_manifest         "${outdir}" "${SERVICE}" "${PDB_NAME}" "${LABEL}" "${TABLESPACE}"
}

# ------------------------------------------------------------------------------
# Function: do_compare
# Purpose.: Compare the fingerprints of two evidence sets datafile by datafile
# Args....: $1  label A, $2 label B
# Returns.: 0   success, 1 if a set is missing
# Output..: one comparison block per matching datafile
# Depends.: python3, block_fingerprint.py
# Example.: do_compare baseline restore_as_encrypted
# ------------------------------------------------------------------------------
do_compare() {
    local a="$1" b="$2"
    local dir_a="${EVIDENCE_ROOT}/${a}" dir_b="${EVIDENCE_ROOT}/${b}"
    local fp base counterpart found=0
    for dir in "${dir_a}" "${dir_b}"; do
        if [[ ! -d "${dir}" ]]; then
            log_error "evidence set not found: ${dir}"
            return 1
        fi
    done
    for fp in "${dir_a}"/*.fp; do
        [[ -e "${fp}" ]] || continue
        base="${fp##*/}"
        counterpart="${dir_b}/${base}"
        if [[ ! -f "${counterpart}" ]]; then
            log_warn "no counterpart for ${base} in set '${b}', skipping"
            continue
        fi
        found=$((found + 1))
        echo
        python3 "${FINGERPRINT_TOOL}" compare "${fp}" "${counterpart}" \
            --label-a "${a}/${base}" --label-b "${b}/${base}"
    done
    if [[ "${found}" -eq 0 ]]; then
        log_error "no matching fingerprints between '${a}' and '${b}' - nothing compared"
        return 1
    fi
    log_info "compared ${found} datafile(s)"
}

# ------------------------------------------------------------------------------
# Parse arguments
# ------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)       usage; exit 0 ;;
        -v|--verbose)    VERBOSE="TRUE"; shift ;;
        -d|--dry-run)    DRY_RUN="TRUE"; shift ;;
        -s|--service)    SERVICE="${2:-}"; shift 2 ;;
        -p|--pdb)        PDB_NAME="${2:-}"; shift 2 ;;
        -l|--label)      LABEL="${2:-}"; shift 2 ;;
        -t|--tablespace) TABLESPACE="${2:-}"; shift 2 ;;
        -m|--marker)     MARKER="${2:-}"; shift 2 ;;
        -c|--compare)    MODE="compare"; COMPARE_A="${2:-}"; COMPARE_B="${3:-}"; shift 3 ;;
        *)  log_error "Unknown option $1"; usage; exit 1 ;;
    esac
done

# ------------------------------------------------------------------------------
# main
# ------------------------------------------------------------------------------
main() {
    log_info "Starting ${SCRIPT_NAME} ${VERSION}"
    if [[ ! -f "${FINGERPRINT_TOOL}" ]]; then
        log_error "fingerprint tool missing: ${FINGERPRINT_TOOL}"
        exit 1
    fi
    case "${MODE}" in
        compare)
            if [[ -z "${COMPARE_A}" || -z "${COMPARE_B}" ]]; then
                log_error "--compare needs two labels"
                usage; exit 1
            fi
            do_compare "${COMPARE_A}" "${COMPARE_B}"
            ;;
        collect)
            if [[ -z "${SERVICE}" || -z "${PDB_NAME}" || -z "${LABEL}" ]]; then
                log_error "--service, --pdb and --label are required"
                usage; exit 1
            fi
            do_collect
            ;;
        *)  log_error "unknown mode ${MODE}"; exit 1 ;;
    esac
    log_info "Done."
}

main "$@"
# --- EOF ----------------------------------------------------------------------
