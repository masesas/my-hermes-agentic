#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

OUT_DIR="${OUT_DIR:-${STARTER_DIR}/dist}"
TARGETS=(
  "linux amd64 morph-task-linux-amd64"
  "linux arm64 morph-task-linux-arm64"
)

command -v go >/dev/null 2>&1 || die "go binary not found."
mkdir -p "${OUT_DIR}"

for target in "${TARGETS[@]}"; do
  read -r goos goarch name <<<"${target}"
  log "Building ${name}..."
  (
    cd "${STARTER_DIR}/apps/morph-task"
    GOOS="${goos}" GOARCH="${goarch}" CGO_ENABLED=0 go build -trimpath -ldflags='-s -w' -o "${OUT_DIR}/${name}" ./cmd/morph-task
  )
  chmod 755 "${OUT_DIR}/${name}"
done

log "morph-task binaries written to ${OUT_DIR}."
