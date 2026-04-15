#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: install_oradba_init.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2025.11.18
# Version....: v0.7.0
# Purpose....: Install oradba_init (and optional BasEnv) into a running container
# Notes......: Works with Docker and Podman. Default container: cdbfree
#              Adds post-steps:
#                - remove BE_INITIALSID block from oracle profiles
#                - relocate BasEnv etc to persisted dbconfig and symlink back
#                - link Oracle Net config to /opt/oracle/oradata/dbconfig/FREE
# Reference..: https://github.com/oehrlis/oradba_init
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------
# Modified...:
# 2025.05.15 oehrli - initial version
# 2025.11.18 oehrli - add BasEnv installation
# 2025.11.18 oehrli - add podman support, lean pkg install, profile cleanup,
#                     BasEnv etc relocation, Oracle Net symlinks
# ------------------------------------------------------------------------------

set -euo pipefail

# --- Defaults -----------------------------------------------------------------
SCRIPT_BIN_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
SCRIPT_BASE="$(dirname "${SCRIPT_BIN_DIR}")"
SCRIPT_NAME="$(basename "$0")"

ENGINE=""                    # autodetect unless --engine specified
CONTAINER_NAME="cdbfree"     # default compose service/container name

BASENV_PKG="dbstar-basenv_24.05_basenv-24.05.final.b.zip"

# --- Helpers ------------------------------------------------------------------
# Utility functions for logging, engine abstraction (docker/podman),
# and container state checks.

usage() {
  # print usage/help message
  cat <<EOF
Usage: ${SCRIPT_NAME} [--engine docker|podman] [--basenv-pkg FILE|PATH] [CONTAINER_NAME]

Examples:
  ${SCRIPT_NAME}
  ${SCRIPT_NAME} odbrepo
  ${SCRIPT_NAME} --engine podman odbdemo
  ${SCRIPT_NAME} --basenv-pkg dbstar-basenv_24.05_basenv-24.05.final.b.zip
  ${SCRIPT_NAME} --basenv-pkg /full/path/to/custom-basenv.zip
EOF
}

err()  { # print error message to stderr
  echo "ERROR: $*" >&2
}

info() { # print info message to stdout
  echo "INFO : $*"
}

have_cmd() { # check if a command exists in PATH
  command -v "$1" >/dev/null 2>&1
}

detect_engine() { # detect docker or podman if not specified
  if [[ -n "${ENGINE}" ]]; then
    echo "${ENGINE}"
    return
  fi
  if have_cmd docker; then
    echo docker; return
  fi
  if have_cmd podman; then
    echo podman; return
  fi
  err "Neither docker nor podman found in PATH"
  exit 1
}

engine_exec()    { # wrapper for docker/podman exec
  "${ENGINE}" exec "$@"
}

engine_cp()      { # wrapper for docker/podman cp
  "${ENGINE}" cp "$@"
}

engine_inspect() { # wrapper for docker/podman inspect
  "${ENGINE}" inspect "$@"
}

log_exec()       { # run command and log stdout/stderr to LOG_FILE
  "$@" >>"${LOG_FILE}" 2>&1
}

container_running() { # check if container is running
  if ! engine_inspect "$1" >/dev/null 2>&1; then return 1; fi
  local running
  running="$(${ENGINE} inspect -f '{{.State.Running}}' "$1" 2>/dev/null || echo false)"
  [[ "${running}" == "true" ]]
}

# --- Args ---------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --engine)
      shift
      [[ $# -gt 0 ]] || { err "Missing value after --engine"; usage; exit 2; }
      case "$1" in docker|podman) ENGINE="$1" ;; *) err "Unsupported engine '$1'"; exit 2;; esac
      shift
      ;;
    --basenv-pkg)
      shift
      [[ $# -gt 0 ]] || { err "Missing value after --basenv-pkg"; usage; exit 2; }
      BASENV_PKG="$1"
      shift
      ;;
    -h|--help)
      usage; exit 0
      ;;
    --)
      shift; break
      ;;
    -*)
      err "Unknown option $1"; usage; exit 2
      ;;
    *)
      CONTAINER_NAME="$1"; shift
      ;;
  esac
done

ENGINE="$(detect_engine)"
info "Using engine        : ${ENGINE}"
info "Target container    : ${CONTAINER_NAME}"

# - Logging -------------------------------------------------------------------
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_DIR="data/${CONTAINER_NAME}/logs"
LOG_FILE="${LOG_DIR}/install_oradba_init_${TIMESTAMP}.log"
mkdir -p "${LOG_DIR}"
info "Logging detailed install output to ${LOG_FILE}"

# --- Preflight ----------------------------------------------------------------
if ! container_running "${CONTAINER_NAME}"; then
  err "Container '${CONTAINER_NAME}' not found or not running"
  info "Hint: ${ENGINE} ps --format '{{.Names}}'"
  exit 1
