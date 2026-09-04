#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: run_all.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026-09-04
# Version....: 0.1.0
# Purpose....: Runner for the TDE restore verification test suite.
#              Executes the scripts in scripts/tde-verify/tests/ in numeric
#              order with explicit gates between steps. Each gate checks that
#              the prerequisite state for the next step is present; on failure
#              it aborts with a clear message and the command to resume.
#              Writes a timestamped log to data/xchange/evidence/run_<ts>.log
#              and prints a result table on completion.
# Notes......: Run from the repository root or the scripts/tde-verify directory.
#              Use --yes with all variant steps to avoid interactive prompts.
#              The individual test scripts are also runnable standalone:
#                scripts/tde-verify/tests/20_variant_a.sh --yes
# Reference..: https://github.com/oehrlis/oracle-free-labs
# License....: Apache License Version 2.0, January 2004 as shown
#              at http://www.apache.org/licenses/
# ------------------------------------------------------------------------------
# CHANGE LOG:
# 2026-09-04  oes  Initial release                                        0.1.0
# ------------------------------------------------------------------------------

set -euo pipefail
SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="0.1.0"
VERBOSE=${VERBOSE:-"FALSE"}
DRY_RUN=${DRY_RUN:-"FALSE"}
FORCE_YES=${FORCE_YES:-"FALSE"}

TESTS_DIR="${SCRIPT_DIR}/tests"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
EVIDENCE_ROOT="${REPO_DIR}/data/xchange/evidence"
STATE_FILE="${EVIDENCE_ROOT}/lab_state.env"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
LOG_FILE="${EVIDENCE_ROOT}/run_${TIMESTAMP}.log"

# Step filter options
OPT_ONLY=""
OPT_FROM=""
OPT_TO=""
OPT_LIST=0

# ------------------------------------------------------------------------------
# usage
# ------------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

  Run the TDE restore verification test suite.
  Executes test scripts from tests/ in numeric order with gates between steps.
  Writes a timestamped log and prints a result table on completion.

Options:
  -h, --help          Show this help and exit
  -v, --verbose       Enable verbose output in test scripts
  -d, --dry-run       Pass --dry-run to each script; print steps, change nothing
  -y, --yes           Pass --yes to all scripts (skip interactive prompts)
  -l, --list          List available steps and exit
      --only NR|NAME  Run exactly one step (e.g. --only 20 or --only variant_a)
      --from NR       Run from this step onwards (inclusive)
      --to NR         Run up to this step (inclusive)

Examples:
  ${SCRIPT_NAME} --list
  ${SCRIPT_NAME} --dry-run
  ${SCRIPT_NAME} --yes
  ${SCRIPT_NAME} --only 20 --yes
  ${SCRIPT_NAME} --from 20 --to 40 --yes
  ${SCRIPT_NAME} --from 60 --yes          # resume after step 50

EOF
}

# ------------------------------------------------------------------------------
# Parse arguments
# ------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)    usage; exit 0 ;;
        -v|--verbose) VERBOSE="TRUE"; shift ;;
        -d|--dry-run) DRY_RUN="TRUE"; shift ;;
        -y|--yes)     FORCE_YES="TRUE"; shift ;;
        -l|--list)    OPT_LIST=1; shift ;;
            --only)   OPT_ONLY="${2:-}"; shift 2 ;;
            --from)   OPT_FROM="${2:-}"; shift 2 ;;
            --to)     OPT_TO="${2:-}"; shift 2 ;;
        *) echo "ERROR: Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

