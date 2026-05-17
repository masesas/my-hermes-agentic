#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_root
load_env
require_env PUBLIC_BASE_URL NINE_ROUTER_INITIAL_PASSWORD NINE_ROUTER_JWT_SECRET NINE_ROUTER_API_KEY_SECRET NINE_ROUTER_MACHINE_ID_SALT

ROUTER_USER="router9"
APP_DIR="/opt/9router/app"
BIN_DIR="/opt/9router/bin"
NODE_RUNTIME_DIR="/opt/9router/node"
DATA_DIR="/var/lib/9router"
ENV_DIR="/etc/9router"
ENV_TARGET="${ENV_DIR}/9router.env"

node_version_at_least() {
  local version="$1"
  local min_major=20
  local min_minor=9
  local major minor

  version="${version#v}"
  major="${version%%.*}"
  version="${version#*.}"
  minor="${version%%.*}"

  [[ "${major}" =~ ^[0-9]+$ ]] || return 1
  [[ "${minor}" =~ ^[0-9]+$ ]] || return 1

  if (( major > min_major )); then
    return 0
  fi
  if (( major == min_major && minor >= min_minor )); then
    return 0
  fi
  return 1
}

resolve_node_bin() {
  local candidates=()
  local candidate version

  if [[ -n "${NINE_ROUTER_NODE_BIN:-}" ]]; then
    candidates+=("${NINE_ROUTER_NODE_BIN}")
  fi

  if command -v node >/dev/null 2>&1; then
    candidates+=("$(command -v node)")
  fi

  candidates+=(
    /usr/local/bin/node
    /usr/bin/node
    /opt/node/bin/node
    /root/.nvm/versions/node/*/bin/node
    /home/agentic/.nvm/versions/node/*/bin/node
  )

  for candidate in "${candidates[@]}"; do
    for candidate in ${candidate}; do
      [[ -x "${candidate}" ]] || continue
      version="$(${candidate} -v 2>/dev/null || true)"
      if node_version_at_least "${version}"; then
        printf '%s\n' "${candidate}"
        return 0
      fi
      log "Skipping Node candidate ${candidate} (${version:-unknown}); 9Router requires >=20.9.0." >&2
    done
  done

  return 1
}

resolve_npm_bin() {
  local node_dir="$1"
  local candidate

  if [[ -n "${NINE_ROUTER_NPM_BIN:-}" ]]; then
    [[ -x "${NINE_ROUTER_NPM_BIN}" ]] || die "NINE_ROUTER_NPM_BIN is not executable: ${NINE_ROUTER_NPM_BIN}"
    printf '%s\n' "${NINE_ROUTER_NPM_BIN}"
    return 0
  fi

  candidate="${node_dir}/npm"
  if [[ -x "${candidate}" ]]; then
    printf '%s\n' "${candidate}"
    return 0
  fi

  if command -v npm >/dev/null 2>&1; then
    printf '%s\n' "$(command -v npm)"
    return 0
  fi

  return 1
}

patch_public_oauth_redirects() {
  local oauth_modal="${APP_DIR}/src/shared/components/OAuthModal.js"

  [[ -f "${oauth_modal}" ]] || return 0

  if grep -q 'http://localhost:${appPort}/callback' "${oauth_modal}"; then
    log "Patching 9Router OAuth browser redirects to use window.location.origin..."
    sudo -u "${ROUTER_USER}" python3 - "${oauth_modal}" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
old = '''      const appPort = window.location.port || (window.location.protocol === "https:" ? "443" : "80");
      let redirectUri;
      if (provider === "codex") {
        redirectUri = "http://localhost:1455/auth/callback";
      } else {
        redirectUri = `http://localhost:\${appPort}/callback`;
      }
'''
new = '''      const appPort = window.location.port || (window.location.protocol === "https:" ? "443" : "80");
      const isPublicOrigin = window.location.hostname !== "localhost" && window.location.hostname !== "127.0.0.1";
      // Providers whose OAuth client accepts arbitrary HTTPS redirect URIs.
      const publicCapableProviders = new Set(["codex", "iflow", "kiro", "qoder", "antigravity", "gitlab"]);
      let redirectUri;
      if (provider === "codex") {
        redirectUri = "http://localhost:1455/auth/callback";
      } else if (isPublicOrigin && publicCapableProviders.has(provider)) {
        redirectUri = `\${window.location.origin}/callback`;
      } else {
        redirectUri = `http://localhost:\${appPort}/callback`;
      }
'''
if old not in text:
    raise SystemExit("OAuth redirect block not found; 9Router source may have changed")
path.write_text(text.replace(old, new))
PY
  fi
}

stage_node_runtime_if_needed() {
  local node_bin="$1"
  local npm_bin="$2"
  local node_dir node_prefix staged_prefix version

  if sudo -u "${ROUTER_USER}" test -x "${node_bin}" \
    && sudo -u "${ROUTER_USER}" test -x "${npm_bin}"; then
    return 0
  fi

  node_dir="$(dirname "${node_bin}")"
  node_prefix="$(cd "${node_dir}/.." && pwd)"
  version="$(${node_bin} -v | sed 's/^v//')"
  staged_prefix="${NODE_RUNTIME_DIR}/node-v${version}"

  log "Node runtime is not executable by ${ROUTER_USER}; staging ${node_prefix} to ${staged_prefix}."
  rm -rf "${staged_prefix}"
  install -d -m 0755 "${NODE_RUNTIME_DIR}"
  cp -a "${node_prefix}" "${staged_prefix}"
  chown -R root:root "${staged_prefix}"
  chmod -R a+rX "${staged_prefix}"

  NODE_BIN="${staged_prefix}/bin/node"
  NPM_BIN="${staged_prefix}/bin/npm"
  NODE_BIN_DIR="${staged_prefix}/bin"

  [[ -x "${NODE_BIN}" ]] || die "Staged node is not executable: ${NODE_BIN}"
  [[ -x "${NPM_BIN}" ]] || die "Staged npm is not executable: ${NPM_BIN}"
}

