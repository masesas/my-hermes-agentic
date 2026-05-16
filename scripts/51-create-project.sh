#!/usr/bin/env bash
# Onboard a new morph-task project. Idempotent.
#
# Usage:
#   sudo ./scripts/51-create-project.sh <project-name> [profile1,profile2,...]
#
# Effects:
#   - Creates /home/${HERMES_USER}/workspace/<project> (bd workspace).
#   - Initializes bd in that workspace if not yet initialized.
#   - Creates /var/lib/morph-agency/handoff/<project>.
#   - Appends a `projects.<name>` entry to /var/lib/morph-agency/config/role-policy.yaml
#     if missing (validated by morph-task projects).
#   - Verifies the project is accepted by morph-task doctor.

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_root
load_env

if [[ $# -lt 1 ]]; then
  die "Usage: $0 <project-name> [profile1,profile2,...]"
fi

PROJECT_NAME="$1"
ALLOWED_PROFILES_CSV="${2:-orchestrator,researcher,executor}"

if [[ ! "${PROJECT_NAME}" =~ ^[a-z0-9][a-z0-9._-]{0,63}$ ]]; then
  die "Invalid project name: ${PROJECT_NAME} (must match ^[a-z0-9][a-z0-9._-]{0,63}$)."
fi

HERMES_USER="${HERMES_USER:-hermes}"
AGENCY_DIR="/var/lib/morph-agency"
CONFIG_DIR="${AGENCY_DIR}/config"
BIN_DIR="/opt/morph-agency/bin"
ROLE_POLICY_TARGET="${CONFIG_DIR}/role-policy.yaml"
BEADS_BIN="${BEADS_BIN:-${BIN_DIR}/bd}"
MORPH_TASK_BIN="${MORPH_TASK_BIN:-${BIN_DIR}/morph-task}"
RUNTIME_DB="${AGENCY_DIR}/queue.db"
PROJECT_WORKSPACE="/home/${HERMES_USER}/workspace/${PROJECT_NAME}"
PROJECT_HANDOFF="${AGENCY_DIR}/handoff/${PROJECT_NAME}"

id "${HERMES_USER}" >/dev/null 2>&1 || die "User ${HERMES_USER} does not exist."
[[ -x "${MORPH_TASK_BIN}" ]] || die "morph-task binary missing at ${MORPH_TASK_BIN}. Run 47-install-morph-task.sh first."
[[ -f "${ROLE_POLICY_TARGET}" ]] || die "Role policy missing at ${ROLE_POLICY_TARGET}. Run 47-install-morph-task.sh first."

ensure_dir "${PROJECT_WORKSPACE}" "${HERMES_USER}:${HERMES_USER}" 755
ensure_dir "${PROJECT_HANDOFF}" "${HERMES_USER}:${HERMES_USER}" 750
log "Ensured workspace ${PROJECT_WORKSPACE} and handoff ${PROJECT_HANDOFF}."

if [[ -x "${BEADS_BIN}" ]]; then
  if [[ ! -d "${PROJECT_WORKSPACE}/.beads" ]]; then
    log "Initializing Beads workspace at ${PROJECT_WORKSPACE}..."
    sudo -u "${HERMES_USER}" env -C "${PROJECT_WORKSPACE}" "${BEADS_BIN}" init >/dev/null 2>&1 \
      || log "Warning: '${BEADS_BIN} init' failed or unsupported; check Beads docs."
  else
    log "Beads workspace already initialized at ${PROJECT_WORKSPACE}."
  fi
else
  log "Warning: Beads binary ${BEADS_BIN} missing; skipping bd init (workspace dir still created)."
fi

# Idempotently append projects.<name> entry if not present.
if grep -E "^[[:space:]]{2}${PROJECT_NAME}:[[:space:]]*$" "${ROLE_POLICY_TARGET}" >/dev/null 2>&1; then
  log "Project '${PROJECT_NAME}' already declared in ${ROLE_POLICY_TARGET}."
else
  if ! grep -E "^projects:[[:space:]]*$" "${ROLE_POLICY_TARGET}" >/dev/null 2>&1; then
    printf '\nprojects:\n' >> "${ROLE_POLICY_TARGET}"
  fi

  IFS=',' read -r -a profiles_arr <<< "${ALLOWED_PROFILES_CSV}"
  {
    printf '  %s:\n' "${PROJECT_NAME}"
    printf '    workspace: %s\n' "${PROJECT_WORKSPACE}"
    printf '    handoff_dir: %s\n' "${PROJECT_HANDOFF}"
    printf '    allowed_profiles:\n'
    for prof in "${profiles_arr[@]}"; do
      printf '      - %s\n' "${prof// /}"
    done
  } >> "${ROLE_POLICY_TARGET}"
  chown "${HERMES_USER}:${HERMES_USER}" "${ROLE_POLICY_TARGET}"
  chmod 640 "${ROLE_POLICY_TARGET}"
  log "Appended project '${PROJECT_NAME}' to ${ROLE_POLICY_TARGET}."
fi

# Verify: morph-task projects show <name> should succeed for orchestrator.
log "Verifying project registration..."
verify_output="$(sudo -u "${HERMES_USER}" env \
  MORPH_PROFILE=orchestrator \
  MORPH_ROLE_POLICY="${ROLE_POLICY_TARGET}" \
  MORPH_RUNTIME_DB="${RUNTIME_DB}" \
  MORPH_BEADS_BIN="${BEADS_BIN}" \
  "${MORPH_TASK_BIN}" --project "${PROJECT_NAME}" projects "${PROJECT_NAME}" 2>&1)" || die "morph-task projects ${PROJECT_NAME} failed: ${verify_output}"

log "Project '${PROJECT_NAME}' registered:"
printf '%s\n' "${verify_output}"

log "Done. Use --project ${PROJECT_NAME} on subsequent morph-task calls."
