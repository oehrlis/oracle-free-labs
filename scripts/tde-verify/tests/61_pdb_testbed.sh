#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: 61_pdb_testbed.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026-09-04
# Version....: 0.1.0
# Purpose....: Build the PDB-clone testbed in odbencprod:
#              - Create PDB PDBCLONE with encrypted CLONE_ENC (AES256) and
#                plain CLONE_PLAIN tablespace
#              - Insert 5000 canary rows (OEHRLI-CANARY-2026-09-03) in each
#              - Set both tablespaces READ ONLY for ciphertext stability
#              - Create common user c##clone with CREATE SESSION and
#                CREATE PLUGGABLE DATABASE (CONTAINER=ALL)
#              - Collect evidence set pdb_baseline
#              - Save PDBCLONE_READY, PDBCLONE_TEK_ENC, PDBCLONE_MKID_ENC
# Notes......: Prerequisite: odbencprod is running and healthy.
#              Run standalone after step 00 or anytime odbencprod is up.
#              Idempotent: drops and re-creates PDBCLONE if it already exists.
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
CANARY_MARKER="OEHRLI-CANARY-2026-09-03"
CLONE_SRC_PDB="PDBCLONE"
CLONE_TS_ENC="CLONE_ENC"
CLONE_TS_PLAIN="CLONE_PLAIN"
CLONE_USER="c##clone"

# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

# ------------------------------------------------------------------------------
# usage
# ------------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

  Build the PDB-clone testbed in odbencprod.
  Creates PDB PDBCLONE with encrypted tablespace CLONE_ENC (AES256) and
  plain tablespace CLONE_PLAIN, inserts 5000 canary rows in each, sets both
  READ ONLY, creates common user c##clone, and collects evidence set
  pdb_baseline.

  Idempotent: drops and re-creates PDBCLONE if already present.
  Prerequisite: odbencprod is running and healthy (step 00).

Options:
  -h, --help      Show this help and exit
  -v, --verbose   Enable verbose output
  -d, --dry-run   Show what would be done; change nothing

Environment:
  VERBOSE=TRUE    Equivalent to --verbose
  DRY_RUN=TRUE    Equivalent to --dry-run

Examples:
  ${SCRIPT_NAME} --dry-run
  ${SCRIPT_NAME} --verbose

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
    step_header "Step 61: PDB testbed - create PDBCLONE with canary tables"

    require_command docker
    require_container "${PROD_SERVICE}"
    require_healthy   "${PROD_SERVICE}"

    # Drop PDBCLONE if it already exists (idempotency)
    step_header "Drop PDBCLONE if exists (idempotency)"
    sqlplus_prod "
WHENEVER SQLERROR CONTINUE
ALTER PLUGGABLE DATABASE ${CLONE_SRC_PDB} CLOSE IMMEDIATE;
DROP PLUGGABLE DATABASE ${CLONE_SRC_PDB} INCLUDING DATAFILES;
WHENEVER SQLERROR EXIT SQL.SQLCODE
SELECT 'PDBCLONE drop attempt done' AS status FROM dual;
EXIT
"

    # Create PDBCLONE - password from ORACLE_PWD inside container
    step_header "Create PDB ${CLONE_SRC_PDB}"
    # shellcheck disable=SC1078,SC1079
    lib_run in_prod '
DBPWD=$(printf "%s" "${ORACLE_PWD}")
sqlplus -S / as sysdba <<SQL 2>&1 | grep -viE "identified by"
WHENEVER SQLERROR EXIT SQL.SQLCODE
CREATE PLUGGABLE DATABASE '"${CLONE_SRC_PDB}"' ADMIN USER pdbadmin IDENTIFIED BY "${DBPWD}";
ALTER PLUGGABLE DATABASE '"${CLONE_SRC_PDB}"' OPEN READ WRITE;
ALTER PLUGGABLE DATABASE '"${CLONE_SRC_PDB}"' SAVE STATE;
SELECT name, open_mode FROM v\$pdbs WHERE name='"'"''"${CLONE_SRC_PDB}"''"'"';
EXIT
SQL
'

    # Create encrypted and plain tablespaces inside PDBCLONE
    step_header "Create tablespaces CLONE_ENC and CLONE_PLAIN in ${CLONE_SRC_PDB}"
    sqlplus_prod "
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SESSION SET CONTAINER=${CLONE_SRC_PDB};
WHENEVER SQLERROR CONTINUE
DROP TABLESPACE ${CLONE_TS_ENC} INCLUDING CONTENTS AND DATAFILES;
DROP TABLESPACE ${CLONE_TS_PLAIN} INCLUDING CONTENTS AND DATAFILES;
WHENEVER SQLERROR EXIT SQL.SQLCODE
CREATE TABLESPACE ${CLONE_TS_ENC}
  DATAFILE SIZE 50M AUTOEXTEND ON
  ENCRYPTION USING 'AES256' DEFAULT STORAGE(ENCRYPT);
