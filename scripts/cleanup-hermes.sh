#!/usr/bin/env bash
# Hermes-only cleanup. Reverses everything that the Hermes-related install
# scripts touch, without disturbing the 9Router stack, Caddy/Nginx, APT
# packages, or UFW.
#
# Scope (in scope):
#   - User-level hermes gateway units (hermes-gateway-${profile}.service)
#   - System-level hermes units (hermes-discord, hermes-${profile}-gateway)
#   - User `hermes` and its entire home directory (userdel -r)
#       └─ includes /home/hermes/.hermes/{profiles/*,SOUL.md,config.yaml,.env},
#                   /home/hermes/workspace/, /home/hermes/.local/bin/hermes
#   - Shared agency data: /var/lib/morph-agency/{queue.db,handoff,skills,config}
#
# Out of scope (intentionally NOT touched):
#   - router9 user, /opt/9router, /etc/9router, /var/lib/9router, 9router.service
#   - Caddy, Caddyfile, Nginx site configs
#   - APT packages, APT repos & keyrings, UFW
#   - Files inside this repository
#
# Usage:
#   sudo ./scripts/cleanup-hermes.sh              # interactive, per-phase confirm
#   sudo ./scripts/cleanup-hermes.sh --dry-run    # preview only
#   sudo ./scripts/cleanup-hermes.sh --yes        # skip prompts (automation)
#   sudo ./scripts/cleanup-hermes.sh --dry-run --yes
#
# Discovers extra profiles automatically: any directory under
# /home/${HERMES_USER}/.hermes/profiles/ counts, in addition to the defaults
# orchestrator/researcher/executor.

set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_root

# ── Constants ───────────────────────────────────────────────────────

HERMES_USER="${HERMES_USER:-hermes}"
HERMES_HOME="/home/${HERMES_USER}"
HERMES_PROFILE_DIR="${HERMES_HOME}/.hermes/profiles"
AGENCY_DIR="/var/lib/morph-agency"

DEFAULT_PROFILES=(orchestrator researcher executor)

# System-level units installed by 50-setup-systemd.sh and 55-setup-systemd-per-profile.sh
SYSTEM_HERMES_UNITS=(
  "hermes-discord.service"
  "hermes-orchestrator-gateway.service"
  "hermes-researcher-gateway.service"
  "hermes-executor-gateway.service"
)

# ── CLI flags ───────────────────────────────────────────────────────

DRY_RUN=0
ASSUME_YES=0

usage() {
  cat <<'EOF'
Usage: sudo ./scripts/cleanup-hermes.sh [options]

Removes all Hermes-related artifacts (user, profiles, services, agency data).
Does NOT touch the 9Router stack, Caddy/Nginx, APT packages, or UFW.

Options:
  --dry-run     Preview without making changes.
  --yes, -y     Skip interactive confirmation prompts.
  -h, --help    Show this help.
EOF
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --yes|-y)  ASSUME_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

# ── Helpers ─────────────────────────────────────────────────────────

load_env_soft() {
  if [[ -f "${ENV_FILE}" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${ENV_FILE}"
    set +a
  fi
}

run() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf '[dry-run] %s\n' "$*"
    return 0
  fi
  "$@"
}

confirm() {
  local prompt="$1"
  if [[ "${ASSUME_YES}" -eq 1 ]]; then
    log "[auto-yes] ${prompt}"
    return 0
  fi
  local answer
  read -r -p "${prompt} [y/N]: " answer
  case "${answer}" in
    y|Y|yes|YES|Yes) return 0 ;;
    *) return 1 ;;
  esac
}

exists_user() { id "$1" >/dev/null 2>&1; }
exists_unit_file() { [[ -f "/etc/systemd/system/$1" ]]; }
uid_of() { id -u "$1" 2>/dev/null || echo ""; }

stop_system_unit() {
  local unit="$1"
  if ! exists_unit_file "${unit}"; then
    log "  - ${unit}: unit file not present, skipping."
    return 0
  fi
  if systemctl is-active --quiet "${unit}"; then
    log "  - ${unit}: stopping..."
    run systemctl stop "${unit}" || log "    [warn] stop failed for ${unit}"
  else
    log "  - ${unit}: not active."
  fi
  if systemctl is-enabled --quiet "${unit}" 2>/dev/null; then
    log "  - ${unit}: disabling..."
    run systemctl disable "${unit}" || log "    [warn] disable failed for ${unit}"
  fi
  run systemctl reset-failed "${unit}" >/dev/null 2>&1 || true
}

