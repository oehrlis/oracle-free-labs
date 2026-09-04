#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: 80_positive_control.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrily@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026-09-04
# Version....: 0.1.0
# Purpose....: Positive control: prove that the block comparison method detects
#              a TEK change. Creates two fresh encrypted tablespaces with
#              identical content in odbencprod, compares their block fingerprints.
#              Expected result: the two tablespaces have DIFFERENT ciphertext
#              (different TEKs under the same MEK), confirming the measurement
#              method is sensitive to a TEK change and the null result in
#              variants A, C, D is not a blindness of the tool.
# Notes......: Prerequisite: odbencprod is running and healthy (step 00).
#              Two tablespaces CTRL_ENC_A and CTRL_ENC_B are created with the
#              same DDL and identical canary content under the same MEK.
#              Identical content + identical block addresses + different TEKs
#              must produce different ciphertext. If they are identical here,
#              the measurement method is broken.
#              The tablespaces are set READ ONLY before fingerprinting.
#              From the measured results (2026-09-03): 367 of 501 blocks in the
#              canary range differ between CTRL_ENC_A and CTRL_ENC_B.
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
# --yes accepted for runner compatibility (no destructive operations in this step)
FORCE_YES=${FORCE_YES:-"FALSE"}

# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

LABEL_A="ctrl_enc_a"
LABEL_B="ctrl_enc_b"
CANARY_ROWS_CTRL=5000

# ------------------------------------------------------------------------------
# usage
# ------------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

  Positive control: prove the block comparison method detects a TEK change.
  Creates two encrypted tablespaces CTRL_ENC_A and CTRL_ENC_B in odbencprod
  with identical content. Their ciphertext MUST differ (different TEKs).

  Prerequisite: step 00 (reset lab) - odbencprod must be running and healthy.

Options:
  -h, --help      Show this help and exit
  -v, --verbose   Enable verbose output
  -d, --dry-run   Show what would be done; change nothing

Examples:
  ${SCRIPT_NAME} --dry-run
  ${SCRIPT_NAME}

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
        *) lib_err "Unknown option: $1"; usage; exit 1 ;;
    esac
