#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_root
load_env
require_env PUBLIC_DOMAIN ADMIN_EMAIL

tmp_file="$(mktemp)"
sed \
  -e "s/{{PUBLIC_DOMAIN}}/${PUBLIC_DOMAIN}/g" \
  -e "s/{{ADMIN_EMAIL}}/${ADMIN_EMAIL}/g" \
  "${STARTER_DIR}/config/caddy/Caddyfile" > "${tmp_file}"

# ── Per-profile endpoints (all profiles route through 9Router) ──────
# Each profile's Discord gateway connects directly to 9Router on
# localhost:20128. No additional Caddy reverse_proxy blocks are needed
# because the profiles use the same /v1 endpoint as the orchestrator.
# If per-profile HTTP endpoints are added in the future, append them
# to the Caddyfile template in config/caddy/Caddyfile instead.

caddy validate --config "${tmp_file}"
install -m 644 "${tmp_file}" /etc/caddy/Caddyfile
rm -f "${tmp_file}"

systemctl enable caddy
systemctl reload caddy || systemctl restart caddy

log "Caddy configured for https://${PUBLIC_DOMAIN}."
log "All profiles route through 9Router at 127.0.0.1:20128 — no per-profile Caddy blocks needed."

