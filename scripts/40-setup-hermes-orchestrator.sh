#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_root
load_env
require_env NINE_ROUTER_API_KEY NINE_ROUTER_BASE_URL HERMES_MODEL

HERMES_USER="${HERMES_USER:-hermes}"
HERMES_HOME="/home/${HERMES_USER}/.hermes"

id "${HERMES_USER}" >/dev/null 2>&1 || die "User ${HERMES_USER} does not exist. Run 30-install-hermes.sh first."

ensure_dir "${HERMES_HOME}" "${HERMES_USER}:${HERMES_USER}" 700
install -o "${HERMES_USER}" -g "${HERMES_USER}" -m 600 "${STARTER_DIR}/config/hermes/config.yaml" "${HERMES_HOME}/config.yaml"
install -o "${HERMES_USER}" -g "${HERMES_USER}" -m 600 "${STARTER_DIR}/config/hermes/SOUL.md" "${HERMES_HOME}/SOUL.md"

cat > "${HERMES_HOME}/.env" <<EOF
NINE_ROUTER_API_KEY=${NINE_ROUTER_API_KEY}
NINE_ROUTER_BASE_URL=${NINE_ROUTER_BASE_URL}
HERMES_MODEL=${HERMES_MODEL}
DISCORD_BOT_TOKEN=${DISCORD_BOT_TOKEN:-}
EOF

chmod 600 "${HERMES_HOME}/.env"
chown "${HERMES_USER}:${HERMES_USER}" "${HERMES_HOME}/.env"

log "Hermes orchestrator config written to ${HERMES_HOME}."

