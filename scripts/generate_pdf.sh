#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: generate_pdf.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026.04.15
# Version....: v0.2.0
# Purpose....: Wrapper script for PDF creation with Pandoc via Docker.
#              Generates a PDF from a Markdown file using XeLaTeX.
# Notes......: Requires the oehrlis/pandoc Docker image.
#              Usage: scripts/generate_pdf.sh <docname>
#              or via Makefile: make doc DOCNAME=<docname>
# Reference..: https://github.com/oehrlis/oracle-free-labs
# License....: Apache License Version 2.0, January 2004 as shown
#              at http://www.apache.org/licenses/
# ------------------------------------------------------------------------------
# Modified...:
# 2025.05.02 oehrli - initial version
# 2026.04.15 oehrli - hardened to set -euo pipefail; updated header and image var
# ------------------------------------------------------------------------------
set -euo pipefail

# - Customization --------------------------------------------------------------
IMAGE="oehrlis/pandoc"
# - End of Customization -------------------------------------------------------

# - Default Values -------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

DOC_NAME="${1:-template}"
INPUT_MD="doc/${DOC_NAME}.md"
METADATA_YML="doc/${DOC_NAME}.yml"
OUTPUT_PDF="artefacts/${DOC_NAME}.pdf"
# - End of Default Values ------------------------------------------------------

# Check if the input file exists
if [[ ! -f "${INPUT_MD}" ]]; then
    echo "ERROR: Input file not found: ${INPUT_MD}" >&2
    exit 1
fi

cd "${PROJECT_ROOT}"

echo "INFO: Creating PDF from ${INPUT_MD}"
docker run --rm -v "${PROJECT_ROOT}":/workdir:z "${IMAGE}" \
    --metadata-file="${METADATA_YML}" \
    --listings --pdf-engine=xelatex \
    --resource-path=doc/images --filter pandoc-latex-environment \
    --output="${OUTPUT_PDF}" "${INPUT_MD}"

echo "INFO: PDF created: ${OUTPUT_PDF}"
# - End of script --------------------------------------------------------------
