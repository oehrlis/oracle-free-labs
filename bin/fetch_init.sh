#!/bin/bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: fetch_init.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2025.05.02
# Version....: v0.1.1
# Purpose....: Download init_project.sh from a GitHub release (public or private)
# Notes......:
#              - Supports downloading from 'latest' GitHub release
#              - Can authenticate using GH_PAT for private repositories
#              - Uses curl to retrieve and store the script locally
#              - Resulting file is made executable
# License....: Apache License, Version 2.0
# ------------------------------------------------------------------------------
# Modified...:
# 2025.05.02 oehrli - fixed curl header handling and 404 error handling
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# Default values
# ------------------------------------------------------------------------------
GH_USER=""
GH_REPO=""
GH_TAG="latest"
TARGET="./init_project.sh"
GITHUB_PAT=""
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# Usage function
# ------------------------------------------------------------------------------
function Usage() {
  echo ""
  echo "Usage: $(basename "$0") -u <user> -r <repo> [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  -u, --user <user>           GitHub username or org (required)"
  echo "  -r, --repo <repo>           GitHub repository name (required)"
  echo "  -t, --tag <tag>             Release tag to download from (default: latest)"
  echo "  -o, --output <file>         Target output file (default: ./init_project.sh)"
  echo "  -p, --pat <token>           GitHub Personal Access Token (for private repos)"
  echo "  -h, --help                  Show this help message"
  echo ""
  echo "Examples:"
  echo "  $(basename "$0") -u oehrlis -r project-template"
  echo "  $(basename "$0") -u oehrlis -r project-template -p \$GH_PAT"
  echo ""
  exit 0
}
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# Parse command-line arguments
# ------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -u|--user) GH_USER="$2"; shift 2 ;;
    -r|--repo) GH_REPO="$2"; shift 2 ;;
    -t|--tag) GH_TAG="$2"; shift 2 ;;
    -o|--output) TARGET="$2"; shift 2 ;;
    -p|--pat) GITHUB_PAT="$2"; shift 2 ;;
    -h|--help) Usage ;;
    *) echo "❌ Unknown option: $1"; Usage ;;
  esac
done

# Validate required params
if [[ -z "$GH_USER" || -z "$GH_REPO" ]]; then
  echo "❌ GitHub user and repo are required"
  Usage
fi

# ------------------------------------------------------------------------------
# Construct URL and download file
# ------------------------------------------------------------------------------
URL="https://github.com/$GH_USER/$GH_REPO/releases/download/$GH_TAG/init_project.sh"
echo "🌐 Downloading init_project.sh from $URL"

if [[ -n "$GITHUB_PAT" ]]; then
  curl -fsSL -H "Authorization: token $GITHUB_PAT" "$URL" -o "$TARGET"
else
  curl -fsSL "$URL" -o "$TARGET"
fi

if [[ $? -ne 0 ]]; then
  echo "❌ Failed to download init_project.sh (check URL, permissions, or token)"
  exit 1
fi

chmod +x "$TARGET"
echo "✅ Downloaded and saved to $TARGET"
# - EOF ------------------------------------------------------------------------