CREATE TABLESPACE ${CLONE_TS_PLAIN}
  DATAFILE SIZE 50M AUTOEXTEND ON;
SELECT tablespace_name, encrypted FROM dba_tablespaces
  WHERE tablespace_name IN ('${CLONE_TS_ENC}','${CLONE_TS_PLAIN}')
  ORDER BY 1;
EXIT
"

    # Create canary in encrypted tablespace
    step_header "Create canary in ${CLONE_TS_ENC} (encrypted)"
    sqlplus_prod "
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SESSION SET CONTAINER=${CLONE_SRC_PDB};
@/opt/oracle/common/scripts/csenc_canary.sql ${CANARY_OWNER} ${CLONE_TS_ENC} ${CANARY_MARKER} ${CANARY_ROWS} CANARY_CLONEENC
EXIT
"

    # Create canary in plain tablespace
    step_header "Create canary in ${CLONE_TS_PLAIN} (plain control)"
    sqlplus_prod "
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SESSION SET CONTAINER=${CLONE_SRC_PDB};
@/opt/oracle/common/scripts/csenc_canary.sql ${CANARY_OWNER} ${CLONE_TS_PLAIN} ${CANARY_MARKER} ${CANARY_ROWS} CANARY_CLONEPLAIN
EXIT
"

    # Set both tablespaces READ ONLY for ciphertext stability
    step_header "Set ${CLONE_TS_ENC} and ${CLONE_TS_PLAIN} READ ONLY"
    sqlplus_prod "
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SESSION SET CONTAINER=${CLONE_SRC_PDB};
ALTER TABLESPACE ${CLONE_TS_ENC} READ ONLY;
ALTER TABLESPACE ${CLONE_TS_PLAIN} READ ONLY;
SELECT tablespace_name, status FROM dba_tablespaces
  WHERE tablespace_name IN ('${CLONE_TS_ENC}','${CLONE_TS_PLAIN}')
  ORDER BY 1;
EXIT
"

    # Create common user c##clone with necessary privileges
    step_header "Create common user ${CLONE_USER}"
    # shellcheck disable=SC1078,SC1079
    lib_run in_prod '
DBPWD=$(printf "%s" "${ORACLE_PWD}")
sqlplus -S / as sysdba <<SQL 2>&1 | grep -viE "identified by"
WHENEVER SQLERROR CONTINUE
DROP USER '"${CLONE_USER}"' CASCADE;
WHENEVER SQLERROR EXIT SQL.SQLCODE
CREATE USER '"${CLONE_USER}"' IDENTIFIED BY "${DBPWD}" CONTAINER=ALL;
GRANT CREATE SESSION TO '"${CLONE_USER}"' CONTAINER=ALL;
GRANT CREATE PLUGGABLE DATABASE TO '"${CLONE_USER}"' CONTAINER=ALL;
SELECT username, common, account_status FROM dba_users
  WHERE username='"'"'C##CLONE'"'"';
EXIT
SQL
'

    # Collect evidence set pdb_baseline
    step_header "Collect evidence set 'pdb_baseline'"
    collect_evidence "${PROD_SERVICE}" "${CLONE_SRC_PDB}" "pdb_baseline" "${CLONE_TS_ENC}"

    # Read key values for state file
    step_header "Read key values from ${CLONE_SRC_PDB}/${CLONE_TS_ENC}"
    local mkid tek
    mkid=""
    tek=""
    if [[ "${DRY_RUN}" != "TRUE" ]]; then
        mkid=$(get_masterkeyid "${PROD_SERVICE}" "${CLONE_SRC_PDB}" "${CLONE_TS_ENC}")
        tek=$(get_encryptedkey  "${PROD_SERVICE}" "${CLONE_SRC_PDB}" "${CLONE_TS_ENC}")
    else
        mkid="DRY-RUN-MKID"
        tek="DRY-RUN-TEK"
    fi

    write_state "PDBCLONE_READY"    "TRUE"
    write_state "PDBCLONE_TEK_ENC"  "${tek}"
    write_state "PDBCLONE_MKID_ENC" "${mkid}"

    print_key_summary "pdb_baseline (${CLONE_SRC_PDB}/${CLONE_TS_ENC})" \
        "${mkid}" "${tek}" "marker=${CANARY_MARKER}"

    print_verdict "PASS" \
        "PDB testbed ready: ${CLONE_SRC_PDB} with canary tables and ${CLONE_USER}"
    lib_info "Done."
}

main "$@"
# --- EOF ----------------------------------------------------------------------
