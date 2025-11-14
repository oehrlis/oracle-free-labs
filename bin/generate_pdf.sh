#!/bin/bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: generate_pdf.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2024.05.02
# Version....: v0.1.0
# Purpose....: Wrapper script for PDF creation with Pandoc via Docker. 
#              It generates a PDF from a Markdown file using XeLaTeX for better font support.
# Notes......: This script requires the oehrlis/pandoc Docker image.
# Reference..: Documentation for Oracle Database Security 19c
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------
# Modified...:
# 2025.05.02 oehrli - initial version
# ------------------------------------------------------------------------------
# - Customization --------------------------------------------------------------
set -e                  # Exit on error
IMAGE="oehrlis/pandoc"  # Docker image for Pandoc
# - End of Customization of configuration files --------------------------------

# - Default Values -------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"  # Directory of this script
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"                # Project root directory

DOC_NAME=${1:-template}                                     # Default name for the document
WORKDIR=$(pwd)                                              # Current working directory
INPUT_MD="doc/${DOC_NAME}.md"               # Input Markdown file
METADATA_YML="doc/${DOC_NAME}.yml"          # Metadata YAML file
OUTPUT_PDF="artefacts/${DOC_NAME}.pdf"      # Output PDF file
# - End of Default Values ------------------------------------------------------

# Check if the input file exists
if [ ! -f "$INPUT_MD" ]; then
  echo "❌ Input file not found: $INPUT_MD"
  exit 1
fi

# temporary change to the project root directory
cd "$PROJECT_ROOT" || exit 1 # Change to the project root directory

# Generate the PDF using Docker
echo "📄 Create PDF from ${INPUT_MD}"
docker run --rm -v "$PROJECT_ROOT":/workdir:z $IMAGE \
  --metadata-file="$METADATA_YML" \
  --listings --pdf-engine=xelatex \
  --resource-path=images --filter pandoc-latex-environment \
  --output="$OUTPUT_PDF" "$INPUT_MD"

# Check if the Docker command was successful
if [ $? -ne 0 ]; then
  echo "❌ Docker command failed."
  exit 1
fi

# Check if the PDF was created successfully
if [ $? -ne 0 ]; then
  echo "❌ PDF generation failed."
  exit 1
fi

# return to the previous directory
cd -                    
echo "✅ PDF created: $OUTPUT_PDF"
# - End of script --------------------------------------------------------------