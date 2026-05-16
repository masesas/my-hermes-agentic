#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_root
load_env

HERMES_USER="${HERMES_USER:-hermes}"
PROFILES_CSV="${PROFILES:-orchestrator,researcher,executor}"
AGENCY_DIR="/var/lib/morph-agency"
QUEUE_DB="${AGENCY_DIR}/queue.db"
BACKUP_DIR="${BACKUP_DIR:-/var/backups}"
RESET_QUEUE="${RESET_QUEUE:-true}"
RESET_HANDOFF="${RESET_HANDOFF:-true}"
RESET_POLICY_AUDIT="${RESET_POLICY_AUDIT:-false}"

id "${HERMES_USER}" >/dev/null 2>&1 || die "User ${HERMES_USER} does not exist."
[[ -d "/home/${HERMES_USER}/.hermes/profiles" ]] || die "Hermes profiles dir missing."

IFS=',' read -r -a PROFILES_ARRAY <<< "${PROFILES_CSV}"
backup_file="${BACKUP_DIR}/morph-agent-memory-reset-$(date +%Y%m%d-%H%M%S).tgz"

log "Creating backup at ${backup_file}..."
tar czf "${backup_file}" \
  "/home/${HERMES_USER}/.hermes/profiles" \
  "${AGENCY_DIR}" 2>/dev/null || die "Backup failed; aborting reset."
chmod 600 "${backup_file}"

for profile in "${PROFILES_ARRAY[@]}"; do
  profile="$(echo "${profile}" | xargs)"
  [[ -n "${profile}" ]] || continue
  profile_home="/home/${HERMES_USER}/.hermes/profiles/${profile}"
  [[ -d "${profile_home}" ]] || die "Profile dir missing: ${profile_home}"

  log "Resetting learned state for ${profile}..."
  rm -f "${profile_home}/MEMORY.md" "${profile_home}/USER.md"
  rm -rf \
    "${profile_home}/sessions" \
    "${profile_home}/checkpoints" \
    "${profile_home}/cache" \
    "${profile_home}/logs" \
    "${profile_home}/transcripts"
  chown -R "${HERMES_USER}:${HERMES_USER}" "${profile_home}"
done

if [[ "${RESET_QUEUE}" == "true" && -f "${QUEUE_DB}" ]]; then
  log "Clearing runtime task queue tables in ${QUEUE_DB}..."
  sqlite3 "${QUEUE_DB}" <<SQL
DELETE FROM tasks;
DELETE FROM task_events;
DELETE FROM task_results;
DELETE FROM agent_messages;
DELETE FROM profile_health;
DELETE FROM runtime_assignments;
DELETE FROM runtime_locks;
$(if [[ "${RESET_POLICY_AUDIT}" == "true" ]]; then echo "DELETE FROM policy_violations;"; fi)
VACUUM;
SQL
  chown "${HERMES_USER}:${HERMES_USER}" "${QUEUE_DB}"
  chmod 640 "${QUEUE_DB}"
fi

if [[ "${RESET_HANDOFF}" == "true" && -d "${AGENCY_DIR}/handoff" ]]; then
  log "Clearing handoff directory..."
  find "${AGENCY_DIR}/handoff" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  chown "${HERMES_USER}:${HERMES_USER}" "${AGENCY_DIR}/handoff"
  chmod 750 "${AGENCY_DIR}/handoff"
fi

log "Reinstalling profile SOUL/config and routing policies..."
"${STARTER_DIR}/scripts/42-seed-profile-souls.sh"
"${STARTER_DIR}/scripts/44-configure-agent-routing.sh"
"${STARTER_DIR}/scripts/47-install-morph-task.sh"

log "Agent learned-state reset complete. Backup: ${backup_file}"
log "Restart Hermes profile gateways before resuming Discord operations."
