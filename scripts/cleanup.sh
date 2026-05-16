#!/usr/bin/env bash
# Reverses everything that scripts/00-90-*.sh install on a target VPS.
#
# Scope (in scope):
#   - Project systemd units (system + user level)
#   - Project directories: /opt/9router, /var/lib/9router, /var/lib/morph-agency, /etc/9router
#   - Project web server config: /etc/caddy/Caddyfile, /etc/nginx/sites-*/${PUBLIC_DOMAIN}.conf
#   - Dedicated users: router9, hermes (with home dirs)
#
# Out of scope (intentionally NOT removed):
#   - APT packages (nodejs, caddy, jq, ufw, sqlite3, ripgrep, build-essential, ...)
#   - APT repos & keyrings (NodeSource, Caddy)
#   - UFW rules / state
#   - Files inside this repository (config/hermes/profiles/*, AGENT_REGISTRY.md, ...)
#
# Usage:
#   sudo ./scripts/cleanup.sh              # interactive, asks before each destructive group
#   sudo ./scripts/cleanup.sh --dry-run    # only print what would happen
#   sudo ./scripts/cleanup.sh --yes        # skip all confirmations (automation)
#   sudo ./scripts/cleanup.sh --dry-run --yes  # full audit, no prompts, no writes

set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_root

# ── Constants (mirror the install scripts) ──────────────────────────

HERMES_USER_DEFAULT="hermes"
HERMES_USER="${HERMES_USER:-${HERMES_USER_DEFAULT}}"
ROUTER_USER="router9"
PROFILES=(orchestrator researcher executor)

ROUTER_DIR="/opt/9router"
ROUTER_DATA_DIR="/var/lib/9router"
ROUTER_ENV_DIR="/etc/9router"
AGENCY_DIR="/var/lib/morph-agency"

CADDYFILE="/etc/caddy/Caddyfile"

SYSTEM_UNITS=(
  "9router.service"
  "hermes-discord.service"
  "hermes-orchestrator-gateway.service"
  "hermes-researcher-gateway.service"
  "hermes-executor-gateway.service"
)

# ── CLI flags ───────────────────────────────────────────────────────

DRY_RUN=0
ASSUME_YES=0
PUBLIC_DOMAIN_OVERRIDE=""

