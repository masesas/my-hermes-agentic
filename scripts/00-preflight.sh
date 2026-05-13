#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_root
load_env
require_env PUBLIC_DOMAIN PUBLIC_BASE_URL ADMIN_EMAIL

if [[ ! -f /etc/os-release ]]; then
  die "Cannot detect OS. This starter targets Ubuntu 22.04."
fi

# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID}" == "ubuntu" ]] || die "Unsupported OS: ${ID}. Use Ubuntu 22.04."
[[ "${VERSION_ID}" == "22.04" ]] || die "Unsupported Ubuntu version: ${VERSION_ID}. Use 22.04."

command -v sudo >/dev/null 2>&1 || die "sudo is required."
command -v systemctl >/dev/null 2>&1 || die "systemd is required."

log "Preflight OK for Ubuntu ${VERSION_ID}."
log "Public domain: ${PUBLIC_DOMAIN}"

