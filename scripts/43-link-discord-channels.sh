#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_root
load_env

HERMES_USER="${HERMES_USER:-hermes}"
PROFILES=(orchestrator researcher executor)

id "${HERMES_USER}" >/dev/null 2>&1 || die "User ${HERMES_USER} does not exist. Run 30-install-hermes.sh first."

# ── Validate and link per-profile Discord tokens ────────────────────

has_error=0

for profile in "${PROFILES[@]}"; do
  profile_home="/home/${HERMES_USER}/.hermes/profiles/${profile}"
  upper_profile="$(echo "${profile}" | tr '[:lower:]' '[:upper:]')"
  token_var="DISCORD_BOT_TOKEN_${upper_profile}"
  token="${!token_var:-}"

  [[ -d "${profile_home}" ]] || die "Profile dir ${profile_home} missing. Run 41-setup-hermes-profiles.sh first."
  [[ -f "${profile_home}/.env" ]] || die "Profile .env missing at ${profile_home}/.env. Run 42-seed-profile-souls.sh first."

  if [[ -z "${token}" ]]; then
    log "[WARN] ${token_var} is not set. Profile '${profile}' will not have a Discord bot."
    has_error=1
    continue
  fi

  # Update DISCORD_BOT_TOKEN in the profile's .env
  if grep -q '^DISCORD_BOT_TOKEN=' "${profile_home}/.env"; then
    sed -i.bak "s|^DISCORD_BOT_TOKEN=.*|DISCORD_BOT_TOKEN=${token}|" "${profile_home}/.env"
    rm -f "${profile_home}/.env.bak"
  else
    echo "DISCORD_BOT_TOKEN=${token}" >> "${profile_home}/.env"
  fi

  chown "${HERMES_USER}:${HERMES_USER}" "${profile_home}/.env"
  chmod 600 "${profile_home}/.env"

  # Mask the token for logging (show first 8 chars only)
  masked="${token:0:8}..."
  log "Profile '${profile}' -> Discord bot token: ${masked}"
done

if [[ "${has_error}" -eq 1 ]]; then
  log "[WARN] Some profiles are missing Discord bot tokens. Set the corresponding env vars in .env."
  log "       Expected vars: DISCORD_BOT_TOKEN_ORCHESTRATOR, DISCORD_BOT_TOKEN_RESEARCHER, DISCORD_BOT_TOKEN_EXECUTOR"
fi

log "NOTE: Actual Discord channel creation and bot permissions must be configured manually in the Discord Developer Portal."
log "Discord channel linking complete."