done

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
main() {
    lib_info "Starting ${SCRIPT_NAME} ${VERSION}"
    step_header "Step 80: Positive control - two fresh encrypted tablespaces"

    require_command docker
    require_command python3
    require_container "${PROD_SERVICE}"
    require_healthy   "${PROD_SERVICE}"

    # Create two fresh encrypted tablespaces with the same DDL
    step_header "Create CTRL_ENC_A (encrypted, AES256)"
    sqlplus_prod "
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SESSION SET CONTAINER=${PROD_PDB};
-- Drop if it already exists from a prior run
DROP TABLESPACE CTRL_ENC_A INCLUDING CONTENTS AND DATAFILES;
EXIT
" || lib_warn "CTRL_ENC_A did not exist (safe to ignore)"

    sqlplus_prod "
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SESSION SET CONTAINER=${PROD_PDB};
CREATE BIGFILE TABLESPACE CTRL_ENC_A
  DATAFILE '/opt/oracle/oradata/FREE/ODBENCPROD/ctrl_enc_a01.dbf'
  SIZE 20M AUTOEXTEND ON MAXSIZE 200M
  ENCRYPTION USING AES256 DEFAULT STORAGE (ENCRYPT);
EXIT
"

    step_header "Create CTRL_ENC_B (encrypted, AES256)"
    sqlplus_prod "
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SESSION SET CONTAINER=${PROD_PDB};
DROP TABLESPACE CTRL_ENC_B INCLUDING CONTENTS AND DATAFILES;
EXIT
" || lib_warn "CTRL_ENC_B did not exist (safe to ignore)"

    sqlplus_prod "
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SESSION SET CONTAINER=${PROD_PDB};
CREATE BIGFILE TABLESPACE CTRL_ENC_B
  DATAFILE '/opt/oracle/oradata/FREE/ODBENCPROD/ctrl_enc_b01.dbf'
  SIZE 20M AUTOEXTEND ON MAXSIZE 200M
  ENCRYPTION USING AES256 DEFAULT STORAGE (ENCRYPT);
EXIT
"

    # Create identical canary content in both tablespaces
    step_header "Create identical canary in CTRL_ENC_A"
    sqlplus_prod "
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SESSION SET CONTAINER=${PROD_PDB};
@/opt/oracle/common/scripts/csenc_canary.sql ${CANARY_OWNER} CTRL_ENC_A ${CANARY_MARKER} ${CANARY_ROWS_CTRL} CANARY_CTRL_A
EXIT
"

    step_header "Create identical canary in CTRL_ENC_B"
    sqlplus_prod "
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SESSION SET CONTAINER=${PROD_PDB};
@/opt/oracle/common/scripts/csenc_canary.sql ${CANARY_OWNER} CTRL_ENC_B ${CANARY_MARKER} ${CANARY_ROWS_CTRL} CANARY_CTRL_B
EXIT
"

    # Freeze both for stable fingerprinting
    step_header "Set CTRL_ENC_A and CTRL_ENC_B to READ ONLY"
    sqlplus_prod "
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SESSION SET CONTAINER=${PROD_PDB};
ALTER TABLESPACE CTRL_ENC_A READ ONLY;
ALTER TABLESPACE CTRL_ENC_B READ ONLY;
SELECT tablespace_name, status, encrypted FROM dba_tablespaces
  WHERE tablespace_name IN ('CTRL_ENC_A','CTRL_ENC_B')
  ORDER BY 1;
SELECT RAWTOHEX(encryptedkey) AS wrapped_tek, name
  FROM v\$encrypted_tablespaces
  WHERE name IN ('CTRL_ENC_A','CTRL_ENC_B')
  ORDER BY name;
EXIT
"

    # Collect fingerprints for both tablespaces
    step_header "Collect evidence set '${LABEL_A}'"
    collect_evidence "${PROD_SERVICE}" "${PROD_PDB}" "${LABEL_A}" "CTRL_ENC_A"

    step_header "Collect evidence set '${LABEL_B}'"
    collect_evidence "${PROD_SERVICE}" "${PROD_PDB}" "${LABEL_B}" "CTRL_ENC_B"

    # Compare - they MUST differ
    step_header "Compare '${LABEL_A}' vs '${LABEL_B}' (expect DIFFERENT ciphertext)"
    compare_evidence "${LABEL_A}" "${LABEL_B}"

    # Count differing canary blocks from the comparison output (use fingerprint tool directly)
    local verdict msg
    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        verdict="PASS"
        msg="DRY-RUN"
    else
        local fp_a fp_b
        fp_a=$(find "${EVIDENCE_ROOT}/${LABEL_A}" -name "*.fp" | head -1)
        fp_b=$(find "${EVIDENCE_ROOT}/${LABEL_B}" -name "*.fp" | head -1)
        if [[ -z "${fp_a}" || -z "${fp_b}" ]]; then
            verdict="FAIL"
            msg="fingerprint files not found in evidence directories"
        else
            local diff_count total_count
            diff_count=$(python3 "${FINGERPRINT_TOOL}" compare "${fp_a}" "${fp_b}" \
                2>/dev/null | grep -c "^diff" || true)
            total_count=$(python3 "${FINGERPRINT_TOOL}" compare "${fp_a}" "${fp_b}" \
                2>/dev/null | grep -cE "^(same|diff)" || true)
            lib_info "block comparison: ${diff_count} differing / ${total_count} total"
            if [[ "${diff_count}" -gt 0 ]]; then
                verdict="PASS"
                msg="method is sensitive: ${diff_count}/${total_count} blocks differ (different TEKs confirmed)"
            else
                verdict="FAIL"
                msg="all blocks identical despite different TEKs - measurement method may be broken"
            fi
        fi
    fi

    print_verdict "${verdict}" "${msg}"
    lib_info "Done."
}

main "$@"
# --- EOF ----------------------------------------------------------------------