# ------------------------------------------------------------------------------
# Step registry
# Each entry: "NR|script_name|description|gate_key|gate_description"
# gate_key is a STATE_FILE key that must exist and be non-empty before this
# step runs. Empty gate_key means no prerequisite check.
# ------------------------------------------------------------------------------
declare -a STEP_REGISTRY=(
    "00|00_reset_lab.sh|Reset both services and verify clean startup||none"
    "10|10_baseline.sh|Create canary tables, READ ONLY, collect baseline evidence||none"
    "15|15_backup.sh|RMAN backup + stage source keystore|SOURCE_DBID|step 10 (baseline)"
    "20|20_variant_a.sh|Variant A: plain RESTORE with transported source keystore|BACKUP_READY|step 15 (backup)"
    "30|30_variant_b2.sh|Variant B2: AS ENCRYPTED USING KEY without prod MEK|BACKUP_READY|step 15 (backup)"
    "35|35_variant_b1.sh|Variant B1: AS ENCRYPTED USING KEY with prod MEK|BACKUP_READY|step 15 (backup)"
    "40|40_variant_c.sh|Variant C: DUPLICATE ... AS ENCRYPTED|BACKUP_READY|step 15 (backup)"
    "50|50_variant_d.sh|Variant D: RESTORE AS DECRYPTED + SET KEY + OFFLINE ENCRYPT|BACKUP_READY|step 15 (backup)"
    "60|60_variant_f.sh|Variant F: chain-breaking path (new TEK)|BACKUP_READY|step 15 (backup)"
    "61|61_pdb_testbed.sh|PDB testbed: create PDBCLONE with canary tables and c##clone user||none"
    "62|62_pdb_p1_local.sh|PDB P1: local clone in same CDB (reference case)|PDBCLONE_READY|step 61 (PDB testbed)"
    "63|63_pdb_p2_archive.sh|PDB P2: unplug with key export, plug into dev CDB|PDBCLONE_READY|step 61 (PDB testbed)"
    "64|64_pdb_p3_nokeys.sh|PDB P3: unplug without key export - negative test|PDBCLONE_READY|step 61 (PDB testbed)"
    "65|65_pdb_p4_remote.sh|PDB P4: remote clone via DB link as c##clone|PDBCLONE_READY|step 61 (PDB testbed)"
    "66|66_pdb_p5_mekrot.sh|PDB P5: MEK rotation in target after P2 or P4|PDB_TARGET_READY|step 63 P2 or step 65 P4"
    "67|67_pdb_p6_rekey.sh|PDB P6: ONLINE REKEY in target after P2 or P4|PDB_TARGET_READY|step 63 P2 or step 65 P4"
    "68|68_pdb_p7_origin.sh|PDB P7: ORIGIN comparison imported vs copied keystore|PDB_TARGET_READY|step 63 P2 or step 65 P4"
    "69|69_pdb_p8_keyver.sh|PDB P8: KEY_VERSION after plug-in to foreign CDB|PDB_TARGET_READY|step 63 P2 or step 65 P4"
    "70|70_variant_g.sh|Variant G: ALTER TABLESPACE ENCRYPTION ONLINE REKEY|BACKUP_READY|step 15 (backup)"
    "80|80_positive_control.sh|Positive control: two tablespaces prove method sensitivity||none"
    "90|90_withdrawal_test.sh|Key withdrawal test: verify cryptographic independence||none"
)

# Result tracking
declare -A STEP_RESULT
declare -A STEP_DURATION
declare -a STEP_ORDER

# ------------------------------------------------------------------------------
# Function: parse_step
# Purpose.: Extract a field from a registry entry
# Args....: $1 entry, $2 field index (1-5)
# ------------------------------------------------------------------------------
parse_step() {
    local entry="$1" field="$2"
    echo "${entry}" | cut -d'|' -f"${field}"
}

# ------------------------------------------------------------------------------
# Function: step_matches_filter
# Purpose.: Return 0 if a step should run given the current filter options
# Args....: $1 step number (e.g. "00")
#           $2 script name
# Returns.: 0 matches, 1 skip
# ------------------------------------------------------------------------------
step_matches_filter() {
    local nr="$1" script="$2"
    local nr_int="${nr#0}"
    nr_int="${nr_int:-0}"

    # --only overrides everything
    if [[ -n "${OPT_ONLY}" ]]; then
        # Match by number (strip leading zeros) or by script name fragment
        local only_int="${OPT_ONLY#0}"
        only_int="${only_int:-0}"
        if [[ "${nr_int}" == "${only_int}" ]] || [[ "${script}" == *"${OPT_ONLY}"* ]]; then
            return 0
        fi
        return 1
    fi

    # --from and/or --to
    if [[ -n "${OPT_FROM}" ]]; then
        local from_int="${OPT_FROM#0}"
        from_int="${from_int:-0}"
        (( nr_int >= from_int )) || return 1
    fi
    if [[ -n "${OPT_TO}" ]]; then
        local to_int="${OPT_TO#0}"
        to_int="${to_int:-0}"
        (( nr_int <= to_int )) || return 1
    fi
    return 0
}

# ------------------------------------------------------------------------------
# Function: read_state
# Purpose.: Read a key from the state file (minimal version for the runner)
# Args....: $1 key
# Returns.: value on stdout, empty if not found
# ------------------------------------------------------------------------------
read_state() {
    local key="$1"
    if [[ ! -f "${STATE_FILE}" ]]; then printf ''; return 0; fi
    grep "^${key}=" "${STATE_FILE}" 2>/dev/null | tail -1 | cut -d= -f2- || true
}

