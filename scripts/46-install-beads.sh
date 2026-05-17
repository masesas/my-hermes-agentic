#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_root
load_env

HERMES_USER="${HERMES_USER:-hermes}"
AGENCY_DIR="/var/lib/morph-agency"
BIN_DIR="/opt/morph-agency/bin"
BEADS_BIN="${BEADS_BIN:-${BIN_DIR}/bd}"
BEADS_PACKAGE="${BEADS_PACKAGE:-github.com/gastownhall/beads/cmd/bd@latest}"

id "${HERMES_USER}" >/dev/null 2>&1 || die "User ${HERMES_USER} does not exist. Run 30-install-hermes.sh first."
resolve_go_bin

ensure_dir "${AGENCY_DIR}" "${HERMES_USER}:${HERMES_USER}" 750
ensure_dir "${BIN_DIR}" "root:${HERMES_USER}" 755
ensure_dir "/home/${HERMES_USER}/workspace" "${HERMES_USER}:${HERMES_USER}" 755

log "Installing Beads (${BEADS_PACKAGE}) to ${BIN_DIR}..."
GOBIN="${BIN_DIR}" CGO_ENABLED="${CGO_ENABLED:-1}" "${GO_BIN}" install "${BEADS_PACKAGE}"

[[ -x "${BEADS_BIN}" ]] || die "Beads binary not found after install: ${BEADS_BIN}"
chown root:"${HERMES_USER}" "${BEADS_BIN}"
chmod 755 "${BEADS_BIN}"

log "Beads version: $(${BEADS_BIN} --version 2>/dev/null || ${BEADS_BIN} version 2>/dev/null || echo unknown)"

log "Beads install complete. Real bd binary: ${BEADS_BIN}"
log "Workspaces are created per project by scripts/51-create-project.sh."
log "Run scripts/47-install-morph-task.sh next to install the /usr/local/bin/bd guard and wrapper env."
