#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_root
load_env

HERMES_USER="${HERMES_USER:-hermes}"
PROFILES=(orchestrator researcher executor)
AGENCY_DIR="/var/lib/morph-agency"
CONFIG_DIR="${AGENCY_DIR}/config"
BIN_DIR="/opt/morph-agency/bin"
MORPH_TASK_SOURCE="${STARTER_DIR}/apps/morph-task"
ROLE_POLICY_SOURCE="${STARTER_DIR}/config/agency/role-policy.yaml"
ROLE_POLICY_TARGET="${CONFIG_DIR}/role-policy.yaml"
RUNTIME_DB="${AGENCY_DIR}/queue.db"
BEADS_BIN="${BEADS_BIN:-${BIN_DIR}/bd}"
BD_GUARD_BIN="${BD_GUARD_BIN:-/usr/local/bin/bd}"
BEADS_WORKSPACE="${BEADS_WORKSPACE:-/home/${HERMES_USER}/workspace/${MORPH_PROJECT:-default}}"

id "${HERMES_USER}" >/dev/null 2>&1 || die "User ${HERMES_USER} does not exist. Run 30-install-hermes.sh first."
command -v go >/dev/null 2>&1 || die "go binary not found. Install Go before building morph-task."
[[ -d "${MORPH_TASK_SOURCE}" ]] || die "Missing morph-task source at ${MORPH_TASK_SOURCE}."
[[ -f "${ROLE_POLICY_SOURCE}" ]] || die "Missing role policy at ${ROLE_POLICY_SOURCE}."

ensure_dir "${AGENCY_DIR}" "${HERMES_USER}:${HERMES_USER}" 750
ensure_dir "${CONFIG_DIR}" "${HERMES_USER}:${HERMES_USER}" 750
ensure_dir "${BIN_DIR}" "root:${HERMES_USER}" 755
ensure_dir "${BEADS_WORKSPACE}" "${HERMES_USER}:${HERMES_USER}" 755

log "Building morph-task CLI..."
(
  cd "${MORPH_TASK_SOURCE}"
  go build -o /tmp/morph-task ./cmd/morph-task
)
install -o root -g "${HERMES_USER}" -m 755 /tmp/morph-task "${BIN_DIR}/morph-task"
rm -f /tmp/morph-task
ln -sf "${BIN_DIR}/morph-task" /usr/local/bin/morph-task
log "Installed morph-task to ${BIN_DIR}/morph-task and linked /usr/local/bin/morph-task."

cat > "${BD_GUARD_BIN}" <<EOF_GUARD
#!/usr/bin/env bash
set -euo pipefail
echo "Direct bd usage is disabled for Morph agents. Use morph-task instead." >&2
echo "Examples:" >&2
echo "  morph-task ready" >&2
echo "  morph-task show <bead-id>" >&2
echo "  morph-task claim --target <profile> <bead-id>" >&2
exit 126
EOF_GUARD
chown root:root "${BD_GUARD_BIN}"
chmod 755 "${BD_GUARD_BIN}"
log "Installed direct bd guard at ${BD_GUARD_BIN}; real Beads binary path remains ${BEADS_BIN}."


install -o "${HERMES_USER}" -g "${HERMES_USER}" -m 640 "${ROLE_POLICY_SOURCE}" "${ROLE_POLICY_TARGET}"
log "Installed role policy to ${ROLE_POLICY_TARGET}."

append_or_replace_env() {
  local file="$1"
  local key="$2"
  local value="$3"

  if grep -q "^${key}=" "${file}"; then
    sed -i.bak "s|^${key}=.*|${key}=${value}|" "${file}"
    rm -f "${file}.bak"
  else
    printf '%s=%s\n' "${key}" "${value}" >> "${file}"
  fi
}

for profile in "${PROFILES[@]}"; do
  profile_home="/home/${HERMES_USER}/.hermes/profiles/${profile}"
  profile_env="${profile_home}/.env"

  [[ -d "${profile_home}" ]] || die "Profile dir ${profile_home} missing. Run 41-setup-hermes-profiles.sh first."
  [[ -f "${profile_env}" ]] || touch "${profile_env}"

  append_or_replace_env "${profile_env}" "MORPH_PROFILE" "${profile}"
  append_or_replace_env "${profile_env}" "MORPH_PROJECT" "${MORPH_PROJECT:-default}"
  append_or_replace_env "${profile_env}" "MORPH_TASK_BIN" "${BIN_DIR}/morph-task"
  append_or_replace_env "${profile_env}" "MORPH_ROLE_POLICY" "${ROLE_POLICY_TARGET}"
  append_or_replace_env "${profile_env}" "MORPH_RUNTIME_DB" "${RUNTIME_DB}"
  append_or_replace_env "${profile_env}" "MORPH_BEADS_BIN" "${BEADS_BIN}"
  append_or_replace_env "${profile_env}" "MORPH_BEADS_WORKSPACE" "${BEADS_WORKSPACE}"
  append_or_replace_env "${profile_env}" "MORPH_DENY_DIRECT_BD" "true"

  chown "${HERMES_USER}:${HERMES_USER}" "${profile_env}"
  chmod 600 "${profile_env}"
  log "Configured morph-task env for ${profile}."
done

if [[ ! -x "${BEADS_BIN}" ]]; then
  log "Warning: Beads binary not found at ${BEADS_BIN}. Install/copy bd there before using morph-task against real Beads."
fi

sudo -u "${HERMES_USER}" env \
  MORPH_PROFILE=orchestrator \
  MORPH_ROLE_POLICY="${ROLE_POLICY_TARGET}" \
  MORPH_RUNTIME_DB="${RUNTIME_DB}" \
  MORPH_BEADS_BIN="${BEADS_BIN}" \
  MORPH_BEADS_WORKSPACE="${BEADS_WORKSPACE}" \
  "${BIN_DIR}/morph-task" --version >/dev/null

log "morph-task install complete. Run 'morph-task doctor' after installing Beads at ${BEADS_BIN}."
