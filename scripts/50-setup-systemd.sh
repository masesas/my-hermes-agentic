#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_root
load_env

install -m 644 "${STARTER_DIR}/systemd/9router.service" /etc/systemd/system/9router.service

tmp_hermes_unit="$(mktemp)"
sed \
  -e "s/{{HERMES_USER}}/${HERMES_USER:-hermes}/g" \
  "${STARTER_DIR}/systemd/hermes-discord.service" > "${tmp_hermes_unit}"
install -m 644 "${tmp_hermes_unit}" /etc/systemd/system/hermes-discord.service
rm -f "${tmp_hermes_unit}"

systemctl daemon-reload
systemctl enable 9router
systemctl restart 9router

if [[ -n "${DISCORD_BOT_TOKEN:-}" ]] && id "${HERMES_USER:-hermes}" >/dev/null 2>&1; then
  systemctl enable hermes-discord
  systemctl restart hermes-discord
  log "Hermes Discord gateway enabled."
else
  systemctl disable hermes-discord >/dev/null 2>&1 || true
  log "Hermes Discord service installed but not enabled yet. Set DISCORD_BOT_TOKEN and run Hermes setup first."
fi

log "systemd setup complete."
