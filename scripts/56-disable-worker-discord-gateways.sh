#!/usr/bin/env bash
# Disable always-on Discord gateways for worker profiles.
#
# Why:
# Hermes currently treats Discord thread participation too broadly in some
# versions. If researcher/executor gateways are always running, they may respond
# in #orchestrator threads even when not explicitly mentioned. Production-safe
# default is orchestrator always-on and workers spawn-on-demand via task queue.
#
# This script:
# - Clears worker DISCORD_BOT_TOKEN values in runtime profile .env files.
# - Disables user-level worker gateway units.
# - Overrides worker units to a no-op sleep placeholder so external
#   `hermes --profile <worker> gateway start` calls cannot launch Discord bots.
#
# Re-enable manually by restoring .env token backups and removing the drop-ins:
#   rm ~/.config/systemd/user/hermes-gateway-researcher.service.d/no-discord-worker.conf
#   rm ~/.config/systemd/user/hermes-gateway-executor.service.d/no-discord-worker.conf
#   systemctl --user daemon-reload

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_root
load_env

HERMES_USER="${HERMES_USER:-hermes}"
WORKERS=(researcher executor)
USER_SYSTEMD_DIR="/home/${HERMES_USER}/.config/systemd/user"
RUNTIME_DIR="/run/user/$(id -u "${HERMES_USER}")"
BACKUP_SUFFIX="disable-discord-$(date +%Y%m%d%H%M%S)"

id "${HERMES_USER}" >/dev/null 2>&1 || die "User ${HERMES_USER} does not exist."

for profile in "${WORKERS[@]}"; do
  profile_env="/home/${HERMES_USER}/.hermes/profiles/${profile}/.env"
  unit="hermes-gateway-${profile}.service"
  dropin_dir="${USER_SYSTEMD_DIR}/${unit}.d"
  dropin_file="${dropin_dir}/no-discord-worker.conf"

  [[ -f "${profile_env}" ]] || die "Missing profile env: ${profile_env}"

  cp "${profile_env}" "${profile_env}.bak-${BACKUP_SUFFIX}"
  sed -i 's|^DISCORD_BOT_TOKEN=.*|DISCORD_BOT_TOKEN=|' "${profile_env}"
  chown "${HERMES_USER}:${HERMES_USER}" "${profile_env}" "${profile_env}.bak-${BACKUP_SUFFIX}"
  chmod 600 "${profile_env}" "${profile_env}.bak-${BACKUP_SUFFIX}"
  log "Cleared DISCORD_BOT_TOKEN for ${profile}; backup: ${profile_env}.bak-${BACKUP_SUFFIX}"

  install -d -o "${HERMES_USER}" -g "${HERMES_USER}" -m 755 "${dropin_dir}"
  cat > "${dropin_file}" <<'DROPIN'
[Service]
ExecStart=
ExecStart=/bin/sleep infinity
Restart=no
DROPIN
  chown "${HERMES_USER}:${HERMES_USER}" "${dropin_file}"
  chmod 644 "${dropin_file}"
  log "Installed no-op worker gateway override: ${dropin_file}"
done

sudo -u "${HERMES_USER}" XDG_RUNTIME_DIR="${RUNTIME_DIR}" systemctl --user daemon-reload

for profile in "${WORKERS[@]}"; do
  unit="hermes-gateway-${profile}.service"
  sudo -u "${HERMES_USER}" XDG_RUNTIME_DIR="${RUNTIME_DIR}" systemctl --user disable "${unit}" >/dev/null 2>&1 || true
  sudo -u "${HERMES_USER}" XDG_RUNTIME_DIR="${RUNTIME_DIR}" systemctl --user restart "${unit}"
done

log "Worker Discord gateways disabled. Verify with:"
log "sudo -u ${HERMES_USER} XDG_RUNTIME_DIR=${RUNTIME_DIR} systemctl --user show hermes-gateway-researcher hermes-gateway-executor -p ExecStart -p Restart"
