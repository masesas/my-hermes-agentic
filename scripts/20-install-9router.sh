#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_root
load_env
require_env PUBLIC_BASE_URL NINE_ROUTER_INITIAL_PASSWORD NINE_ROUTER_JWT_SECRET NINE_ROUTER_API_KEY_SECRET NINE_ROUTER_MACHINE_ID_SALT

ROUTER_USER="router9"
APP_DIR="/opt/9router/app"
DATA_DIR="/var/lib/9router"
ENV_DIR="/etc/9router"
ENV_TARGET="${ENV_DIR}/9router.env"

if ! id "${ROUTER_USER}" >/dev/null 2>&1; then
  log "Creating ${ROUTER_USER} system user..."
  useradd --system --create-home --home-dir /opt/9router --shell /usr/sbin/nologin "${ROUTER_USER}"
fi

ensure_dir /opt/9router "${ROUTER_USER}:${ROUTER_USER}" 755
ensure_dir "${DATA_DIR}" "${ROUTER_USER}:${ROUTER_USER}" 750
ensure_dir "${ENV_DIR}" root:root 755

if [[ ! -d "${APP_DIR}/.git" ]]; then
  log "Cloning 9Router..."
  sudo -u "${ROUTER_USER}" git clone https://github.com/decolua/9router.git "${APP_DIR}"
else
  log "Updating 9Router repository..."
  sudo -u "${ROUTER_USER}" git -C "${APP_DIR}" pull --ff-only
fi

log "Installing and building 9Router..."
sudo -u "${ROUTER_USER}" npm --prefix "${APP_DIR}" install
sudo -u "${ROUTER_USER}" npm --prefix "${APP_DIR}" run build

cat > "${ENV_TARGET}" <<EOF
NODE_ENV=production
PORT=20128
HOSTNAME=127.0.0.1
DATA_DIR=${DATA_DIR}
NEXT_PUBLIC_BASE_URL=${PUBLIC_BASE_URL}
NEXT_PUBLIC_CLOUD_URL=https://9router.com
INITIAL_PASSWORD=${NINE_ROUTER_INITIAL_PASSWORD}
JWT_SECRET=${NINE_ROUTER_JWT_SECRET}
API_KEY_SECRET=${NINE_ROUTER_API_KEY_SECRET}
MACHINE_ID_SALT=${NINE_ROUTER_MACHINE_ID_SALT}
ENABLE_REQUEST_LOGS=false
EOF

chmod 600 "${ENV_TARGET}"
chown root:"${ROUTER_USER}" "${ENV_TARGET}"

log "9Router installed. It will listen only on 127.0.0.1:20128 behind Caddy."
