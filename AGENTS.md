# Morph AI Agent — Software Agency

Master context document for coding agents working on this project. Compatible with Claude Code, Codex, Gemini, Kiro, and other AI coding assistants.

---

## Project Overview

Multi-agent autonomous software agency built on Hermes Agent + 9Router + Discord + Caddy. Each agent is a long-lived Hermes profile with full isolation (config, memory, skills, Discord bot). Agents collaborate via an SQLite task queue and communicate with humans via Discord.

**Deployment target:** Ubuntu 22.04 VPS (2 vCPU / 4GB RAM / 80GB storage).
**Lifecycle:** Orchestrator always-on, workers spawn-on-demand.

---

## Tech Stack

| Component | Purpose | Location |
|-----------|---------|----------|
| **Hermes Agent** | Autonomous agent core with profiles, memory, skills, gateway | `~/.hermes/profiles/<name>/` |
| **9Router** | Multi-provider LLM gateway with cost-optimization fallback | `/opt/9router/` |
| **Discord** | Human-agent interface. One bot per profile, one channel per agent. | Discord API |
| **Caddy** | Reverse proxy with auto-TLS | `/etc/caddy/Caddyfile` |
| **systemd** | Service management. One unit per profile gateway. | `/etc/systemd/system/hermes-*-gateway.service` |
| **SQLite** | Task queue for inter-profile communication | `/var/lib/morph-agency/queue.db` |
| **Bash** | Setup scripts (idempotent, `set -euo pipefail`, `source lib.sh`) | `scripts/` |

**Not used (by design):** CrewAI, LangGraph, AutoGen, or any external orchestration framework.

---

## Architecture Summary

See `ARCHITECTURE.md` for full diagrams and decisions. Key points:

- **Orchestrator** receives user requests via Discord, decomposes into tasks, delegates to specialist profiles via SQLite queue
- **Researcher** handles web search, doc lookup, technology scouting
- **Executor** handles code generation, file ops, git workflow, build/test
- All profiles share a single 9Router instance with named combos: `combo:premium`, `combo:balanced`, `combo:budget`
- Inter-profile communication: SQLite task queue (primary) + filesystem handoff (large payloads)
- Memory per profile is fully isolated (MEMORY.md, USER.md, sessions)
- Shared skills are read-only at `/var/lib/morph-agency/skills/common/`

---

## Active Agent Profiles

| Profile | Role | LLM Combo | Discord | Lifecycle |
|---------|------|-----------|---------|-----------|
| `orchestrator` | Task router, planner, synthesis | `combo:premium` | `#orchestrator` | always-on |
| `researcher` | Web research, analysis | `combo:balanced` | `#researcher` | spawn-on-demand |
| `executor` | Code gen, build/test, git ops | `combo:budget` | `#executor` | spawn-on-demand |

See `AGENT_REGISTRY.md` for the full roster including planned profiles.

---

## Key Paths

### Repository (this project)

```
config/hermes/profiles/<name>/SOUL.md       Agent persona definition
config/hermes/profiles/<name>/config.yaml   Agent runtime config
config/caddy/Caddyfile                      Caddy reverse proxy template
scripts/                                    Idempotent setup scripts (00-90)
scripts/lib.sh                              Shared bash library
systemd/                                    systemd unit templates
.env.example                                Environment variable template
```

### VPS Runtime

```
~/.hermes/profiles/<name>/                  Per-profile Hermes home
/var/lib/morph-agency/queue.db              SQLite task queue (shared)
/var/lib/morph-agency/handoff/              Large payload exchange
/var/lib/morph-agency/skills/common/        Shared read-only skills
/opt/9router/                               9Router installation
/etc/caddy/Caddyfile                        Active Caddy config
/etc/systemd/system/hermes-*-gateway.service  Active systemd units
/home/hermes/workspace/                     Default working directory
```

---

## Common Commands

### Hermes

```bash
hermes profile create <name>              # Create a new profile
hermes -p <name> gateway start            # Start Discord gateway for profile
hermes -p <name> chat                     # Interactive CLI session
hermes -p <name> -z "prompt"              # One-shot execution
```

### systemd

```bash
sudo systemctl status hermes-orchestrator-gateway
sudo systemctl restart hermes-orchestrator-gateway
sudo journalctl -u hermes-orchestrator-gateway -f
sudo systemctl status 9router
```

### 9Router

```bash
# Dashboard at https://<domain>/dashboard
# API endpoint at https://<domain>/v1
# Local port: 127.0.0.1:20128 (never expose directly)
```

### Setup Scripts

```bash
cd /opt/ai-agent/scripts
sudo ./00-preflight.sh       # Validate environment
sudo ./90-doctor.sh          # Health check all components
```

---

## Conventions

### Naming

- Profile names: lowercase, single word (`orchestrator`, `researcher`, `executor`)
- systemd units: `hermes-<profile>-gateway.service`
- Discord bots: `Morph<Profile>` (PascalCase)
- Discord channels: `#<profile>` (lowercase)
- Scripts: `XX-<action>.sh` (numbered, kebab-case)
- Env vars: `UPPER_SNAKE_CASE`

### File Structure

- One SOUL.md per profile (identity, authority, permissions, behavior)
- One config.yaml per profile (LLM, delegation, terminal, memory)
- Shared config templates in `config/hermes/` (base config)
- Profile-specific overrides in `config/hermes/profiles/<name>/`

### Script Patterns

- All scripts: `set -euo pipefail` + `source lib.sh`
- Idempotent (safe to re-run)
- Use `log` for info, `die` for fatal
- Use `require_root`, `load_env`, `require_env` from lib.sh
- Numbered 00-90 for execution order

### Git

- Conventional commits: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`
- Feature branches: `feat/<description>`
- PR required for `main`

### Security

- No hardcoded secrets anywhere
- All secrets in `.env` (gitignored)
- File permissions: 600 for secrets, 644 for configs, 755 for scripts
- Caddy handles TLS. Never expose 9Router port directly.

---

## Related Documentation

| Document | Content |
|----------|---------|
| `ARCHITECTURE.md` | System design, Mermaid diagrams, memory budget, task queue schema, failure handling, roadmap |
| `AGENT_REGISTRY.md` | All profiles with roles, capabilities, LLM combos, tool permissions |
| `DISCORD_PLAYBOOK.md` | Discord channel structure, commands, escalation, output formats |
| `PROJECT_RULES.md` | Coding standards, naming, commit conventions, security rules |
| `WORKFLOW.md` | Adding/modifying profiles, testing, git flow, onboarding checklist |
| `INDEX.md` | File map, script execution order, config relationships |
