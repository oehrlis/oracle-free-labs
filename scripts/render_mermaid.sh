#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: render_mermaid.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026-09-04
# Version....: 0.1.0
# Purpose....: Extract Mermaid blocks from markdown files and render them to
#              images, so the diagrams in doc/ can be reviewed and reused in a
#              presentation without hand-copying them.
# Notes......: Uses the minlag/mermaid-cli container, so no local node install
#              is needed. Output goes to doc/images/mermaid/<doc>-NN.<fmt> plus
#              an index markdown file listing every diagram with its heading.
#              Re-running overwrites the generated files; nothing else is
#              touched, so this stays safe to run repeatedly.
# Reference..: https://github.com/oehrlis/oracle-free-labs
# License....: Apache License Version 2.0, January 2004 as shown
#              at http://www.apache.org/licenses/
# ------------------------------------------------------------------------------
# CHANGE LOG:
# 2026-09-04  oes  Initial release                                        0.1.0
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# Default Values
# ------------------------------------------------------------------------------
set -euo pipefail
SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSION="0.1.0"
VERBOSE=${VERBOSE:-"FALSE"}
DRY_RUN=${DRY_RUN:-"FALSE"}

MERMAID_IMAGE="minlag/mermaid-cli:latest"
OUT_DIR="${REPO_DIR}/doc/images/mermaid"
FORMAT="png"
THEME="neutral"
SCALE="2"
INPUTS=()
# Global on purpose: the EXIT trap runs outside main and needs to see it.
FRAG_DIR=""
MMDC_CONFIG=""

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
Usage: ${SCRIPT_NAME} [OPTIONS] [markdown-file ...]

  Render every Mermaid block found in the given markdown files to an image.
  With no file given, all doc/tde-*.md files are processed.

Options:
  -f, --format FMT   Output format: png or svg (default: ${FORMAT})
  -t, --theme NAME   Mermaid theme: default, neutral, dark, forest (default: ${THEME})
  -s, --scale N      Scale factor for png (default: ${SCALE})
  -o, --out DIR      Output directory (default: doc/images/mermaid)
  -h, --help         Show this help and exit
  -v, --verbose      Enable verbose output
  -d, --dry-run      List the blocks that would be rendered, render nothing

Examples:
  ${SCRIPT_NAME}
  ${SCRIPT_NAME} --format svg doc/tde-key-architecture.md
  ${SCRIPT_NAME} --dry-run

EOF
}

# ------------------------------------------------------------------------------
# Function: extract_blocks
# Purpose.: Split a markdown file into its Mermaid blocks
# Args....: $1  markdown file
#           $2  target directory for the .mmd fragments
# Returns.: 0 always
# Output..: one line per block: "<index>\t<mmd file>\t<preceding heading>"
# Depends.: python3
# Example.: extract_blocks doc/x.md /tmp/frag
# ------------------------------------------------------------------------------
extract_blocks() {
    local md="$1" dest="$2"
    python3 - "${md}" "${dest}" <<'PY'
import pathlib, re, sys
md = pathlib.Path(sys.argv[1]); dest = pathlib.Path(sys.argv[2])
dest.mkdir(parents=True, exist_ok=True)
stem = md.stem
heading, idx, buf, inblock = "", 0, [], False
for line in md.read_text().splitlines():
    if not inblock and line.startswith("#"):
        heading = line.lstrip("#").strip()
    if line.strip() == "```mermaid":
        inblock, buf = True, []
        continue
    if inblock and line.strip() == "```":
        inblock = False
        idx += 1
        out = dest / f"{stem}-{idx:02d}.mmd"
        out.write_text("\n".join(buf) + "\n")
        print(f"{idx}\t{out}\t{heading}")
        continue
    if inblock:
        buf.append(line)
PY
}

# ------------------------------------------------------------------------------
# Function: render_one
# Purpose.: Render a single .mmd fragment to an image
# Args....: $1  .mmd file, $2 output image path
# Returns.: 0 on success, 1 on render failure
# Output..: mermaid-cli output on failure
# Depends.: docker, minlag/mermaid-cli
# Example.: render_one /tmp/frag/x-01.mmd doc/images/mermaid/x-01.png
# ------------------------------------------------------------------------------
render_one() {
    local mmd="$1" out="$2"
    local mmd_dir out_dir
    mmd_dir="$(cd "$(dirname "${mmd}")" && pwd)"
    out_dir="$(cd "$(dirname "${out}")" && pwd)"

    if [[ "${DRY_RUN}" == "TRUE" ]]; then
        log_info "DRY-RUN: would render ${mmd##*/} -> ${out##*/}"
        return 0
    fi

    # The container runs as a non-root user, so both mounts need to be writable
    # by it. -u keeps the produced files owned by the caller instead of root.
    local cfg_args=()
    if [[ -n "${MMDC_CONFIG}" && -f "${MMDC_CONFIG}" ]]; then
        cfg_args=(-c "/out/$(basename "${MMDC_CONFIG}")")
    fi

    if ! docker run --rm -u "$(id -u):$(id -g)" \
            -v "${mmd_dir}:/in" -v "${out_dir}:/out" \
            "${MERMAID_IMAGE}" \
            -i "/in/${mmd##*/}" -o "/out/${out##*/}" \
            "${cfg_args[@]}" \
            -t "${THEME}" -b white -s "${SCALE}" >/tmp/mmdc.$$.log 2>&1; then
        log_error "render failed for ${mmd##*/}"
        sed 's/^/    /' /tmp/mmdc.$$.log >&2
        rm -f /tmp/mmdc.$$.log
        return 1
    fi
    rm -f /tmp/mmdc.$$.log
    return 0
}

