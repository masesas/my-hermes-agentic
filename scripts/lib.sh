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