if ! id "${ROUTER_USER}" >/dev/null 2>&1; then
  log "Creating ${ROUTER_USER} system user..."
  useradd --system --create-home --home-dir /opt/9router --shell /usr/sbin/nologin "${ROUTER_USER}"
fi

ensure_dir /opt/9router "${ROUTER_USER}:${ROUTER_USER}" 755
ensure_dir "${BIN_DIR}" "${ROUTER_USER}:${ROUTER_USER}" 755
ensure_dir "${NODE_RUNTIME_DIR}" root:root 755
ensure_dir "${DATA_DIR}" "${ROUTER_USER}:${ROUTER_USER}" 750
ensure_dir "${ENV_DIR}" root:root 755

if [[ ! -d "${APP_DIR}/.git" ]]; then
  log "Cloning 9Router..."
  sudo -u "${ROUTER_USER}" git clone https://github.com/decolua/9router.git "${APP_DIR}"
else
  log "Updating 9Router repository..."
  sudo -u "${ROUTER_USER}" git -C "${APP_DIR}" pull --ff-only
fi

patch_public_oauth_redirects

log "Installing and building 9Router..."
NODE_BIN="$(resolve_node_bin)" || die "No compatible Node.js found. Install Node.js >=20.9.0 or set NINE_ROUTER_NODE_BIN=/path/to/node in .env."
NODE_BIN_DIR="$(dirname "${NODE_BIN}")"
NPM_BIN="$(resolve_npm_bin "${NODE_BIN_DIR}")" || die "npm not found for Node.js at ${NODE_BIN}. Set NINE_ROUTER_NPM_BIN=/path/to/npm in .env."
stage_node_runtime_if_needed "${NODE_BIN}" "${NPM_BIN}"

log "Using Node: ${NODE_BIN} ($("${NODE_BIN}" -v))"
log "Using npm: ${NPM_BIN} ($(env PATH="${NODE_BIN_DIR}:${PATH}" "${NPM_BIN}" -v))"

cat > "${BIN_DIR}/npm-run" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export PATH="${NODE_BIN_DIR}:\${PATH:-}"
exec "${NPM_BIN}" "\$@"
EOF
chmod 755 "${BIN_DIR}/npm-run"
chown "${ROUTER_USER}:${ROUTER_USER}" "${BIN_DIR}/npm-run"

cat > "${BIN_DIR}/npm-start" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export PATH="${NODE_BIN_DIR}:\${PATH:-}"
cd "${APP_DIR}"
exec "${NPM_BIN}" run start
EOF
chmod 755 "${BIN_DIR}/npm-start"
chown "${ROUTER_USER}:${ROUTER_USER}" "${BIN_DIR}/npm-start"

# Keep the selected Node directory first in PATH because npm's shebang uses
# /usr/bin/env node. Without this, sudo/systemd may fall back to an older
# distro Node even when root's interactive shell uses nvm Node 24.
sudo -u "${ROUTER_USER}" env PATH="${NODE_BIN_DIR}:${PATH}" "${BIN_DIR}/npm-run" --prefix "${APP_DIR}" install
sudo -u "${ROUTER_USER}" env PATH="${NODE_BIN_DIR}:${PATH}" "${BIN_DIR}/npm-run" --prefix "${APP_DIR}" run build

cat > "${ENV_TARGET}" <<EOF
NODE_ENV=production
PORT=20128
HOSTNAME=127.0.0.1
DATA_DIR=${DATA_DIR}
NEXT_PUBLIC_BASE_URL=${PUBLIC_BASE_URL}
NEXT_PUBLIC_CLOUD_URL=https://9router.com
BASE_URL=${PUBLIC_BASE_URL}
CLOUD_URL=${PUBLIC_BASE_URL}
NEXTAUTH_URL=${PUBLIC_BASE_URL}
AUTH_URL=${PUBLIC_BASE_URL}
INITIAL_PASSWORD=${NINE_ROUTER_INITIAL_PASSWORD}
JWT_SECRET=${NINE_ROUTER_JWT_SECRET}
API_KEY_SECRET=${NINE_ROUTER_API_KEY_SECRET}
MACHINE_ID_SALT=${NINE_ROUTER_MACHINE_ID_SALT}
ENABLE_REQUEST_LOGS=false
NINE_ROUTER_NODE_BIN=${NODE_BIN}
NINE_ROUTER_NPM_BIN=${NPM_BIN}
NINE_ROUTER_NODE_BIN_DIR=${NODE_BIN_DIR}
EOF

chmod 600 "${ENV_TARGET}"
chown root:"${ROUTER_USER}" "${ENV_TARGET}"

log "9Router installed. It will listen only on 127.0.0.1:20128 behind Caddy."