fi

# --- Install oradba_init ------------------------------------------------------
info "Removing existing /opt/oradba (root)..."
log_exec engine_exec -u root -i "${CONTAINER_NAME}" rm -rf /opt/oradba || true

info "Fetching oradba_init setup (oracle)..."
log_exec engine_exec -u oracle -i "${CONTAINER_NAME}" bash -lc \
  "curl -Lf https://raw.githubusercontent.com/oehrlis/oradba_init/master/bin/00_setup_oradba_init.sh -o /tmp/00_setup_oradba_init.sh"

info "Mark setup executable (oracle)..."
log_exec engine_exec -u oracle -i "${CONTAINER_NAME}" chmod 755 /tmp/00_setup_oradba_init.sh || true

info "Run OraDBA setup (root)..."
log_exec engine_exec -u root -i "${CONTAINER_NAME}" /tmp/00_setup_oradba_init.sh || true

info "Cleanup setup tmp..."
log_exec engine_exec -u oracle -i "${CONTAINER_NAME}" rm -f /tmp/00_setup_oradba_init.sh || true

# --- Optional: tools inside container (best-effort, low memory footprint) -----
info "Installing useful tools (file, lsof, which, tree; rlwrap if available) (root)..."
log_exec engine_exec -u root -i "${CONTAINER_NAME}" bash -lc '
  set -euo pipefail

  # base tools we want
  base_tools=(file lsof which tree)
  missing=()
  for t in "${base_tools[@]}"; do
    if ! command -v "$t" >/dev/null 2>&1; then
      missing+=("$t")
    fi
  done

  # optional tool
  need_rlwrap=0
  if ! command -v rlwrap >/dev/null 2>&1; then
    need_rlwrap=1
  fi

  if [ ${#missing[@]} -eq 0 ] && [ $need_rlwrap -eq 0 ]; then
    echo "All requested tools already present: ${base_tools[*]} rlwrap"
    exit 0
  fi

  echo "Missing base tools: ${missing[*]:-none}; rlwrap missing: $need_rlwrap"

  if command -v microdnf >/dev/null 2>&1; then
    if [ ${#missing[@]} -gt 0 ]; then
      echo "Installing with microdnf: ${missing[*]}"
      microdnf --assumeyes --setopt=install_weak_deps=0 install "${missing[@]}" || true
    fi
    if [ $need_rlwrap -eq 1 ]; then
      echo "Attempting rlwrap install via microdnf"
      microdnf --assumeyes --setopt=install_weak_deps=0 install rlwrap || echo "rlwrap not available (skipping)"
    fi
    microdnf clean all || true

  elif command -v dnf >/dev/null 2>&1; then
    echo "" >/etc/dnf/vars/ociregion || true
    if [ ${#missing[@]} -gt 0 ]; then
      echo "Installing with dnf: ${missing[*]}"
      dnf -y --setopt=install_weak_deps=0 --setopt=max_parallel_downloads=1 --best \
          --setopt=tsflags=nodocs install "${missing[@]}" || true
    fi

    if [ $need_rlwrap -eq 1 ]; then
      if dnf repolist 2>/dev/null | grep -qi epel; then
        echo "Installing rlwrap from existing EPEL repo"
        dnf -y --setopt=install_weak_deps=0 --setopt=max_parallel_downloads=1 --best \
            --setopt=tsflags=nodocs install rlwrap || echo "rlwrap install failed (skipping)"
      else
        echo "EPEL not detected; enabling oracle-epel-release-el8 for rlwrap"
        dnf -y --setopt=max_parallel_downloads=1 --setopt=tsflags=nodocs install oracle-epel-release-el8 || true
        dnf -y --setopt=install_weak_deps=0 --setopt=max_parallel_downloads=1 --best \
            --setopt=tsflags=nodocs install rlwrap || echo "rlwrap not installed (skipping)"
      fi
    fi
    dnf -y clean all || true

  else
    echo "No dnf/microdnf found; skipping tool install"
  fi
' || true

# --- BasEnv installation (optional) -------------------------------------------
# Resolve package path:
# - if BASENV_PKG includes a /, treat as explicit path
# - else look for it under ${SCRIPT_BASE}/artefacts/
BASENV_SRC=""
if [[ "${BASENV_PKG}" == */* ]]; then
  [[ -f "${BASENV_PKG}" ]] && BASENV_SRC="${BASENV_PKG}"
else
  [[ -f "${SCRIPT_BASE}/artefacts/${BASENV_PKG}" ]] && BASENV_SRC="${SCRIPT_BASE}/artefacts/${BASENV_PKG}"
fi

if [[ -n "${BASENV_SRC}" ]]; then
  BASENV_BNAME="$(basename "${BASENV_SRC}")"
  CONTAINER_STAGE="/opt/stage"
  CONTAINER_PKG="${CONTAINER_STAGE}/${BASENV_BNAME}"

  info "Installing BasEnv from ${BASENV_SRC} (oracle)..."
  # ensure stage dir exists in the container
  log_exec engine_exec -u root -i "${CONTAINER_NAME}" bash -lc "mkdir -p '${CONTAINER_STAGE}'"

  # always copy as /opt/stage/<filename> (no nested dirs)
  log_exec engine_cp "${BASENV_SRC}" "${CONTAINER_NAME}:${CONTAINER_PKG}"
  
  # run installer with full path to the zip inside the container
  log_exec engine_exec -u oracle -i "${CONTAINER_NAME}" bash -lc "
    export PROCESSOR=\$(uname -m) &&
    export BASENV_PKG='${BASENV_BNAME}' &&
    /opt/oradba/bin/20_setup_basenv.sh || true
    rm -f '${CONTAINER_PKG}' || true
  " || true
else
  info "BasEnv package not found (looked at: ${BASENV_PKG} and ${SCRIPT_BASE}/artefacts/${BASENV_PKG}). Skipping BasEnv."
fi

# --- Cleanup BE_INITIALSID block in oracle profiles ---------------------------
info "Cleaning BE_INITIALSID block in oracle's shell profiles (oracle)..."
log_exec engine_exec -u oracle -i "${CONTAINER_NAME}" bash -lc '
  set -e
  for f in ~/.bash_profile ~/.profile; do
    [ -f "$f" ] || continue
    cp "$f" "$f.bak" 2>/dev/null || true
    # remove from the line starting with the grid check up to and including "typeset BE_OH"
    sed -i "/if \[ \"\`id -un\`\" = \"grid\" \]; then/,/typeset BE_OH/d" "$f" || true
  done
' || true

# --- Relocate BasEnv config to persisted dbconfig and symlink back ------------
info "Relocating BasEnv config to /opt/oracle/oradata/dbconfig/basenv/etc (reusing if present) (oracle)..."
log_exec engine_exec -u root -i "${CONTAINER_NAME}" bash -lc '
  set -e
  ORIG_DIR=/opt/oracle/local/dba/etc
  PERSIST_ROOT=/opt/oracle/oradata/dbconfig
  PERSIST_DIR=${PERSIST_ROOT}/basenv/etc

  if [ -d "$ORIG_DIR" ]; then
    echo "Replacing symlinks in $ORIG_DIR with their target files"
    # find and replace symlinks with the original file contents
    find "$ORIG_DIR" -type l -exec sh -c "
      for link; do
        target=\$(readlink -f \"\$link\")
        if [ -f \"\$target\" ]; then
          echo \"  replacing symlink \$link -> \$target\"
          rm -f \"\$link\"
          cp \"\$target\" \"\$link\"
        fi
      done
    " sh {} +

    mkdir -p "$PERSIST_DIR"
    # copy without overwriting existing files in persisted dir
    if command -v rsync >/dev/null 2>&1; then
      rsync -a --ignore-existing "$ORIG_DIR"/ "$PERSIST_DIR"/
    else
      cp -an "$ORIG_DIR"/. "$PERSIST_DIR"/ 2>/dev/null || cp -a "$ORIG_DIR"/. "$PERSIST_DIR"/
    fi

    rm -rf "$ORIG_DIR"
    ln -s "$PERSIST_DIR" "$ORIG_DIR"
    echo "BasEnv etc moved and symlinked: $ORIG_DIR -> $PERSIST_DIR"
  else
    echo "BasEnv etc not found at $ORIG_DIR (skipping relocation)"
  fi
' || true

# --- Oracle Net config symlinks to persisted dbconfig/FREE --------------------
info "Linking Oracle Net config to /opt/oracle/oradata/dbconfig/FREE if present (oracle)..."
log_exec engine_exec -u oracle -i "${CONTAINER_NAME}" bash -lc '
  set -e
  CFG_DIR=/opt/oracle/oradata/dbconfig/FREE
  # Default 23ai Free home path
  NET_DIR=/opt/oracle/network/admin
  [ -d "$NET_DIR" ] || NET_DIR=/opt/oracle/network/admin

  for f in ldap.ora listener.ora sqlnet.ora tnsnames.ora; do
    if [ -f "$CFG_DIR/$f" ]; then
      echo "Linking $NET_DIR/$f -> $CFG_DIR/$f"
      rm -f "$NET_DIR/$f" 2>/dev/null || true
      ln -s "$CFG_DIR/$f" "$NET_DIR/$f"
    else
      echo "No $f in $CFG_DIR, skipping"
    fi
  done
' || true

info "Done. oradba_init installed and post-configuration applied to ${CONTAINER_NAME}"
# - EOF ------------------------------------------------------------------------
