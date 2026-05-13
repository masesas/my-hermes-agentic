#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_root
load_env
HERMES_USER="${HERMES_USER:-hermes}"

if ! id "${HERMES_USER}" >/dev/null 2>&1; then
  log "Creating ${HERMES_USER} user..."
  useradd --create-home --shell /bin/bash "${HERMES_USER}"
fi

ensure_dir "/home/${HERMES_USER}/workspace" "${HERMES_USER}:${HERMES_USER}" 755

if sudo -iu "${HERMES_USER}" bash -lc 'command -v hermes' >/dev/null 2>&1; then
  log "Hermes already installed for ${HERMES_USER}."
else
  log "Installing Hermes Agent for ${HERMES_USER}..."
  sudo -iu "${HERMES_USER}" bash -lc \
    'curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash'
fi

log "Hermes install step complete."
