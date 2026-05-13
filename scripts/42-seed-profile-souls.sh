#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_root
load_env
require_env NINE_ROUTER_API_KEY NINE_ROUTER_BASE_URL HERMES_MODEL

HERMES_USER="${HERMES_USER:-hermes}"
PROFILES=(orchestrator researcher executor)
CONFIG_DIR="${STARTER_DIR}/config/hermes/profiles"

id "${HERMES_USER}" >/dev/null 2>&1 || die "User ${HERMES_USER} does not exist. Run 30-install-hermes.sh first."

for profile in "${PROFILES[@]}"; do
  profile_home="/home/${HERMES_USER}/.hermes/profiles/${profile}"
  profile_config="${CONFIG_DIR}/${profile}"

  [[ -d "${profile_home}" ]] || die "Profile dir ${profile_home} missing. Run 41-setup-hermes-profiles.sh first."

  # ── SOUL.md ───────────────────────────────────────────────────────
  if [[ -f "${profile_config}/SOUL.md" ]]; then
    install -o "${HERMES_USER}" -g "${HERMES_USER}" -m 644 \
      "${profile_config}/SOUL.md" "${profile_home}/SOUL.md"
    log "Installed SOUL.md for ${profile}."
  else
    log "No SOUL.md found at ${profile_config}/SOUL.md, skipping."
  fi

  # ── discord-policy.yaml ─────────────────────────────────────────
  if [[ -f "${profile_config}/discord-policy.yaml" ]]; then
    install -o "${HERMES_USER}" -g "${HERMES_USER}" -m 640 \
      "${profile_config}/discord-policy.yaml" "${profile_home}/discord-policy.yaml"
    log "Installed discord-policy.yaml for ${profile}."
  else
    log "No discord-policy.yaml found at ${profile_config}/discord-policy.yaml, skipping."
  fi

  # ── config.yaml ──────────────────────────────────────────────────
  if [[ -f "${profile_config}/config.yaml" ]]; then
    install -o "${HERMES_USER}" -g "${HERMES_USER}" -m 600 \
      "${profile_config}/config.yaml" "${profile_home}/config.yaml"
    log "Installed config.yaml for ${profile}."
  else
    # Fall back to the shared config.yaml as a base
    log "No config.yaml at ${profile_config}/config.yaml, using shared default."
    tmp_config="$(mktemp)"
    sed -e "s/hermes-orchestrator/hermes-${profile}/g" \
      "${STARTER_DIR}/config/hermes/config.yaml" > "${tmp_config}"
    install -o "${HERMES_USER}" -g "${HERMES_USER}" -m 600 \
      "${tmp_config}" "${profile_home}/config.yaml"
    rm -f "${tmp_config}"
  fi

  # ── .env (from .env.template with value substitution) ────────────
  upper_profile="$(echo "${profile}" | tr '[:lower:]' '[:upper:]')"
  discord_token_var="DISCORD_BOT_TOKEN_${upper_profile}"
  discord_token="${!discord_token_var:-${DISCORD_BOT_TOKEN:-}}"

  if [[ -f "${profile_config}/.env.template" ]]; then
    tmp_env="$(mktemp)"
    sed \
      -e "s|^NINE_ROUTER_API_KEY=.*|NINE_ROUTER_API_KEY=${NINE_ROUTER_API_KEY}|" \
      -e "s|^NINE_ROUTER_BASE_URL=.*|NINE_ROUTER_BASE_URL=${NINE_ROUTER_BASE_URL}|" \
      -e "s|^HERMES_MODEL=.*|HERMES_MODEL=${HERMES_MODEL}|" \
      -e "s|^DISCORD_BOT_TOKEN=.*|DISCORD_BOT_TOKEN=${discord_token}|" \
      -e "s|^DISCORD_ALLOWED_USERS=.*|DISCORD_ALLOWED_USERS=${DISCORD_ALLOWED_USERS:-}|" \
      -e "s|^HERMES_AGENT_NAME=.*|HERMES_AGENT_NAME=hermes-${profile}|" \
      "${profile_config}/.env.template" > "${tmp_env}"
    install -o "${HERMES_USER}" -g "${HERMES_USER}" -m 600 \
      "${tmp_env}" "${profile_home}/.env"
    rm -f "${tmp_env}"
  else
    log "No .env.template at ${profile_config}/.env.template, generating minimal .env."
    cat > "${profile_home}/.env" <<EOF
NINE_ROUTER_API_KEY=${NINE_ROUTER_API_KEY}
NINE_ROUTER_BASE_URL=${NINE_ROUTER_BASE_URL}
HERMES_MODEL=${HERMES_MODEL}
DISCORD_BOT_TOKEN=${discord_token}
HERMES_AGENT_NAME=hermes-${profile}
HERMES_PROFILE=${profile}
MORPH_AGENCY_DIR=/var/lib/morph-agency
MORPH_AUTONOMOUS_MODE=orchestrated
MORPH_ROUTING_POLICY=/var/lib/morph-agency/config/autonomous-routing.yaml
MORPH_DISCORD_POLICY=${profile_home}/discord-policy.yaml
EOF
    chown "${HERMES_USER}:${HERMES_USER}" "${profile_home}/.env"
    chmod 600 "${profile_home}/.env"
  fi
  grep -q '^MORPH_AUTONOMOUS_MODE=' "${profile_home}/.env" \
    || echo 'MORPH_AUTONOMOUS_MODE=orchestrated' >> "${profile_home}/.env"
  grep -q '^MORPH_ROUTING_POLICY=' "${profile_home}/.env" \
    || echo 'MORPH_ROUTING_POLICY=/var/lib/morph-agency/config/autonomous-routing.yaml' >> "${profile_home}/.env"
  grep -q '^MORPH_DISCORD_POLICY=' "${profile_home}/.env" \
    || echo "MORPH_DISCORD_POLICY=${profile_home}/discord-policy.yaml" >> "${profile_home}/.env"
  chown "${HERMES_USER}:${HERMES_USER}" "${profile_home}/.env"
  chmod 600 "${profile_home}/.env"
  log "Installed .env for ${profile}."
done

log "Profile souls seeded for: ${PROFILES[*]}"
