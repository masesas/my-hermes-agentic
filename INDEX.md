# Index

High-level module and file map for the Morph AI Agent project.

---

## Project Structure

```
ai-agent/
├── .claude/                        # IDE settings (Claude Code)
│   ├── settings.json
│   └── settings.local.json
├── apps/                           # Project applications and CLIs
│   └── morph-task/                 # Role-enforcing Beads task wrapper CLI
├── config/                         # All service configuration
│   ├── caddy/
│   │   └── Caddyfile               # Reverse proxy config (Caddy)
│   └── hermes/
│       ├── config.yaml             # Base Hermes config template
│       ├── SOUL.md                 # Base orchestrator persona
│       └── profiles/               # Per-agent profile configs
│           ├── orchestrator/
│           │   ├── SOUL.md          # Orchestrator identity & rules
│           │   └── config.yaml      # LLM combo morph-orchestrator, delegation enabled
│           ├── researcher/
│           │   ├── SOUL.md          # Researcher identity & rules
│           │   └── config.yaml      # LLM combo morph-researcher, no delegation
│           └── executor/
│               ├── SOUL.md          # Executor identity & rules
│               └── config.yaml      # LLM combo morph-executor
├── docs/                           # Extended documentation
│   ├── ADDING_NEW_AGENT.md         # Operational runbook for adding profiles
│   ├── VPS_DEPLOYMENT.md           # VPS deployment guide
│   ├── DISCORD_SETUP.md            # Discord bot/channel setup
│   ├── AUTONOMOUS_DISCORD_AGENTS.md # Autonomous Discord behavior
│   ├── AGENT_ROLE_ENFORCEMENT.md    # Role enforcement and reset runbook
│   ├── BEADS_SQLITE_RECONCILE_PLAN.md # Planned drift reconciliation
│   ├── MORPH_TASK_MULTI_PROJECT.md # Multi-project task namespace guide
│   └── agent/
│       └── begin.md                # Original setup prompt (v2)
├── scripts/                        # Idempotent setup & ops scripts
│   ├── lib.sh                      # Shared library (log, die, require_env, etc.)
│   ├── 00-preflight.sh             # OS and env validation
│   ├── 10-install-system-deps.sh   # System packages (curl, git, etc.)
│   ├── 20-install-9router.sh       # 9Router LLM gateway installation
│   ├── 21-update-9router.sh        # 9Router update/install helper
│   ├── 30-install-hermes.sh        # Hermes Agent installation
│   ├── 40-setup-hermes-orchestrator.sh  # Single orchestrator profile setup
│   ├── 45-create-agent-profile.sh  # Interactive new agent profile generator
│   ├── 46-install-beads.sh         # Install real Beads bd binary safely
│   ├── 47-install-morph-task.sh    # Build/install role-enforcing task wrapper
│   ├── 48-build-morph-task.sh      # Build distributable morph-task binaries
│   ├── 49-reset-agent-memory.sh    # Selectively reset learned agent state
│   ├── 50-setup-systemd.sh         # 9Router/system service installation
│   ├── 55-setup-systemd-per-profile.sh # Hermes user-level gateway services
│   ├── 60-setup-caddy.sh           # Caddy reverse proxy setup when WEB_SERVER=caddy
│   ├── 65-setup-nginx-direct.sh    # Nginx direct reverse proxy setup
│   └── 90-doctor.sh                # Health check & diagnostics
├── systemd/                        # systemd service templates
│   ├── 9router.service             # 9Router service unit
│   └── 9router.service             # 9Router service unit
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
| `apps/morph-task/` | Go CLI project for the future `morph-task` role-enforcing Beads wrapper. |
| `scripts/lib.sh` | Shared bash library. Every script sources this. Provides `log`, `die`, `require_root`, `load_env`, `require_env`, `ensure_dir`. |
| `config/hermes/profiles/*/SOUL.md` | Agent persona definition. Loaded by Hermes on gateway start. Controls identity, authority, permissions, and behavioral rules. |
| `config/hermes/profiles/*/config.yaml` | Agent runtime config. LLM combo, delegation limits, terminal settings, memory, Discord options. |
| `.env` | Runtime secrets. Bot tokens, API keys, domain config. Never committed. |
| `ARCHITECTURE.md` | Canonical architecture reference. Mermaid diagrams, memory budget, task queue schema, orchestration patterns, failure handling, roadmap. |
| `AGENT_REGISTRY.md` | Master list of all agent profiles with capabilities, LLM assignments, and lifecycle status. |
| `docs/ADDING_NEW_AGENT.md` | Step-by-step operational runbook for adding a new Hermes/Discord/9Router agent. |
| `docs/AGENT_ROLE_ENFORCEMENT.md` | Reset and enforcement runbook for learned behavior drift. |
| `docs/BEADS_SQLITE_RECONCILE_PLAN.md` | Planned Beads/SQLite drift detection and repair design. |
| `docs/MORPH_TASK_MULTI_PROJECT.md` | Multi-project namespace and workspace guide for `morph-task`. |

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
21-update-9router        Optional ops script to update existing 9Router,
                         or install it if missing
        |
    [MANUAL STEP]        Open 9Router dashboard, configure providers,
                         create API key, update .env
        |
30-install-hermes        Install Hermes Agent
        |
40-setup-hermes-*        Configure Hermes profiles and SOUL.md
        |
44-configure-agent-routing
                         Install autonomous routing and anti-loop policy
        |
45-create-agent-profile  Optional interactive generator for additional agents
        |
46-install-beads       Install real Beads bd binary to /opt/morph-agency/bin
        |
47-install-morph-task   Build/install morph-task wrapper and role policy
        |
48-build-morph-task    Optional local/CI release binary build
51-create-project      Onboard a new morph-task project (workspace, handoff, policy)
        |
49-reset-agent-memory Optional selective reset for learned behavior drift
        |
50-setup-systemd         Install 9Router/system services
        |
55-setup-systemd-*       Per-profile Hermes user-level systemd units
        |
60-setup-caddy           Configure Caddy only if WEB_SERVER=caddy
65-setup-nginx-direct    Configure Nginx if WEB_SERVER=nginx-direct
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
       ├── Uses literal 9Router endpoint and `morph-<profile>` combo names
       ├── Sets delegation limits, agent behavior, Discord gateway config
       │
       └──> 9Router combos (`morph-orchestrator`, `morph-researcher`, `morph-executor`)
             ├── Defined in 9Router dashboard on VPS
             └── Routes to Anthropic, OpenAI, Google, DeepSeek, etc.

config/nginx/9router-nginx-direct.conf
 ├── Used when WEB_SERVER=nginx-direct
 └── Routes HTTPS traffic to 9Router (127.0.0.1:20128)

/home/hermes/.config/systemd/user/hermes-gateway-<profile>.service
 └── Runs: hermes --profile <profile> gateway run

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
| `/etc/nginx/sites-enabled/my-hermes.otomotives.com.conf` | Active Nginx direct reverse proxy config |
| `/home/hermes/.config/systemd/user/hermes-gateway-*.service` | Active Hermes user-level gateway units |
| `/home/hermes/workspace/` | Default working directory for all profiles |
