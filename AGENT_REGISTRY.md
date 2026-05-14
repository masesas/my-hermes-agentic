# Agent Registry

Master registry of all Hermes agent profiles in the Morph AI Software Agency.

---

## Profile Roster

| Profile | Role | Capability Summary | LLM Combo | Discord Channel | Discord Bot | Lifecycle | Status |
|---------|------|--------------------|-----------|-----------------|-------------|-----------|--------|
| `orchestrator` | Task Router & Planner | Decompose user requests, delegate to specialists, synthesize results, manage task queue | `morph-orchestrator` | `#orchestrator` | `MorphOrchestrator` | always-on | **active** |
| `researcher` | Web Research & Analysis | Web search, doc lookup, technology scouting, competitive analysis, structured reports | `morph-researcher` | `#researcher` | `MorphResearcher` | spawn-on-demand | **active** |
| `executor` | Code Generation & Ops | Code gen, file ops, git workflow, build/test execution, infrastructure scripts | `morph-executor` | `#executor` | `MorphExecutor` | spawn-on-demand | **active** |
| `reviewer` | Code Review & QA | Code quality analysis, security audit, test coverage review, PR feedback | `morph-reviewer` | `#reviewer` | `MorphReviewer` | spawn-on-demand | planned |
| `devops` | Infrastructure & Deployment | System ops, deployment automation, monitoring setup, security hardening | `morph-devops` | `#devops` | `MorphDevOps` | spawn-on-demand | planned |
| `writer` | Documentation & Content | Technical writing, README generation, API docs, changelog, blog drafts | TBD | `#writer` | `MorphWriter` | spawn-on-demand | candidate |
| `monitor` | Observability & Alerts | Health checks, cost tracking, uptime monitoring, anomaly detection | TBD | `#status` | `MorphMonitor` | cron-based | candidate |

---

## Phase 1 MVP Profiles

### orchestrator

| Attribute | Value |
|-----------|-------|
| **Profile path** | `~/.hermes/profiles/orchestrator/` |
| **systemd unit** | `hermes-gateway-orchestrator.service` (user-level) |
| **LLM combo** | `morph-orchestrator` (Claude Sonnet 4.6 > GPT-4o > Gemini 2.5 Pro) |
| **Max turns** | 160 |
| **Max concurrent children** | 3 |
| **Max spawn depth** | 1 |
| **Delegation** | Enabled (orchestrator_enabled: true) |

**Tool permissions:**
- SQLite queue: read/write (enqueue tasks, poll results)
- Filesystem handoff: read/write
- Discord: send messages to all agency channels
- `delegate_task`: allowed
- Terminal: workspace only (`/home/hermes/workspace`)

**Decision authority:**
- Approve or reject subtask results
- Re-assign failed tasks to same or different profile
- Escalate to user when confidence is low
- Set task priority

**Interaction patterns:**
- Receives all user requests via `#orchestrator`
- Decomposes into subtasks, enqueues in SQLite
- Polls for results, synthesizes, reports back to user
- Never executes code or performs research directly

---

### researcher

| Attribute | Value |
|-----------|-------|
| **Profile path** | `~/.hermes/profiles/researcher/` |
| **systemd unit** | `hermes-gateway-researcher.service` (user-level) |
| **LLM combo** | `morph-researcher` (Gemini 2.5 Flash > Claude Haiku 4.5 > GPT-4o-mini) |
| **Max turns** | 80 |
| **Max concurrent children** | 2 |
| **Max spawn depth** | 1 |
| **Delegation** | Disabled (orchestrator_enabled: false) |

**Tool permissions:**
- Web search: allowed
- Documentation lookup: allowed
- SQLite queue: read/write (claim tasks, write results)
- Filesystem handoff: write to `/var/lib/morph-agency/handoff/<task-id>/output/`
- Terminal: read-only workspace access
- Git: none
- File modification: none (outside handoff directory)

**Decision authority:**
- None over other profiles
- Can choose research depth and strategy within a task
- Reports findings; does not make architectural decisions

**Interaction patterns:**
- Receives tasks from orchestrator via SQLite queue
- Writes findings as structured reports
- Large artifacts go to filesystem handoff
- Visible in `#researcher` for observability

---

### executor

| Attribute | Value |
|-----------|-------|
| **Profile path** | `~/.hermes/profiles/executor/` |
| **systemd unit** | `hermes-gateway-executor.service` (user-level) |
| **LLM combo** | `morph-executor` (Claude Haiku 4.5 > Gemini 2.5 Flash > DeepSeek V3) |
| **Max turns** | 80 |
| **Max concurrent children** | 2 |
| **Max spawn depth** | 1 |
| **Delegation** | Disabled (orchestrator_enabled: false) |

**Tool permissions:**
- Terminal: full access within `/home/hermes/workspace`
- File system: create/modify/delete in workspace and handoff directory
- Git: push to feature branches only (main/master blocked)
- Build/test: run builds, execute tests, report results
- Package install: project-local only (no `sudo` system installs without approval)
- SQLite queue: read/write (claim tasks, write results)
- Filesystem handoff: read/write

**Decision authority:**
- None over other profiles
- Can choose implementation approach within the spec
- Cannot make architectural decisions not in the task
- Cannot deploy to production

**Interaction patterns:**
- Receives tasks from orchestrator via SQLite queue
- Implements code, runs tests, reports results with evidence
- Writes artifacts to filesystem handoff
- Visible in `#executor` for observability

---

## Phase 2 Planned Profiles

### reviewer

**Justification for separate profile:** Needs fresh context without implementation bias. Uses a different LLM reasoning profile (premium) to catch subtle issues the executor's budget model might miss.

| Attribute | Value |
|-----------|-------|
| **LLM combo** | `morph-reviewer` |
| **Lifecycle** | spawn-on-demand |
| **Discord channel** | `#reviewer` |

**Tool permissions:**
- Read-only access to workspace and handoff artifacts
- SQLite queue: read/write
- Git: read-only (diff, log, blame)
- No file modification, no code execution

**Decision authority:**
- Approve or request changes on code deliverables
- Flag security, performance, or quality issues
- Cannot merge or deploy

---

### devops

**Justification for separate profile:** Requires elevated system permissions (systemd, apt, firewall). Separate security boundary from code-execution agents.

| Attribute | Value |
|-----------|-------|
| **LLM combo** | `morph-devops` |
| **Lifecycle** | spawn-on-demand |
| **Discord channel** | `#devops` |

**Tool permissions:**
- System operations: systemctl, journalctl, apt (with approval)
- Caddy/Nginx config management
- Firewall rules
- SSL certificate management
- Deployment scripts execution (with user approval for production)
- SQLite queue: read/write

**Decision authority:**
- Infrastructure changes within approved scope
- Cannot deploy to production without user confirmation
- Cannot modify security boundaries without approval

---

## Phase 3 Candidates

### writer

**Justification:** Different tone and style requirements from code agents. Specialized prompting for technical writing, user-facing documentation, and content generation.

### monitor

**Justification:** Long-running background process. Cron-based health monitoring, cost tracking, and alerting. Fundamentally different lifecycle from task-based agents.
