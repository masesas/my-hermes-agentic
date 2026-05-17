#!/usr/bin/env bash
set -euo pipefail

STARTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${STARTER_DIR}/.env"

log() {
  printf '[starter-vps] %s\n' "$*"
}

die() {
  printf '[starter-vps][error] %s\n' "$*" >&2
  exit 1
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "Run this script with sudo or as root."
  fi
}

load_env() {
  [[ -f "${ENV_FILE}" ]] || die "Missing ${ENV_FILE}. Copy .env.example to .env first."
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
}

require_env() {
  local name
  for name in "$@"; do
    [[ -n "${!name:-}" ]] || die "Missing required env: ${name}"
  done
}

ensure_dir() {
  local path="$1"
  local owner="${2:-root:root}"
  local mode="${3:-755}"
  install -d -o "${owner%:*}" -g "${owner#*:}" -m "${mode}" "${path}"
}


resolve_go_bin() {
  # Resolve Go binary from PATH or common install locations.
  # Sets GO_BIN global variable or dies if not found.
  
  if command -v go >/dev/null 2>&1; then
    GO_BIN="$(command -v go)"
    return 0
  fi
  
  local candidates=(
    "/usr/local/go/bin/go"
    "/usr/bin/go"
    "/opt/go/bin/go"
    "/snap/bin/go"
    "${HOME}/go/bin/go"
    "${HOME}/.local/bin/go"
  )
  
  for candidate in "${candidates[@]}"; do
    if [[ -x "${candidate}" ]]; then
      GO_BIN="${candidate}"
      log "Found Go at ${GO_BIN}"
      return 0
    fi
  done
  
  die "Go binary not found. Install Go from https://go.dev/dl/ or via package manager."
}