remove_system_unit_file() {
  local unit="$1"
  local path="/etc/systemd/system/${unit}"
  if [[ -e "${path}" ]]; then
    log "  - removing ${path}"
    run rm -f "${path}"
  fi
}

remove_path_if_present() {
  local path="$1"
  if [[ -e "${path}" || -L "${path}" ]]; then
    log "  - removing ${path}"
    run rm -rf "${path}"
  else
    log "  - ${path}: not present."
  fi
}

# Discover all profiles under /home/${HERMES_USER}/.hermes/profiles/, merged
# with the defaults. Returns unique profile names on stdout (one per line).
discover_profiles() {
  {
    printf '%s\n' "${DEFAULT_PROFILES[@]}"
    if [[ -d "${HERMES_PROFILE_DIR}" ]]; then
      find "${HERMES_PROFILE_DIR}" -mindepth 1 -maxdepth 1 -type d \
        -exec basename {} \; 2>/dev/null
    fi
  } | sort -u | grep -E '^[a-z][a-z0-9_-]*$' || true
}

cleanup_user_level_services() {
  exists_user "${HERMES_USER}" || { log "User ${HERMES_USER} does not exist; skipping user-level units."; return 0; }

  local uid; uid="$(uid_of "${HERMES_USER}")"
  [[ -n "${uid}" ]] || { log "Could not resolve uid for ${HERMES_USER}; skipping user-level units."; return 0; }

  local xdg="/run/user/${uid}"
  local dbus="unix:path=${xdg}/bus"

  local profiles
  mapfile -t profiles < <(discover_profiles)

  for profile in "${profiles[@]}"; do
    local unit="hermes-gateway-${profile}.service"
    log "  - ${HERMES_USER}@user ${unit}: stop & disable (best-effort)"
    run sudo -u "${HERMES_USER}" \
      XDG_RUNTIME_DIR="${xdg}" \
      DBUS_SESSION_BUS_ADDRESS="${dbus}" \
      systemctl --user stop "${unit}" >/dev/null 2>&1 || true
    run sudo -u "${HERMES_USER}" \
      XDG_RUNTIME_DIR="${xdg}" \
      DBUS_SESSION_BUS_ADDRESS="${dbus}" \
      systemctl --user disable "${unit}" >/dev/null 2>&1 || true
  done

  # Disable linger so the user-bus shuts down cleanly before we userdel.
  if command -v loginctl >/dev/null 2>&1; then
    if loginctl show-user "${HERMES_USER}" --property=Linger 2>/dev/null | grep -q 'Linger=yes'; then
      log "  - disabling linger for ${HERMES_USER}"
      run loginctl disable-linger "${HERMES_USER}" || true
    fi
  fi
}

# ── Phase 0: discover state ─────────────────────────────────────────

load_env_soft

DISCOVERED_PROFILES=()
mapfile -t DISCOVERED_PROFILES < <(discover_profiles)

# Add per-profile system unit candidates discovered from disk (in case of
# extra profiles created via 45-create-agent-profile.sh).
EXTRA_SYSTEM_UNITS=()
for profile in "${DISCOVERED_PROFILES[@]}"; do
  unit="hermes-${profile}-gateway.service"
  case " ${SYSTEM_HERMES_UNITS[*]} " in
    *" ${unit} "*) ;;
    *) EXTRA_SYSTEM_UNITS+=("${unit}") ;;
  esac
done

ALL_SYSTEM_UNITS=("${SYSTEM_HERMES_UNITS[@]}" "${EXTRA_SYSTEM_UNITS[@]}")

# ── Plan summary ────────────────────────────────────────────────────

printf '\n=== Hermes cleanup plan ===\n'
printf 'Mode             : %s\n' "$([[ ${DRY_RUN} -eq 1 ]] && echo 'DRY-RUN (no changes)' || echo 'EXECUTE')"
printf 'Auto-confirm     : %s\n' "$([[ ${ASSUME_YES} -eq 1 ]] && echo 'yes' || echo 'no (interactive)')"
printf 'Hermes user      : %s%s\n' "${HERMES_USER}" "$(exists_user "${HERMES_USER}" && echo '' || echo ' (not present)')"
printf 'Hermes home      : %s\n' "${HERMES_HOME}"
printf 'Profiles found   : %s\n' "${DISCOVERED_PROFILES[*]:-<none>}"
printf 'System units     : %s\n' "${ALL_SYSTEM_UNITS[*]}"
printf 'Agency dir       : %s\n' "${AGENCY_DIR}"
printf 'Out of scope     : router9, /opt/9router, 9router.service, Caddy/Nginx, APT, UFW\n'
printf '===========================\n\n'

