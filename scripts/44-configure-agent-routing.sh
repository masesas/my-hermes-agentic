#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_root
load_env

HERMES_USER="${HERMES_USER:-hermes}"
PROFILES=(orchestrator researcher executor)
AGENCY_DIR="/var/lib/morph-agency"
CONFIG_DIR="${AGENCY_DIR}/config"
QUEUE_DB="${AGENCY_DIR}/queue.db"
ROUTING_SOURCE="${STARTER_DIR}/config/agency/autonomous-routing.yaml"
ROUTING_TARGET="${CONFIG_DIR}/autonomous-routing.yaml"
PROFILE_CONFIG_DIR="${STARTER_DIR}/config/hermes/profiles"

id "${HERMES_USER}" >/dev/null 2>&1 || die "User ${HERMES_USER} does not exist. Run 30-install-hermes.sh first."
[[ -f "${QUEUE_DB}" ]] || die "Missing ${QUEUE_DB}. Run 41-setup-hermes-profiles.sh first."
[[ -f "${ROUTING_SOURCE}" ]] || die "Missing routing policy at ${ROUTING_SOURCE}."

ensure_dir "${AGENCY_DIR}" "${HERMES_USER}:${HERMES_USER}" 750
ensure_dir "${CONFIG_DIR}" "${HERMES_USER}:${HERMES_USER}" 750
ensure_dir "${AGENCY_DIR}/handoff" "${HERMES_USER}:${HERMES_USER}" 750

install -o "${HERMES_USER}" -g "${HERMES_USER}" -m 640 \
  "${ROUTING_SOURCE}" "${ROUTING_TARGET}"
log "Installed autonomous routing policy to ${ROUTING_TARGET}."

log "Ensuring autonomous queue tables exist..."
sqlite3 "${QUEUE_DB}" <<'SQL'
CREATE TABLE IF NOT EXISTS task_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    task_id TEXT NOT NULL,
    profile TEXT NOT NULL,
    event_type TEXT NOT NULL,
    message TEXT NOT NULL,
    metadata TEXT,
    created_at TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    FOREIGN KEY(task_id) REFERENCES tasks(id)
);
CREATE INDEX IF NOT EXISTS idx_task_events_task_id ON task_events(task_id, created_at);

CREATE TABLE IF NOT EXISTS task_results (
    task_id TEXT PRIMARY KEY,
    profile TEXT NOT NULL,
    status TEXT NOT NULL CHECK(status IN ('succeeded', 'failed', 'blocked', 'partial')),
    summary TEXT NOT NULL,
    artifact_path TEXT,
    metadata TEXT,
    created_at TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    FOREIGN KEY(task_id) REFERENCES tasks(id)
);

CREATE TABLE IF NOT EXISTS agent_messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    task_id TEXT,
    from_profile TEXT NOT NULL,
    to_profile TEXT NOT NULL,
    channel TEXT NOT NULL,
    intent TEXT NOT NULL,
    depth INTEGER NOT NULL DEFAULT 0,
    discord_message_id TEXT,
    content TEXT NOT NULL,
    processed INTEGER NOT NULL DEFAULT 0,
    created_at TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);
CREATE INDEX IF NOT EXISTS idx_agent_messages_target ON agent_messages(to_profile, processed, created_at);
CREATE INDEX IF NOT EXISTS idx_agent_messages_task ON agent_messages(task_id, created_at);
SQL
chown "${HERMES_USER}:${HERMES_USER}" "${QUEUE_DB}"
chmod 640 "${QUEUE_DB}"
log "Autonomous queue schema ready."

for profile in "${PROFILES[@]}"; do
  profile_home="/home/${HERMES_USER}/.hermes/profiles/${profile}"
  policy_source="${PROFILE_CONFIG_DIR}/${profile}/discord-policy.yaml"

  [[ -d "${profile_home}" ]] || die "Profile dir ${profile_home} missing. Run 41-setup-hermes-profiles.sh first."
  [[ -f "${policy_source}" ]] || die "Missing profile Discord policy at ${policy_source}."

  install -o "${HERMES_USER}" -g "${HERMES_USER}" -m 640 \
    "${policy_source}" "${profile_home}/discord-policy.yaml"

  if [[ -f "${profile_home}/.env" ]]; then
    grep -q '^MORPH_AUTONOMOUS_MODE=' "${profile_home}/.env" \
      || echo 'MORPH_AUTONOMOUS_MODE=orchestrated' >> "${profile_home}/.env"
    grep -q '^MORPH_ROUTING_POLICY=' "${profile_home}/.env" \
      || echo "MORPH_ROUTING_POLICY=${ROUTING_TARGET}" >> "${profile_home}/.env"
    grep -q '^MORPH_DISCORD_POLICY=' "${profile_home}/.env" \
      || echo "MORPH_DISCORD_POLICY=${profile_home}/discord-policy.yaml" >> "${profile_home}/.env"
    chown "${HERMES_USER}:${HERMES_USER}" "${profile_home}/.env"
    chmod 600 "${profile_home}/.env"
  fi

  log "Installed Discord autonomy policy for ${profile}."
done

log "Autonomous agent routing configured. Communication mode: orchestrator + SQLite queue; Discord is progress/UI."
