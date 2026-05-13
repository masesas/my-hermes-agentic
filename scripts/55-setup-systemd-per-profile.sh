#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_root
load_env

HERMES_USER="${HERMES_USER:-hermes}"
PROFILES=(orchestrator researcher executor)
TEMPLATE="${STARTER_DIR}/systemd/hermes-profile.service.template"

id "${HERMES_USER}" >/dev/null 2>&1 || die "User ${HERMES_USER} does not exist. Run 30-install-hermes.sh first."
[[ -f "${TEMPLATE}" ]] || die "Service template not found at ${TEMPLATE}."

for profile in "${PROFILES[@]}"; do
  service_name="hermes-${profile}-gateway"
  unit_file="/etc/systemd/system/${service_name}.service"

  log "Installing ${service_name}.service..."

  tmp_unit="$(mktemp)"
  sed \
    -e "s/{{HERMES_USER}}/${HERMES_USER}/g" \
    -e "s/{{PROFILE_NAME}}/${profile}/g" \
    "${TEMPLATE}" > "${tmp_unit}"
  install -m 644 "${tmp_unit}" "${unit_file}"
  rm -f "${tmp_unit}"

  log "Installed ${unit_file}."
done

systemctl daemon-reload

# ── Orchestrator: always-on ─────────────────────────────────────────

upper_orch="DISCORD_BOT_TOKEN_ORCHESTRATOR"
if [[ -n "${!upper_orch:-}" ]]; then
  systemctl enable hermes-orchestrator-gateway
  systemctl restart hermes-orchestrator-gateway
  log "hermes-orchestrator-gateway enabled and started."
else
  systemctl disable hermes-orchestrator-gateway >/dev/null 2>&1 || true
  log "hermes-orchestrator-gateway installed but not enabled (DISCORD_BOT_TOKEN_ORCHESTRATOR not set)."
fi

# ── Researcher & Executor: spawn-on-demand, not enabled by default ──

for profile in researcher executor; do
  service_name="hermes-${profile}-gateway"
  systemctl disable "${service_name}" >/dev/null 2>&1 || true
  log "${service_name} installed (spawn-on-demand, not enabled by default)."
done

log "Systemd per-profile setup complete."