if [[ "${ASSUME_YES}" -ne 1 && "${DRY_RUN}" -ne 1 ]]; then
  if ! confirm "Proceed with the Hermes cleanup plan above?"; then
    log "Aborted by user."
    exit 0
  fi
fi

# ── Phase 1: user-level hermes gateway services ─────────────────────

log "[1/6] Stopping user-level hermes gateway services..."
if confirm "Stop & disable user-level hermes-gateway-* for ${HERMES_USER}?"; then
  cleanup_user_level_services
else
  log "  - skipped by user."
fi

# ── Phase 2: system-level hermes units ──────────────────────────────

log "[2/6] Stopping & removing system-level hermes units..."
if confirm "Stop, disable, and remove system unit files (${ALL_SYSTEM_UNITS[*]})?"; then
  for unit in "${ALL_SYSTEM_UNITS[@]}"; do
    stop_system_unit "${unit}"
  done
  for unit in "${ALL_SYSTEM_UNITS[@]}"; do
    remove_system_unit_file "${unit}"
  done
  run systemctl daemon-reload || true
else
  log "  - skipped by user."
fi

# ── Phase 3: shared agency data ─────────────────────────────────────

log "[3/6] Removing shared agency data..."
if confirm "Remove ${AGENCY_DIR} (queue.db, handoff, skills, config)?"; then
  remove_path_if_present "${AGENCY_DIR}"
else
  log "  - skipped by user."
fi

# ── Phase 4: delete hermes user + home ──────────────────────────────

log "[4/6] Deleting user ${HERMES_USER} and home directory..."
if confirm "Delete user '${HERMES_USER}' and recursively remove ${HERMES_HOME}?"; then
  if exists_user "${HERMES_USER}"; then
    # Kill any processes still owned by hermes so userdel does not refuse.
    run pkill -KILL -u "${HERMES_USER}" >/dev/null 2>&1 || true
    sleep 1
    log "  - userdel -r ${HERMES_USER}"
    run userdel -r "${HERMES_USER}" || log "    [warn] userdel failed; verify ${HERMES_HOME} manually."
  else
    log "  - ${HERMES_USER}: not present."
  fi

  if getent group "${HERMES_USER}" >/dev/null 2>&1; then
    log "  - groupdel ${HERMES_USER}"
    run groupdel "${HERMES_USER}" >/dev/null 2>&1 || true
  fi

  # In rare cases userdel -r leaves the home dir behind (e.g. if the user was
  # still logged in on another tty). Sweep it explicitly.
  if [[ -d "${HERMES_HOME}" ]]; then
    log "  - sweeping residual ${HERMES_HOME}"
    run rm -rf "${HERMES_HOME}"
  fi
else
  log "  - skipped by user."
fi

# ── Phase 5: final systemd reload ───────────────────────────────────

log "[5/6] Final systemd reload..."
run systemctl daemon-reload || true
run systemctl reset-failed >/dev/null 2>&1 || true

# ── Phase 6: residue check ──────────────────────────────────────────

log "[6/6] Residue check (informational only)..."
residue_count=0

if exists_user "${HERMES_USER}"; then
  log "  - residue user: ${HERMES_USER}"
  residue_count=$((residue_count + 1))
fi
for path in "${HERMES_HOME}" "${AGENCY_DIR}"; do
  if [[ -e "${path}" ]]; then
    log "  - residue path: ${path}"
    residue_count=$((residue_count + 1))
  fi
done
for unit in "${ALL_SYSTEM_UNITS[@]}"; do
  if exists_unit_file "${unit}"; then
    log "  - residue unit: /etc/systemd/system/${unit}"
    residue_count=$((residue_count + 1))
  fi
done

if [[ "${residue_count}" -eq 0 ]]; then
  log "Hermes cleanup complete. No residue detected."
else
  log "Hermes cleanup finished with ${residue_count} residual item(s) listed above."
  log "Items typically remain because you declined a phase, or they were already missing."
fi

if [[ "${DRY_RUN}" -eq 1 ]]; then
  log "Dry-run mode: no changes were applied."
fi
