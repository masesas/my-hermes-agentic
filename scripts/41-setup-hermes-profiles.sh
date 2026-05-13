#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_root
load_env

HERMES_USER="${HERMES_USER:-hermes}"
PROFILES=(orchestrator researcher executor)
AGENCY_DIR="/var/lib/morph-agency"

id "${HERMES_USER}" >/dev/null 2>&1 || die "User ${HERMES_USER} does not exist. Run 30-install-hermes.sh first."
command -v hermes >/dev/null 2>&1 || die "hermes binary not found. Run 30-install-hermes.sh first."

# ── Create Hermes profiles ──────────────────────────────────────────

for profile in "${PROFILES[@]}"; do
  profile_home="/home/${HERMES_USER}/.hermes/profiles/${profile}"
  if [[ -d "${profile_home}" ]]; then
    log "Profile '${profile}' already exists at ${profile_home}, skipping."
  else
    log "Creating profile '${profile}'..."
    sudo -u "${HERMES_USER}" hermes profile create "${profile}"
    log "Profile '${profile}' created."
  fi
  ensure_dir "${profile_home}" "${HERMES_USER}:${HERMES_USER}" 700
done

# ── Shared infrastructure directories ───────────────────────────────

ensure_dir "${AGENCY_DIR}"              "${HERMES_USER}:${HERMES_USER}" 750
ensure_dir "${AGENCY_DIR}/handoff"      "${HERMES_USER}:${HERMES_USER}" 750
ensure_dir "${AGENCY_DIR}/skills/common" "${HERMES_USER}:${HERMES_USER}" 750

# ── Initialize SQLite task queue ────────────────────────────────────

QUEUE_DB="${AGENCY_DIR}/queue.db"

if [[ ! -f "${QUEUE_DB}" ]]; then
  log "Initializing SQLite queue at ${QUEUE_DB}..."
  sqlite3 "${QUEUE_DB}" <<'SQL'
CREATE TABLE IF NOT EXISTS tasks (
    id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(8)))),
    type TEXT NOT NULL,
    profile_target TEXT NOT NULL,
    payload TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    priority INTEGER DEFAULT 0,
    result TEXT,
    error TEXT,
    created_at TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    expires_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_queue ON tasks(status, profile_target, priority DESC, created_at);

CREATE TABLE IF NOT EXISTS profile_health (
    profile TEXT PRIMARY KEY,
    consecutive_failures INTEGER DEFAULT 0,
    last_failure_at TEXT,
    status TEXT DEFAULT 'closed',
    updated_at TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

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
  log "SQLite queue initialized."
else
  log "SQLite queue already exists at ${QUEUE_DB}, verifying schema..."
  sqlite3 "${QUEUE_DB}" "SELECT name FROM sqlite_master WHERE type='table' AND name='tasks';" \
    | grep -q tasks || die "queue.db exists but missing 'tasks' table."
  sqlite3 "${QUEUE_DB}" "SELECT name FROM sqlite_master WHERE type='table' AND name='profile_health';" \
    | grep -q profile_health || die "queue.db exists but missing 'profile_health' table."
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
  log "Schema verified."
fi

log "Hermes profiles setup complete. Profiles: ${PROFILES[*]}"
