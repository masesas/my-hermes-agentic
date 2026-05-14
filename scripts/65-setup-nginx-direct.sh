#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_root
load_env
require_env PUBLIC_DOMAIN

WEB_SERVER="${WEB_SERVER:-caddy}"
if [[ "${WEB_SERVER}" != "nginx-direct" ]]; then
  log "WEB_SERVER=${WEB_SERVER}; skipping Nginx direct setup."
  exit 0
fi

TEMPLATE="${STARTER_DIR}/config/nginx/9router-nginx-direct.conf"
AVAILABLE_TARGET="/etc/nginx/sites-available/${PUBLIC_DOMAIN}.conf"
ENABLED_TARGET="/etc/nginx/sites-enabled/${PUBLIC_DOMAIN}.conf"

[[ -f "${TEMPLATE}" ]] || die "Missing Nginx template: ${TEMPLATE}"
command -v nginx >/dev/null 2>&1 || die "nginx is not installed. Install Nginx or set WEB_SERVER=caddy."

if [[ ! -f "/etc/letsencrypt/live/${PUBLIC_DOMAIN}/fullchain.pem" ]]; then
  log "[WARN] Let's Encrypt cert not found for ${PUBLIC_DOMAIN}."
  log "       If TLS is terminated elsewhere, edit ${AVAILABLE_TARGET} after install."
fi

tmp_file="$(mktemp)"
sed -e "s/{{PUBLIC_DOMAIN}}/${PUBLIC_DOMAIN}/g" "${TEMPLATE}" > "${tmp_file}"
install -m 644 "${tmp_file}" "${AVAILABLE_TARGET}"
rm -f "${tmp_file}"

ln -sfn "${AVAILABLE_TARGET}" "${ENABLED_TARGET}"
nginx -t
systemctl reload nginx || systemctl restart nginx

log "Nginx direct proxy configured for https://${PUBLIC_DOMAIN} -> http://127.0.0.1:20128."