# ------------------------------------------------------------------------------
# Function: check_gate
# Purpose.: Verify the prerequisite state key is present; abort if not
# Args....: $1 gate_key (may be empty)
#           $2 gate_description
#           $3 step_script for the resume hint
# Returns.: 0 gate OK (or no gate), exits 1 on violation
# ------------------------------------------------------------------------------
check_gate() {
    local gate_key="$1" gate_desc="$2" step_script="$3"
    [[ -z "${gate_key}" ]] && return 0
    local val
    val=$(read_state "${gate_key}")
    if [[ -z "${val}" ]]; then
        echo "GATE VIOLATION: prerequisite '${gate_desc}' not met (${gate_key} is unset)" >&2
        echo "  => Run:  ${TESTS_DIR}/${step_script}" >&2
        return 1
    fi
    return 0
}

# ------------------------------------------------------------------------------
# Function: list_steps
# ------------------------------------------------------------------------------
list_steps() {
    printf '\n%-4s  %-30s  %s\n' "NR" "Script" "Description"
    printf '%-4s  %-30s  %s\n' "----" "------------------------------" "-------------------------------------------"
    for entry in "${STEP_REGISTRY[@]}"; do
        local nr script desc gate_key gate_desc
        nr=$(parse_step "${entry}" 1)
        script=$(parse_step "${entry}" 2)
        desc=$(parse_step "${entry}" 3)
        gate_key=$(parse_step "${entry}" 4)
        gate_desc=$(parse_step "${entry}" 5)
        printf '%-4s  %-30s  %s' "${nr}" "${script}" "${desc}"
        if [[ -n "${gate_key}" ]]; then
            printf '  [gate: %s]' "${gate_desc}"
        fi
        printf '\n'
    done
    printf '\n'
}