# ------------------------------------------------------------------------------
# Parse arguments
# ------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)    usage; exit 0 ;;
        -v|--verbose) VERBOSE="TRUE"; shift ;;
        -d|--dry-run) DRY_RUN="TRUE"; shift ;;
        -f|--format)  FORMAT="${2:-png}"; shift 2 ;;
        -t|--theme)   THEME="${2:-neutral}"; shift 2 ;;
        -s|--scale)   SCALE="${2:-2}"; shift 2 ;;
        -o|--out)     OUT_DIR="${2:-}"; shift 2 ;;
        -*)           log_error "Unknown option $1"; usage; exit 1 ;;
        *)            INPUTS+=("$1"); shift ;;
    esac
done

# ------------------------------------------------------------------------------
# main
# ------------------------------------------------------------------------------
main() {
    log_info "Starting ${SCRIPT_NAME} ${VERSION}"

    if ! command -v docker >/dev/null 2>&1; then
        log_error "docker not found in PATH"; exit 1
    fi

    if [[ "${#INPUTS[@]}" -eq 0 ]]; then
        while IFS= read -r f; do INPUTS+=("${f}"); done \
            < <(find "${REPO_DIR}/doc" -maxdepth 1 -name 'tde-*.md' | sort)
    fi

    mkdir -p "${OUT_DIR}"

    # htmlLabels=false makes mermaid emit real <text> elements instead of
    # <foreignObject> with HTML inside. foreignObject renders in a browser but
    # stays blank in PowerPoint, Illustrator and most SVG editors, which is
    # exactly where these diagrams are headed.
    MMDC_CONFIG="${OUT_DIR}/.mermaid-config.json"
    cat > "${MMDC_CONFIG}" <<'JSON'
{
  "htmlLabels": false,
  "flowchart": { "htmlLabels": false, "useMaxWidth": false },
  "sequence":  { "useMaxWidth": false },
  "themeVariables": { "fontFamily": "Helvetica, Arial, sans-serif" }
}
JSON
    FRAG_DIR="$(mktemp -d)"
    trap 'rm -rf "${FRAG_DIR:-}"' EXIT

    local index="${OUT_DIR}/README.md"
    local total=0 failed=0
    local -a index_lines=()

    for md in "${INPUTS[@]}"; do
        [[ -f "${md}" ]] || { log_warn "not a file, skipping: ${md}"; continue; }
        local base count=0
        base="$(basename "${md}")"
        while IFS=$'\t' read -r idx mmd heading; do
            [[ -n "${idx}" ]] || continue
            count=$((count + 1)); total=$((total + 1))
            local img img_base
            img_base="$(basename "${mmd%.mmd}")"
            img="${OUT_DIR}/${img_base}.${FORMAT}"
            log_info "rendering ${base} block ${idx}: ${heading}"
            if render_one "${mmd}" "${img}"; then
                index_lines+=("| \`${base}\` | ${idx} | ${heading} | \`$(basename "${img}")\` |")
            else
                failed=$((failed + 1))
                index_lines+=("| \`${base}\` | ${idx} | ${heading} | render failed |")
            fi
        done < <(extract_blocks "${md}" "${FRAG_DIR}")
        [[ "${count}" -eq 0 ]] && log_info "no Mermaid blocks in ${base}"
    done

    if [[ "${DRY_RUN}" != "TRUE" && "${total}" -gt 0 ]]; then
        {
            echo "# Rendered Mermaid diagrams"
            echo ""
            echo "Generated by \`scripts/render_mermaid.sh\`. Do not edit by hand -"
            echo "the source of truth is the Mermaid block in the markdown file listed below."
            echo ""
            echo "| Source document | Block | Heading | Image |"
            echo "|---|---|---|---|"
            printf '%s\n' "${index_lines[@]}"
        } > "${index}"
        log_info "index written to ${index}"
    fi

    log_info "rendered ${total} diagram(s), ${failed} failed"
    [[ "${failed}" -eq 0 ]] || exit 1
    log_info "Done."
}

main "$@"
# --- EOF ----------------------------------------------------------------------
