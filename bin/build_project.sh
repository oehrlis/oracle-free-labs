#!/bin/bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: build_project.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2024.05.02
# Version....: v0.3.1
# Purpose....: Rebuilds a base64-encoded tarball of a template directory and
#              updates the payload in a companion init_project.sh script.
# Notes......: 
#              - Packs a directory (default: parent of script folder)
#              - Updates init_project.sh located in the same folder
#              - Excludes previous .tgz files automatically
#              - Uses sed to avoid newline issues in payload
#              - Can be run from any working directory
# License....: Apache License, Version 2.0
# ------------------------------------------------------------------------------
# Modified...:
# 2025.05.02 oehrli - added Usage function and argument validation
# ------------------------------------------------------------------------------

set -e

# - Resolve Script Location ----------------------------------------------------
SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SCRIPT_SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SCRIPT_SOURCE")" && pwd)"
  SCRIPT_SOURCE="$(readlink "$SCRIPT_SOURCE")"
  [[ "$SCRIPT_SOURCE" != /* ]] && SCRIPT_SOURCE="$DIR/$SCRIPT_SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_SOURCE")" && pwd)"
# ------------------------------------------------------------------------------

# - Default Configuration ------------------------------------------------------
ARCHIVE_NAME="project_structure.tgz"
INIT_SCRIPT="${SCRIPT_DIR}/init_project.sh"
PACK_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE_DIR_NAME="$(basename "$PACK_DIR")"
# ------------------------------------------------------------------------------

# - Usage Function -------------------------------------------------------------
function Usage {
  echo ""
  echo "Usage: $(basename "$0") [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  -d, --directory <dir>     Directory to pack (default: script parent directory)"
  echo "  -n, --name <tgz-name>     Name of output archive (default: project_structure.tgz)"
  echo "  -i, --init-script <path>  Path to init_project.sh to update (default: ./init_project.sh)"
  echo "  -h, --help                Show this help message"
  echo ""
  exit 0
}
# ------------------------------------------------------------------------------

# - Parameter Parsing ----------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case $1 in
    -d|--directory)
      PACK_DIR="$(cd "$2" && pwd)"
      TEMPLATE_DIR_NAME="$(basename "$PACK_DIR")"
      shift 2
      ;;
    -n|--name)
      ARCHIVE_NAME="$2"
      shift 2
      ;;
    -i|--init-script)
      INIT_SCRIPT="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
      shift 2
      ;;
    -h|--help)
      Usage
      ;;
    *)
      echo "❌ Unknown option: $1"
      Usage
      ;;
  esac
done
# ------------------------------------------------------------------------------

# - GitHub Actions compatibility -----------------------------------------------
if [[ -n "$GITHUB_WORKSPACE" ]]; then
  PACK_DIR="$GITHUB_WORKSPACE"
  TEMPLATE_DIR_NAME="$(basename "$PACK_DIR")"
fi
# ------------------------------------------------------------------------------

# - Build Archive --------------------------------------------------------------
echo "📦 Creating archive from: $PACK_DIR (name: $ARCHIVE_NAME)"
echo "📁 TEMPLATE_DIR_NAME: $TEMPLATE_DIR_NAME"
echo "📁 PACK_DIR:          $PACK_DIR"
echo "📁 INIT_SCRIPT:       $INIT_SCRIPT"
echo "📁 Working Directory: $(pwd)"

cd "$PACK_DIR" && tar --warning=no-file-changed --ignore-failed-read -czf "$PACK_DIR/$ARCHIVE_NAME" \
  --exclude="$ARCHIVE_NAME" \
  --exclude="$(basename "$INIT_SCRIPT")" \
  --exclude="*.DS_Store" \
  --exclude="__MACOSX" \
  --exclude=".git" \
  . || {
    echo "❌ tar failed with exit code $?"
    exit 1
}

# - Encode Archive -------------------------------------------------------------
echo "🔐 Encoding archive to Base64"
B64_PAYLOAD=$(base64 "$ARCHIVE_NAME")

# - Update init_project.sh -----------------------------------------------------
echo "🔄 Updating $INIT_SCRIPT"
TMP_SCRIPT="${INIT_SCRIPT}.tmp"

# Keep everything up to and including the marker line
sed '/^__TAR_PAYLOAD__$/q' "$INIT_SCRIPT" > "$TMP_SCRIPT"

echo "$B64_PAYLOAD" >> "$TMP_SCRIPT"

cat "$TMP_SCRIPT" > "$INIT_SCRIPT"
rm -f "$TMP_SCRIPT" "$ARCHIVE_NAME" "$PACK_DIR/$ARCHIVE_NAME"
chmod +x "$INIT_SCRIPT"

echo "✅ $INIT_SCRIPT successfully updated with new payload."
# ------------------------------------------------------------------------------
