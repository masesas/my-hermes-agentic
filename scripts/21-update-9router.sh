#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_root
load_env

ROUTER_USER="router9"
APP_DIR="/opt/9router/app"
NPM_RUN="/opt/9router/bin/npm-run"
INSTALL_SCRIPT="${STARTER_DIR}/scripts/20-install-9router.sh"

is_9router_installed() {
  id "${ROUTER_USER}" >/dev/null 2>&1 \
    && [[ -d "${APP_DIR}/.git" ]] \
    && [[ -x "${NPM_RUN}" ]]
}

restart_9router_if_managed() {
  if systemctl list-unit-files 9router.service >/dev/null 2>&1; then
    log "Restarting 9Router service..."
    systemctl daemon-reload
    systemctl restart 9router
    systemctl --no-pager --lines=20 status 9router
  else
    log "9router.service is not installed yet. Run scripts/50-setup-systemd.sh to enable it."
  fi
}

[[ -x "${INSTALL_SCRIPT}" ]] || die "Missing executable install script: ${INSTALL_SCRIPT}"

if is_9router_installed; then
  log "9Router installation detected. Updating via 20-install-9router.sh..."
else
  log "9Router is not installed. Installing via 20-install-9router.sh..."
fi

"${INSTALL_SCRIPT}"
restart_9router_if_managed

log "9Router update/install flow complete."
