#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_root
load_env
require_env NINE_ROUTER_API_KEY NINE_ROUTER_BASE_URL

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
  # Resolve per-profile HERMES_MODEL early so we can hardcode model.default
  # into config.yaml. Hermes does not consistently expand ${HERMES_MODEL}
  # inside model.default on all gateway versions, so we substitute literally.
  upper_profile_pre="$(echo "${profile}" | tr '[:lower:]' '[:upper:]')"
  hermes_model_var_pre="HERMES_MODEL_${upper_profile_pre}"
  hermes_model_pre="${!hermes_model_var_pre:-${HERMES_MODEL:-morph-${profile}}}"

  if [[ -f "${profile_config}/config.yaml" ]]; then
    tmp_config="$(mktemp)"
    sed -e 's|^  default: ${HERMES_MODEL}.*|  default: '"${hermes_model_pre}"'|' \
      "${profile_config}/config.yaml" > "${tmp_config}"
    install -o "${HERMES_USER}" -g "${HERMES_USER}" -m 600 \
      "${tmp_config}" "${profile_home}/config.yaml"
    rm -f "${tmp_config}"
    log "Installed config.yaml for ${profile} (model.default hardcoded to ${hermes_model_pre})."
  else
    # Fall back to the shared config.yaml as a base
    log "No config.yaml at ${profile_config}/config.yaml, using shared default."
    tmp_config="$(mktemp)"
    sed -e "s/hermes-orchestrator/hermes-${profile}/g" \
        -e 's|^  default: ${HERMES_MODEL}.*|  default: '"${hermes_model_pre}"'|' \
      "${STARTER_DIR}/config/hermes/config.yaml" > "${tmp_config}"
    install -o "${HERMES_USER}" -g "${HERMES_USER}" -m 600 \
      "${tmp_config}" "${profile_home}/config.yaml"
    rm -f "${tmp_config}"
  fi

  # ── .env (from .env.template with value substitution) ────────────
  upper_profile="$(echo "${profile}" | tr '[:lower:]' '[:upper:]')"
  discord_token_var="DISCORD_BOT_TOKEN_${upper_profile}"
  discord_token="${!discord_token_var:-${DISCORD_BOT_TOKEN:-}}"
  discord_owner_var="DISCORD_OWNER_CHANNELS_${upper_profile}"
  discord_owner="${!discord_owner_var:-${DISCORD_OWNER_CHANNELS:-}}"
  hermes_model_var="HERMES_MODEL_${upper_profile}"
  hermes_model="${!hermes_model_var:-${HERMES_MODEL:-morph-${profile}}}"

  if [[ -f "${profile_config}/.env.template" ]]; then
    tmp_env="$(mktemp)"
    sed \
      -e "s|^NINE_ROUTER_API_KEY=.*|NINE_ROUTER_API_KEY=${NINE_ROUTER_API_KEY}|" \
      -e "s|^NINE_ROUTER_BASE_URL=.*|NINE_ROUTER_BASE_URL=${NINE_ROUTER_BASE_URL}|" \
      -e "s|^HERMES_MODEL=.*|HERMES_MODEL=${hermes_model}|" \
      -e "s|^DISCORD_BOT_TOKEN=.*|DISCORD_BOT_TOKEN=${discord_token}|" \
      -e "s|^DISCORD_ALLOWED_USERS=.*|DISCORD_ALLOWED_USERS=${DISCORD_ALLOWED_USERS:-}|" \
      -e "s|^DISCORD_OWNER_CHANNELS=.*|DISCORD_OWNER_CHANNELS=${discord_owner}|" \
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
HERMES_MODEL=${hermes_model}
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
