# Index

High-level module and file map for the Morph AI Agent project.

---

## Project Structure

```
ai-agent/
├── .claude/                        # IDE settings (Claude Code)
│   ├── settings.json
│   └── settings.local.json
├── config/                         # All service configuration
│   ├── caddy/
│   │   └── Caddyfile               # Reverse proxy config (Caddy)
│   └── hermes/
│       ├── config.yaml             # Base Hermes config template
│       ├── SOUL.md                 # Base orchestrator persona
│       └── profiles/               # Per-agent profile configs
│           ├── orchestrator/
│           │   ├── SOUL.md          # Orchestrator identity & rules
│           │   └── config.yaml      # LLM combo:premium, delegation enabled
│           ├── researcher/
│           │   ├── SOUL.md          # Researcher identity & rules
│           │   └── config.yaml      # LLM combo:balanced, no delegation
│           └── executor/
│               └── SOUL.md          # Executor identity & rules
├── docs/                           # Extended documentation
│   └── agent/
│       └── begin.md                # Original setup prompt (v2)
├── scripts/                        # Idempotent setup & ops scripts
│   ├── lib.sh                      # Shared library (log, die, require_env, etc.)
│   ├── 00-preflight.sh             # OS and env validation
│   ├── 10-install-system-deps.sh   # System packages (curl, git, etc.)
│   ├── 20-install-9router.sh       # 9Router LLM gateway installation
│   ├── 30-install-hermes.sh        # Hermes Agent installation
│   ├── 40-setup-hermes-orchestrator.sh  # Single orchestrator profile setup
│   ├── 50-setup-systemd.sh         # systemd unit installation
│   ├── 60-setup-caddy.sh           # Caddy reverse proxy setup
│   └── 90-doctor.sh                # Health check & diagnostics
├── systemd/                        # systemd service templates
│   ├── 9router.service             # 9Router service unit
│   └── hermes-discord.service      # Hermes Discord gateway unit
├── .env.example                    # Environment variable template
├── .env                            # Actual secrets (gitignored)
├── .gitignore                      # Git ignore rules
├── AGENTS.md                       # Master context (agent-agnostic)
├── AGENT_REGISTRY.md               # All profiles: roles, combos, channels
├── ARCHITECTURE.md                 # System design, diagrams, decisions
├── CLAUDE.md                       # Claude Code auto-detect (mirrors AGENTS.md)
├── DISCORD_PLAYBOOK.md             # Discord interaction guide
├── INDEX.md                        # This file
├── PROJECT_RULES.md                # Coding standards & conventions
├── README.md                       # Project overview & setup instructions
└── WORKFLOW.md                     # Development workflow & git flow
```

---

## Key Files

| File | Role |
|------|------|
| `scripts/lib.sh` | Shared bash library. Every script sources this. Provides `log`, `die`, `require_root`, `load_env`, `require_env`, `ensure_dir`. |
| `config/hermes/profiles/*/SOUL.md` | Agent persona definition. Loaded by Hermes on gateway start. Controls identity, authority, permissions, and behavioral rules. |
| `config/hermes/profiles/*/config.yaml` | Agent runtime config. LLM combo, delegation limits, terminal settings, memory, Discord options. |
| `.env` | Runtime secrets. Bot tokens, API keys, domain config. Never committed. |
| `ARCHITECTURE.md` | Canonical architecture reference. Mermaid diagrams, memory budget, task queue schema, orchestration patterns, failure handling, roadmap. |
| `AGENT_REGISTRY.md` | Master list of all agent profiles with capabilities, LLM assignments, and lifecycle status. |

---

## Script Execution Order

Scripts are numbered for sequential execution during initial VPS setup:

```
00-preflight.sh          Validate OS, env vars, prerequisites
        |
10-install-system-deps   Install system packages
        |
20-install-9router       Install and configure 9Router
        |
    [MANUAL STEP]        Open 9Router dashboard, configure providers,
                         create API key, update .env
        |
30-install-hermes        Install Hermes Agent
        |
40-setup-hermes-*        Configure Hermes profiles and SOUL.md
        |
50-setup-systemd         Install systemd service units
        |
55-setup-systemd-*       Per-profile systemd units (Phase 1)
        |
60-setup-caddy           Configure Caddy reverse proxy
        |
90-doctor                Run health checks on all components
```

---

## Config File Relationships

```
.env
 ├── Referenced by: scripts/lib.sh (load_env)
 ├── Provides: PUBLIC_DOMAIN, NINE_ROUTER_*, DISCORD_BOT_TOKEN, HERMES_*
 │
 └──> config/hermes/profiles/*/config.yaml
       ├── Uses: ${NINE_ROUTER_BASE_URL}, ${NINE_ROUTER_API_KEY}
       ├── Sets: LLM combo, delegation limits, agent behavior
       │
       └──> 9Router combos (premium, balanced, budget)
             ├── Defined in: 9Router db.json on VPS
             └── Routes to: Anthropic, OpenAI, Google, DeepSeek

config/caddy/Caddyfile
 ├── Uses: {{PUBLIC_DOMAIN}}, {{ADMIN_EMAIL}} (template vars)
 └── Routes: all traffic to 9Router (127.0.0.1:20128)

systemd/hermes-discord.service
 ├── Uses: {{HERMES_USER}} (template var)
 └── Runs: hermes gateway start

/var/lib/morph-agency/queue.db
 ├── Shared by: all Hermes profiles
 └── Schema: tasks table (see ARCHITECTURE.md)
```

---

## Runtime Paths (on VPS)

| Path | Purpose |
|------|---------|
| `~/.hermes/profiles/<name>/` | Per-profile Hermes home directory |
| `/var/lib/morph-agency/queue.db` | SQLite task queue (shared) |
| `/var/lib/morph-agency/handoff/` | Large payload exchange between profiles |
| `/var/lib/morph-agency/skills/common/` | Shared read-only skills |
| `/opt/9router/` | 9Router installation |
| `/etc/caddy/Caddyfile` | Active Caddy config |
| `/etc/systemd/system/hermes-*-gateway.service` | Active systemd units |
| `/home/hermes/workspace/` | Default working directory for all profiles |
