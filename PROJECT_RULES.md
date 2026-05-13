# Project Rules

Coding standards and conventions for the Morph AI Agent project.

---

## Bash Scripts

All setup and operational scripts follow these rules:

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
```

| Rule | Requirement |
|------|-------------|
| Header | `set -euo pipefail` in every script |
| Library | `source lib.sh` for logging (`log`, `die`), env loading, and helpers |
| Idempotency | Every script must be safe to run multiple times without side effects |
| Root check | Use `require_root` if the script needs elevated privileges |
| Env validation | Use `require_env VAR1 VAR2` before accessing environment variables |
| Directory creation | Use `ensure_dir path owner:group mode` instead of raw `mkdir` |
| Logging | Use `log "message"` for info, `die "message"` for fatal errors |
| No inline secrets | Reference `.env` via `load_env`, never hardcode values |

---

## Script Numbering

Scripts in `scripts/` follow a numbered execution order:

| Range | Category | Examples |
|-------|----------|----------|
| `00-09` | Preflight checks | `00-preflight.sh` |
| `10-19` | System dependencies | `10-install-system-deps.sh` |
| `20-29` | 9Router setup | `20-install-9router.sh` |
| `30-39` | Hermes installation | `30-install-hermes.sh` |
| `40-49` | Hermes profile setup | `40-setup-hermes-orchestrator.sh`, `41-setup-hermes-profiles.sh`, `42-seed-profile-souls.sh`, `43-link-discord-channels.sh` |
| `50-59` | Systemd services | `50-setup-systemd.sh`, `55-setup-systemd-per-profile.sh` |
| `60-69` | Reverse proxy | `60-setup-caddy.sh` |
| `90-99` | Health checks | `90-doctor.sh` |

---

## Config Files

| Format | Usage |
|--------|-------|
| YAML | Hermes config (`config.yaml`), 9Router combo definitions |
| TOML / JSON | 9Router internal config (`db.json`) |
| Markdown | SOUL.md persona files, documentation |
| Caddyfile | Caddy reverse proxy configuration |
| INI (systemd) | Service unit files |

---

## Naming Conventions

| Entity | Pattern | Example |
|--------|---------|---------|
| Hermes profile | lowercase, single word | `orchestrator`, `researcher`, `executor` |
| systemd service | `hermes-<profile>-gateway.service` | `hermes-orchestrator-gateway.service` |
| Discord bot | `Morph<Profile>` (PascalCase) | `MorphOrchestrator`, `MorphResearcher` |
| Discord channel | `#<profile>` (lowercase) | `#orchestrator`, `#researcher` |
| Setup script | `XX-<action>.sh` (numbered, kebab-case) | `41-setup-hermes-profiles.sh` |
| Env variable | `UPPER_SNAKE_CASE` | `NINE_ROUTER_API_KEY`, `DISCORD_BOT_TOKEN` |
| Task ID | 16-char lowercase hex | `a1b2c3d4e5f6a7b8` |
| Config directory | `config/<service>/` | `config/hermes/`, `config/caddy/` |

---

## Git Conventions

### Commit Messages

```
<type>: <description>

<optional body>
```

| Type | Usage |
|------|-------|
| `feat` | New feature or profile |
| `fix` | Bug fix |
| `refactor` | Code restructuring without behavior change |
| `docs` | Documentation only |
| `test` | Adding or updating tests |
| `chore` | Maintenance, dependency updates |
| `perf` | Performance improvement |
| `ci` | CI/CD pipeline changes |

### Branch Naming

```
feat/<short-description>
fix/<short-description>
docs/<short-description>
```

Examples: `feat/add-reviewer-profile`, `fix/sqlite-queue-timeout`, `docs/discord-playbook`.

### Protected Branches

- `main` / `master`: requires PR review. No direct push.
- Feature branches: free to push.

---

## Security Rules

| Rule | Enforcement |
|------|-------------|
| No hardcoded secrets | Secrets go in `.env` files only. `.env` is in `.gitignore`. |
| Environment variables | Use `load_env` + `require_env` pattern in scripts |
| Secret rotation | Rotate immediately if a secret appears in logs, chat, or commits |
| API keys | Generated via 9Router dashboard, stored in profile `.env` |
| Discord tokens | One bot token per profile, stored in profile `.env` |
| TLS | All public endpoints behind Caddy with auto-TLS |
| Port exposure | Only ports 22, 80, 443 open. Never expose 9Router port (20128) directly. |

---

## File Permissions

| File Type | Permission | Octal |
|-----------|------------|-------|
| `.env` files (secrets) | Owner read/write only | `600` |
| Config files (YAML, Caddyfile) | Owner read/write, group/other read | `644` |
| Scripts | Owner read/write/execute, group/other read/execute | `755` |
| SOUL.md | Owner read/write, group/other read | `644` |
| SQLite database | Owner read/write only | `600` |
| Handoff directories | Owner read/write/execute | `700` |

---

## Code Standards (for Generated Code)

When the executor profile generates code:

- Follow the language's standard style guide (gofmt, rustfmt, black, prettier)
- Target 80% test coverage minimum
- Use conventional commit messages for all git operations
- No TODO or placeholder code in deliverables
- No debug logging in production code
- Handle errors explicitly at every level
- Validate inputs at system boundaries
