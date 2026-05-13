#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_root
load_env

HERMES_USER="${HERMES_USER:-hermes}"
PROFILES=(orchestrator researcher executor)
AGENCY_DIR="/var/lib/morph-agency"
FAILURES=0

check_pass() { log "[PASS] $*"; }
check_fail() { log "[FAIL] $*"; FAILURES=$((FAILURES + 1)); }
check_warn() { log "[WARN] $*"; }

# ── Core services ───────────────────────────────────────────────────

log "Checking core services..."
systemctl --no-pager --full status 9router || true
systemctl --no-pager --full status caddy || true
systemctl --no-pager --full status hermes-discord || true

# ── Per-profile existence ───────────────────────────────────────────

log "Checking Hermes profiles..."
for profile in "${PROFILES[@]}"; do
  profile_home="/home/${HERMES_USER}/.hermes/profiles/${profile}"
  if [[ -d "${profile_home}" ]]; then
    check_pass "Profile '${profile}' exists at ${profile_home}"
  else
    check_fail "Profile '${profile}' missing at ${profile_home}"
  fi

  if [[ -f "${profile_home}/.env" ]]; then
    check_pass "Profile '${profile}' .env present"
  else
    check_fail "Profile '${profile}' .env missing"
  fi

  if [[ -f "${profile_home}/SOUL.md" ]]; then
    check_pass "Profile '${profile}' SOUL.md present"
  else
    check_warn "Profile '${profile}' SOUL.md missing (optional but recommended)"
  fi
done

# ── Per-profile systemd services ────────────────────────────────────

log "Checking per-profile systemd services..."
for profile in "${PROFILES[@]}"; do
  service_name="hermes-${profile}-gateway"
  if systemctl list-unit-files "${service_name}.service" >/dev/null 2>&1; then
    status="$(systemctl is-active "${service_name}" 2>/dev/null || true)"
    enabled="$(systemctl is-enabled "${service_name}" 2>/dev/null || true)"
    check_pass "${service_name}: active=${status}, enabled=${enabled}"
  else
    check_warn "${service_name} not installed (run 55-setup-systemd-per-profile.sh)"
  fi
done

# ── SQLite queue accessibility ──────────────────────────────────────

log "Checking SQLite queue..."
QUEUE_DB="${AGENCY_DIR}/queue.db"
if [[ -f "${QUEUE_DB}" ]]; then
  check_pass "queue.db exists at ${QUEUE_DB}"

  if sqlite3 "${QUEUE_DB}" "SELECT count(*) FROM tasks;" >/dev/null 2>&1; then
    task_count="$(sqlite3 "${QUEUE_DB}" "SELECT count(*) FROM tasks;")"
    pending_count="$(sqlite3 "${QUEUE_DB}" "SELECT count(*) FROM tasks WHERE status='pending';")"
    check_pass "queue.db accessible: ${task_count} total tasks, ${pending_count} pending"
  else
    check_fail "queue.db exists but cannot query tasks table"
  fi

  if sqlite3 "${QUEUE_DB}" "SELECT count(*) FROM profile_health;" >/dev/null 2>&1; then
    check_pass "queue.db profile_health table accessible"
  else
    check_fail "queue.db profile_health table inaccessible"
  fi

  for table in task_events task_results agent_messages; do
    if sqlite3 "${QUEUE_DB}" "SELECT count(*) FROM ${table};" >/dev/null 2>&1; then
      check_pass "queue.db ${table} table accessible"
    else
      check_warn "queue.db ${table} table missing (run 44-configure-agent-routing.sh for autonomous mode)"
    fi
  done

  db_owner="$(stat -c '%U:%G' "${QUEUE_DB}" 2>/dev/null || stat -f '%Su:%Sg' "${QUEUE_DB}" 2>/dev/null)"
  if [[ "${db_owner}" == "${HERMES_USER}:${HERMES_USER}" ]]; then
    check_pass "queue.db ownership correct (${db_owner})"
  else
    check_fail "queue.db ownership is ${db_owner}, expected ${HERMES_USER}:${HERMES_USER}"
  fi
else
  check_fail "queue.db not found at ${QUEUE_DB} (run 41-setup-hermes-profiles.sh)"
fi

# ── Shared directories ─────────────────────────────────────────────

log "Checking shared directories..."
for dir in "${AGENCY_DIR}" "${AGENCY_DIR}/handoff" "${AGENCY_DIR}/skills/common" "${AGENCY_DIR}/config"; do
  if [[ -d "${dir}" ]]; then
    check_pass "Directory exists: ${dir}"
  else
    if [[ "${dir}" == "${AGENCY_DIR}/config" ]]; then
      check_warn "Directory missing: ${dir} (run 44-configure-agent-routing.sh for autonomous mode)"
    else
      check_fail "Directory missing: ${dir}"
    fi
  fi
done

if [[ -f "${AGENCY_DIR}/config/autonomous-routing.yaml" ]]; then
  check_pass "Autonomous routing policy installed"
else
  check_warn "Autonomous routing policy missing (run 44-configure-agent-routing.sh)"
fi

for profile in "${PROFILES[@]}"; do
  policy_file="/home/${HERMES_USER}/.hermes/profiles/${profile}/discord-policy.yaml"
  if [[ -f "${policy_file}" ]]; then
    check_pass "Profile '${profile}' Discord policy present"
  else
    check_warn "Profile '${profile}' Discord policy missing (run 44-configure-agent-routing.sh)"
  fi
done

# ── Disk usage warning ──────────────────────────────────────────────

log "Checking disk usage..."
disk_usage_pct="$(df / | awk 'NR==2 {gsub(/%/,""); print $5}')"
if [[ "${disk_usage_pct}" -ge 85 ]]; then
  check_warn "Disk usage is at ${disk_usage_pct}% (threshold: 85%)"
else
  check_pass "Disk usage is at ${disk_usage_pct}%"
fi

# ── 9Router API ─────────────────────────────────────────────────────

log "Checking local 9Router API..."
if [[ -n "${NINE_ROUTER_API_KEY:-}" ]]; then
  curl -fsS http://127.0.0.1:20128/v1/models \
    -H "Authorization: Bearer ${NINE_ROUTER_API_KEY}" | jq '.data[0:5]' \
    || die "9Router /v1/models check failed."
else
  curl -fsS http://127.0.0.1:20128/v1/models | jq '.data[0:5]' \
    || die "9Router /v1/models check failed."
fi

# ── Hermes LLM check ───────────────────────────────────────────────

if [[ -n "${NINE_ROUTER_API_KEY:-}" ]]; then
  log "Checking Hermes one-shot..."
  sudo -iu "${HERMES_USER}" bash -lc 'hermes -z "Reply exactly: OK"'
else
  log "Skipping Hermes LLM check because NINE_ROUTER_API_KEY is empty."
fi

# ── Summary ─────────────────────────────────────────────────────────

if [[ "${FAILURES}" -gt 0 ]]; then
  log "Doctor complete with ${FAILURES} failure(s). Review [FAIL] items above."
else
  log "Doctor complete. All checks passed."
fi