usage() {
  cat <<'EOF'
Usage: sudo ./scripts/cleanup.sh [options]

Options:
  --dry-run             Print what would be removed without changing anything.
  --yes, -y             Skip interactive confirmation prompts.
  --domain NAME         Override PUBLIC_DOMAIN (used to locate nginx site files
                        when .env is not available).
  -h, --help            Show this help.
EOF
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    --domain)
      [[ $# -ge 2 ]] || die "--domain requires a value."
      PUBLIC_DOMAIN_OVERRIDE="$2"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

# ── Helpers ─────────────────────────────────────────────────────────

# load_env from lib.sh requires .env. Cleanup must work even without it.
load_env_soft() {
  if [[ -f "${ENV_FILE}" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${ENV_FILE}"
    set +a
    log "Loaded ${ENV_FILE}."
  else
    log "No .env file at ${ENV_FILE} (continuing without it)."
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

# Stop & disable a system-level unit if installed. Idempotent.
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

# Stop & disable user-level hermes gateway units. Best effort.
cleanup_user_level_hermes_services() {
  exists_user "${HERMES_USER}" || { log "User ${HERMES_USER} does not exist; skipping user-level units."; return 0; }

  local uid; uid="$(uid_of "${HERMES_USER}")"
  local xdg="/run/user/${uid}"
  local dbus="unix:path=${xdg}/bus"

  # Try a wildcard stop. Some servers run with linger; some don't. Either way
  # the failure is non-fatal — we're removing the user shortly anyway.
  for profile in "${PROFILES[@]}"; do
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

  # Disable linger so user-bus shuts down cleanly before we userdel.
  if command -v loginctl >/dev/null 2>&1; then
    if loginctl show-user "${HERMES_USER}" --property=Linger 2>/dev/null | grep -q 'Linger=yes'; then
      log "  - disabling linger for ${HERMES_USER}"
      run loginctl disable-linger "${HERMES_USER}" || true
    fi
  fi
}

remove_dir_if_present() {
  local path="$1"
  if [[ -e "${path}" || -L "${path}" ]]; then
    log "  - removing ${path}"
    run rm -rf "${path}"
  else
    log "  - ${path}: not present."
  fi
}

# ── Phase 0: load env (optional) ────────────────────────────────────

load_env_soft

PUBLIC_DOMAIN="${PUBLIC_DOMAIN_OVERRIDE:-${PUBLIC_DOMAIN:-}}"
if [[ -n "${PUBLIC_DOMAIN}" ]]; then
  log "Using PUBLIC_DOMAIN=${PUBLIC_DOMAIN} for nginx site discovery."
else
  log "PUBLIC_DOMAIN not set; will scan /etc/nginx/sites-* for known patterns instead."
fi

# ── Plan summary ────────────────────────────────────────────────────

printf '\n=== Cleanup plan ===\n'
printf 'Mode             : %s\n' "$([[ ${DRY_RUN} -eq 1 ]] && echo 'DRY-RUN (no changes)' || echo 'EXECUTE')"
printf 'Auto-confirm     : %s\n' "$([[ ${ASSUME_YES} -eq 1 ]] && echo 'yes' || echo 'no (interactive)')"
printf 'Hermes user      : %s%s\n' "${HERMES_USER}" "$(exists_user "${HERMES_USER}" && echo '' || echo ' (not present)')"
printf 'Router user      : %s%s\n' "${ROUTER_USER}" "$(exists_user "${ROUTER_USER}" && echo '' || echo ' (not present)')"
printf 'System units     : %s\n' "${SYSTEM_UNITS[*]}"
printf 'Project dirs     : %s\n' "${ROUTER_DIR} ${ROUTER_DATA_DIR} ${ROUTER_ENV_DIR} ${AGENCY_DIR}"
printf 'Caddyfile        : %s\n' "${CADDYFILE}"
printf 'Out of scope     : APT packages, APT repos/keyrings, UFW, repo files\n'
printf '====================\n\n'

if [[ "${ASSUME_YES}" -ne 1 && "${DRY_RUN}" -ne 1 ]]; then
  if ! confirm "Proceed with the cleanup plan above?"; then
    log "Aborted by user."
    exit 0
  fi
fi

# ── Phase 1: Stop user-level hermes services ────────────────────────

log "[1/7] Stopping user-level hermes gateway services..."
if confirm "Stop & disable user-level hermes-gateway-{${PROFILES[*]}} for ${HERMES_USER}?"; then
  cleanup_user_level_hermes_services
else
  log "  - skipped by user."
fi

# ── Phase 2: Stop & remove system-level units ───────────────────────

log "[2/7] Stopping system-level project services..."
if confirm "Stop, disable, and remove system unit files (${SYSTEM_UNITS[*]})?"; then
  for unit in "${SYSTEM_UNITS[@]}"; do
    stop_system_unit "${unit}"
  done
  for unit in "${SYSTEM_UNITS[@]}"; do
    remove_system_unit_file "${unit}"
  done
  run systemctl daemon-reload || true
else
  log "  - skipped by user."
fi

# ── Phase 3: Web server project config ──────────────────────────────

log "[3/7] Removing project web server configuration..."
if confirm "Remove Caddyfile (${CADDYFILE}) and nginx site files belonging to this project?"; then
  # Caddy: the install script overwrites /etc/caddy/Caddyfile with our template
  # generated from config/caddy/Caddyfile. Remove it; user can reconfigure or
  # `apt-get install --reinstall caddy` to restore the package default if needed.
  if [[ -f "${CADDYFILE}" ]]; then
    log "  - removing ${CADDYFILE} (apt-get install --reinstall caddy will restore the default if you still need caddy)"
    run rm -f "${CADDYFILE}"
    if systemctl list-unit-files caddy.service >/dev/null 2>&1; then
      log "  - stopping & disabling caddy.service (binary kept; only project config removed)"
      run systemctl stop caddy >/dev/null 2>&1 || true
      run systemctl disable caddy >/dev/null 2>&1 || true
    fi
  else
    log "  - ${CADDYFILE}: not present."
  fi

  # Nginx: 65-setup-nginx-direct.sh writes /etc/nginx/sites-{available,enabled}/${PUBLIC_DOMAIN}.conf
  if [[ -d /etc/nginx/sites-enabled || -d /etc/nginx/sites-available ]]; then
    if [[ -n "${PUBLIC_DOMAIN}" ]]; then
      remove_dir_if_present "/etc/nginx/sites-enabled/${PUBLIC_DOMAIN}.conf"
      remove_dir_if_present "/etc/nginx/sites-available/${PUBLIC_DOMAIN}.conf"
    else
      # Fallback: any site config that proxies our 9Router upstream
      log "  - scanning nginx sites for 9Router upstream (127.0.0.1:20128)..."
      local_found=0
      for dir in /etc/nginx/sites-enabled /etc/nginx/sites-available; do
        [[ -d "${dir}" ]] || continue
        while IFS= read -r -d '' f; do
          if grep -lq '127.0.0.1:20128' "${f}" 2>/dev/null; then
            log "    matched: ${f}"
            run rm -f "${f}"
            local_found=1
          fi
        done < <(find "${dir}" -maxdepth 1 -type f -o -type l -print0 2>/dev/null)
      done
      [[ "${local_found}" -eq 0 ]] && log "    no matching nginx site files found."
    fi
    if systemctl list-unit-files nginx.service >/dev/null 2>&1; then
      log "  - reloading nginx (best-effort)"
      run nginx -t >/dev/null 2>&1 && run systemctl reload nginx >/dev/null 2>&1 || \
        log "    [warn] nginx -t failed or reload failed; verify nginx config manually."
    fi
  fi
else
  log "  - skipped by user."
fi

# ── Phase 4: Project directories ────────────────────────────────────

log "[4/7] Removing project directories..."
if confirm "Remove ${ROUTER_ENV_DIR}, ${ROUTER_DATA_DIR}, ${AGENCY_DIR}, and ${ROUTER_DIR}?"; then
  remove_dir_if_present "${ROUTER_ENV_DIR}"
  remove_dir_if_present "${ROUTER_DATA_DIR}"
  remove_dir_if_present "${AGENCY_DIR}"
  # /opt/9router is router9's home; it'll also be removed by `userdel -r router9`
  # below. Removing it explicitly first makes the user removal cheaper and safer
  # against userdel choking on weird perms.
  remove_dir_if_present "${ROUTER_DIR}"
else
  log "  - skipped by user."
fi

# ── Phase 5: Delete dedicated users (with home dirs) ────────────────

log "[5/7] Deleting dedicated users..."
if confirm "Delete user '${HERMES_USER}' and remove /home/${HERMES_USER}?"; then
  if exists_user "${HERMES_USER}"; then
    # Kill any lingering processes owned by the user; userdel refuses otherwise
    run pkill -KILL -u "${HERMES_USER}" >/dev/null 2>&1 || true
    sleep 1
    log "  - userdel -r ${HERMES_USER}"
    run userdel -r "${HERMES_USER}" || log "    [warn] userdel failed; verify /home/${HERMES_USER} manually."
  else
    log "  - ${HERMES_USER}: not present."
  fi
  # Group cleanup (some distros leave the primary group behind)
  if getent group "${HERMES_USER}" >/dev/null 2>&1; then
    log "  - groupdel ${HERMES_USER}"
    run groupdel "${HERMES_USER}" >/dev/null 2>&1 || true
  fi
fi

if confirm "Delete system user '${ROUTER_USER}' and remove its home (${ROUTER_DIR})?"; then
  if exists_user "${ROUTER_USER}"; then
    run pkill -KILL -u "${ROUTER_USER}" >/dev/null 2>&1 || true
    sleep 1
    log "  - userdel -r ${ROUTER_USER}"
    run userdel -r "${ROUTER_USER}" || log "    [warn] userdel failed (home may already be gone)."
  else
    log "  - ${ROUTER_USER}: not present."
  fi
  if getent group "${ROUTER_USER}" >/dev/null 2>&1; then
    log "  - groupdel ${ROUTER_USER}"
    run groupdel "${ROUTER_USER}" >/dev/null 2>&1 || true
  fi
fi

# ── Phase 6: systemd reload ─────────────────────────────────────────

log "[6/7] Final systemd reload..."
run systemctl daemon-reload || true
run systemctl reset-failed >/dev/null 2>&1 || true

# ── Phase 7: Residue check ──────────────────────────────────────────

log "[7/7] Residue check (informational only)..."
residue_count=0
for path in \
  "${ROUTER_DIR}" \
  "${ROUTER_DATA_DIR}" \
  "${ROUTER_ENV_DIR}" \
  "${AGENCY_DIR}" \
  "/home/${HERMES_USER}" \
  "${CADDYFILE}"
do
  if [[ -e "${path}" ]]; then
    log "  - residue: ${path}"
    residue_count=$((residue_count + 1))
  fi
done
for unit in "${SYSTEM_UNITS[@]}"; do
  if exists_unit_file "${unit}"; then
    log "  - residue unit: /etc/systemd/system/${unit}"
    residue_count=$((residue_count + 1))
  fi
done
if exists_user "${HERMES_USER}"; then
  log "  - residue user: ${HERMES_USER}"
  residue_count=$((residue_count + 1))
fi
if exists_user "${ROUTER_USER}"; then
  log "  - residue user: ${ROUTER_USER}"
  residue_count=$((residue_count + 1))
fi

if [[ "${residue_count}" -eq 0 ]]; then
  log "Cleanup complete. No residue detected."
else
  log "Cleanup finished with ${residue_count} residual item(s) listed above."
  log "These typically remain because you declined a phase or because items were"
  log "already missing. Re-run with --yes to remove them, or clean manually."
fi

if [[ "${DRY_RUN}" -eq 1 ]]; then
  log "Dry-run mode: no changes were applied."
fi