# ------------------------------------------------------------------------------
# Function: run_step
# Purpose.: Execute a single test script, log output, record result
# Args....: $1 step entry from STEP_REGISTRY
# Returns.: 0 on step pass, 1 on step fail
# ------------------------------------------------------------------------------
run_step() {
    local entry="$1"
    local nr script desc gate_key gate_desc
    nr=$(parse_step "${entry}" 1)
    script=$(parse_step "${entry}" 2)
    desc=$(parse_step "${entry}" 3)
    gate_key=$(parse_step "${entry}" 4)
    gate_desc=$(parse_step "${entry}" 5)

    local script_path="${TESTS_DIR}/${script}"
    STEP_ORDER+=("${nr}")

    # Check gate (skip if dry-run, gates still checked)
    if ! check_gate "${gate_key}" "${gate_desc}" "${script}"; then
        STEP_RESULT["${nr}"]="GATE"
        echo "$(date '+%Y-%m-%d %H:%M:%S') GATE  [${nr}] ${script}: gate '${gate_desc}' violated" >> "${LOG_FILE}"
        return 1
    fi

    if [[ ! -x "${script_path}" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR [${nr}] ${script}: not executable" >> "${LOG_FILE}"
        STEP_RESULT["${nr}"]="ERROR"
        return 1
    fi

    # Build args
    local args=()
    [[ "${VERBOSE}"   == "TRUE" ]] && args+=("--verbose")
    [[ "${DRY_RUN}"   == "TRUE" ]] && args+=("--dry-run")
    [[ "${FORCE_YES}" == "TRUE" ]] && args+=("--yes")

    # For withdrawal test, pass --after-variant if the last variant is known
    if [[ "${script}" == "90_withdrawal_test.sh" ]]; then
        local last_variant
        last_variant=$(read_state "LAST_VARIANT_LABEL" || true)
        [[ -n "${last_variant}" ]] && args+=("--after-variant" "${last_variant}")
    fi

    echo ""
    echo "========================================================================"
    echo "  STEP ${nr}: ${desc}"
    echo "  Script: ${script_path}"
    echo "  Time:   $(date '+%Y-%m-%d %H:%M:%S')"
    echo "========================================================================"
    echo "$(date '+%Y-%m-%d %H:%M:%S') START [${nr}] ${script}" >> "${LOG_FILE}"

    local t_start t_end elapsed step_exit=0
    t_start=$(date '+%s')

    # Run script, tee to log
    "${script_path}" "${args[@]}" 2>&1 | tee -a "${LOG_FILE}" || step_exit=$?

    t_end=$(date '+%s')
    elapsed=$(( t_end - t_start ))
    STEP_DURATION["${nr}"]="${elapsed}s"

    if [[ "${step_exit}" -eq 0 ]]; then
        STEP_RESULT["${nr}"]="PASS"
        echo "$(date '+%Y-%m-%d %H:%M:%S') END   [${nr}] ${script}: PASS (${elapsed}s)" >> "${LOG_FILE}"
    else
        STEP_RESULT["${nr}"]="FAIL"
        echo "$(date '+%Y-%m-%d %H:%M:%S') END   [${nr}] ${script}: FAIL (exit ${step_exit}, ${elapsed}s)" >> "${LOG_FILE}"
    fi

    return "${step_exit}"
}

# ------------------------------------------------------------------------------
# Function: print_result_table
# ------------------------------------------------------------------------------
print_result_table() {
    echo ""
    echo "========================================================================"
    echo "  TDE Verification Run Results"
    echo "  Log: ${LOG_FILE}"
    echo "========================================================================"
    printf '\n%-4s  %-10s  %-8s  %s\n' "NR" "Result" "Duration" "Description"
    printf '%-4s  %-10s  %-8s  %s\n' "----" "----------" "--------" "-------------------------------------------"
    for entry in "${STEP_REGISTRY[@]}"; do
        local nr script desc
        nr=$(parse_step "${entry}" 1)
        script=$(parse_step "${entry}" 2)
        desc=$(parse_step "${entry}" 3)
        if [[ -n "${STEP_RESULT[${nr}]+isset}" ]]; then
            printf '%-4s  %-10s  %-8s  %s\n' \
                "${nr}" \
                "${STEP_RESULT[${nr}]}" \
                "${STEP_DURATION[${nr}]:-n/a}" \
                "${desc}"
        fi
    done
    printf '\n'
}

# ------------------------------------------------------------------------------
# main
# ------------------------------------------------------------------------------
main() {
    if [[ "${OPT_LIST}" -eq 1 ]]; then
        list_steps
        exit 0
    fi

    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        mkdir -p "${EVIDENCE_ROOT}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') RUN ${SCRIPT_NAME} ${VERSION}" > "${LOG_FILE}"
        echo "  DRY_RUN=${DRY_RUN} FORCE_YES=${FORCE_YES} VERBOSE=${VERBOSE}" >> "${LOG_FILE}"
        echo "  OPT_ONLY=${OPT_ONLY} OPT_FROM=${OPT_FROM} OPT_TO=${OPT_TO}" >> "${LOG_FILE}"
    fi

    echo ""
    echo "TDE Restore Verification Runner ${VERSION}"
    echo "Log: ${LOG_FILE}"
    if [[ "${DRY_RUN}" == "TRUE" ]]; then echo "(DRY-RUN mode)"; fi

    local any_failure=0

    for entry in "${STEP_REGISTRY[@]}"; do
        local nr script
        nr=$(parse_step "${entry}" 1)
        script=$(parse_step "${entry}" 2)

        if ! step_matches_filter "${nr}" "${script}"; then
            lib_dbg "skipping step ${nr} (filtered)"
            continue
        fi

        local step_rc=0
        run_step "${entry}" || step_rc=$?

        # Track last variant for withdrawal test context
        if [[ "${script}" =~ variant ]]; then
            if [[ "${DRY_RUN}" != "TRUE" ]]; then
                local label
                label=$(echo "${script}" | sed -E 's/[0-9]+_//' | sed 's/\.sh//')
                printf '%s=%s\n' "LAST_VARIANT_LABEL" "${label}" >> "${STATE_FILE}"
            fi
        fi

        if [[ "${step_rc}" -ne 0 ]]; then
            any_failure=1
            echo ""
            echo "STEP ${nr} FAILED. Aborting run." >&2
            echo "To resume:  ${SCRIPT_NAME} --from ${nr} --yes" >&2
            echo "Single step: ${TESTS_DIR}/${script} --yes" >&2
            break
        fi
    done

    print_result_table

    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        echo "(dry-run complete - no changes made)"
        return 0
    fi

    if [[ "${any_failure}" -eq 0 ]]; then
        echo "All steps PASSED."
    else
        echo "Run did not complete - see log for details." >&2
        return 1
    fi
}

# Provide log_info / lib_dbg here since lib.sh is not sourced in the runner
log_info() { echo "$(date '+%Y-%m-%d %H:%M:%S') INFO  $*"; }
lib_dbg()  { [[ "${VERBOSE}" == "TRUE" ]] && echo "$(date '+%Y-%m-%d %H:%M:%S') DEBUG $*" || true; }

main "$@"
# --- EOF ----------------------------------------------------------------------
