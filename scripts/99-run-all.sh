#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() {
  cat <<'EOF'
Usage: sudo ./scripts/99-run-all.sh [options]

Run all numbered setup scripts in ./scripts in ascending order.

Options:
  --dry-run              Print scripts that would run, without executing them.
  --continue-on-error    Continue to the next script after a failure.
  --skip NAME            Skip a script by filename. Can be repeated.
  --only NAME            Run only a script by filename. Can be repeated.
  -h, --help             Show this help.

Examples:
  sudo ./scripts/99-run-all.sh --dry-run
  sudo ./scripts/99-run-all.sh --skip 90-doctor.sh
  sudo ./scripts/99-run-all.sh --only 00-preflight.sh --only 90-doctor.sh
EOF
}

contains() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    [[ "${item}" == "${needle}" ]] && return 0
  done
  return 1
}

require_root

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF_NAME="$(basename "${BASH_SOURCE[0]}")"
DRY_RUN=0
CONTINUE_ON_ERROR=0
SKIP_SCRIPTS=()
ONLY_SCRIPTS=()

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --continue-on-error)
      CONTINUE_ON_ERROR=1
      shift
      ;;
    --skip)
      [[ $# -ge 2 ]] || die "--skip requires a script filename."
      SKIP_SCRIPTS+=("$2")
      shift 2
      ;;
    --only)
      [[ $# -ge 2 ]] || die "--only requires a script filename."
      ONLY_SCRIPTS+=("$2")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

mapfile -t ALL_SCRIPTS < <(
  find "${SCRIPT_DIR}" -maxdepth 1 -type f -name '[0-9][0-9]-*.sh' -print \
    | sort
)

RUN_SCRIPTS=()
for script_path in "${ALL_SCRIPTS[@]}"; do
  script_name="$(basename "${script_path}")"

  [[ "${script_name}" == "${SELF_NAME}" ]] && continue
  contains "${script_name}" "${SKIP_SCRIPTS[@]}" && continue
  if [[ "${#ONLY_SCRIPTS[@]}" -gt 0 ]] && ! contains "${script_name}" "${ONLY_SCRIPTS[@]}"; then
    continue
  fi

  RUN_SCRIPTS+=("${script_path}")
done

[[ "${#RUN_SCRIPTS[@]}" -gt 0 ]] || die "No scripts selected for execution."

log "Selected ${#RUN_SCRIPTS[@]} script(s):"
for script_path in "${RUN_SCRIPTS[@]}"; do
  log "  - $(basename "${script_path}")"
done

if [[ "${DRY_RUN}" -eq 1 ]]; then
  log "Dry run complete. No scripts executed."
  exit 0
fi

FAILED_SCRIPTS=()

for script_path in "${RUN_SCRIPTS[@]}"; do
  script_name="$(basename "${script_path}")"
  log "▶ Running ${script_name}"

  if bash "${script_path}"; then
    log "✓ Completed ${script_name}"
  else
    status=$?
    FAILED_SCRIPTS+=("${script_name}:${status}")
    log "✗ Failed ${script_name} with exit code ${status}"

    if [[ "${CONTINUE_ON_ERROR}" -ne 1 ]]; then
      die "Stopping after ${script_name}. Re-run with --continue-on-error to keep going."
    fi
  fi
done

if [[ "${#FAILED_SCRIPTS[@]}" -gt 0 ]]; then
  log "Completed with ${#FAILED_SCRIPTS[@]} failure(s): ${FAILED_SCRIPTS[*]}"
  exit 1
fi

log "All selected scripts executed successfully."
