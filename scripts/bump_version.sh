#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: bump_version.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026.04.15
# Version....: 0.2.0
# Purpose....: Update semantic version in VERSION and create a changelog stub
# Usage......: ./scripts/bump_version.sh [major|minor|patch]
# Notes......: Assumes a VERSION file containing only the version number (e.g. 1.2.3).
#              CHANGELOG.md must follow Keep a Changelog format (header = 6 lines).
# Reference..: https://github.com/oehrlis/oracle-free-labs
# License....: Apache License Version 2.0, January 2004 as shown
#              at http://www.apache.org/licenses/
# ------------------------------------------------------------------------------
set -o errexit
set -o nounset
set -o pipefail

SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly REPO_ROOT
readonly VERSION_FILE="${REPO_ROOT}/VERSION"
readonly CHANGELOG_FILE="${REPO_ROOT}/CHANGELOG.md"

usage() {
    cat <<USAGE
Usage: ${SCRIPT_NAME} [major|minor|patch]

Examples:
    ${SCRIPT_NAME} patch
    ${SCRIPT_NAME} minor
    ${SCRIPT_NAME} major
USAGE
}

validate_prerequisites() {
    [[ -f "${VERSION_FILE}" ]] || { echo "ERROR: VERSION file not found." >&2; exit 1; }
    [[ -f "${CHANGELOG_FILE}" ]] || { echo "ERROR: CHANGELOG.md not found." >&2; exit 1; }
}

read_version() {
    cat "${VERSION_FILE}"
}

bump_semver() {
    local version="$1"
    local type="$2"
    local major minor patch

    IFS='.' read -r major minor patch <<< "${version}"

    case "${type}" in
        major)
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        minor)
            minor=$((minor + 1))
            patch=0
            ;;
        patch)
            patch=$((patch + 1))
            ;;
        *)
            echo "ERROR: Invalid bump type '${type}'." >&2
            usage
            exit 1
            ;;
    esac

    echo "${major}.${minor}.${patch}"
}

update_version_file() {
    local new_version="$1"
    printf '%s\n' "${new_version}" > "${VERSION_FILE}"
}

prepend_changelog_stub() {
    local new_version="$1"
    local today
    local tmp_file

    today="$(date +%F)"
    tmp_file="$(mktemp)"

    {
        echo "# Changelog"
        echo
        echo "All notable changes to this project are documented here."
        echo
        echo "Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/);"
        echo "versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html)."
        echo
        echo "## [${new_version}] - ${today}"
        echo
        echo "### Added"
        echo
        echo "- "
        echo
        tail -n +8 "${CHANGELOG_FILE}"
    } > "${tmp_file}"

    mv "${tmp_file}" "${CHANGELOG_FILE}"
}

main() {
    local bump_type="${1:-}"
    local current_version new_version

    [[ -n "${bump_type}" ]] || { usage; exit 1; }

    validate_prerequisites
    current_version="$(read_version)"
    new_version="$(bump_semver "${current_version}" "${bump_type}")"

    update_version_file "${new_version}"
    prepend_changelog_stub "${new_version}"

    echo "Updated version: ${current_version} -> ${new_version}"
}

main "$@"
# - End of script --------------------------------------------------------------
