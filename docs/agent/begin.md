# Morph AI Agent — Software Agency Setup Prompt (v2)

> **Purpose**: Prompt komprehensif untuk dikirim ke coding agent (Claude Code, Codex, Cursor, dll) untuk membangun multi-agent autonomous software agency di atas Hermes Agent + 9router stack.
>
> **Version**: 2.0
> **Status**: Ready to send

---

## 📑 Table of Contents

1. [Context](#context)
2. [Vision](#vision-software-agency)
3. [Architectural Decisions](#architectural-decisions-locked--do-not-deviate)
4. [Required Deliverables](#required-deliverables)
5. [Research Mandatory](#research-mandatory)
6. [Constraints](#constraints-hard-rules)
7. [Output Format](#output-format)
8. [Clarification Required](#clarification-required-before-start-working)
9. [Pre-send Checklist](#-pre-send-checklist)

---

## Context

- **Project**: `morph-ai-agent` (greenfield, setup-only state)
- **Existing foundation** (sudah ter-script di `/scripts`):
  - **Hermes Agent** (Nous Research) — autonomous agent core
  - **9router** — multi-provider LLM gateway with cost-optimization fallback
  - **Discord integration** via `hermes-discord.service`
  - **Caddy** reverse proxy + systemd services
  - `SOUL.md` — Hermes persona/identity file (current single instance)

### Project structure

```
.claude/                          # IDE settings
config/
  caddy/Caddyfile
  hermes/
    config.yaml                   # current single profile
    SOUL.md
scripts/
  00-preflight.sh
  10-install-system-deps.sh
  20-install-9router.sh
  30-install-hermes.sh
  40-setup-hermes-orchestrator.sh
  50-setup-systemd.sh
  60-setup-caddy.sh
  90-doctor.sh
  lib.sh
systemd/
  9router.service
  hermes-discord.service
.env
.env.example
.gitignore
README.md
```

- **Deployment**: VPS, 24/7 operation
- **Existing docs**: NONE (greenfield documentation needed)

---

## Vision: "Software Agency"

Build a **multi-agent autonomous software agency** dimana setiap agent adalah specialist long-lived untuk role tertentu (multi-discipline: coding, research, DevOps, content, dll). Agent berkolaborasi via orchestrator. Operasi visible & controllable via Discord dengan **hybrid visibility** (human ↔ agent ↔ agent).

---

## Architectural Decisions (LOCKED — DO NOT DEVIATE)

### 1. Orchestration: Hermes Profiles + Subagents (Hybrid)

#### Layer 1 — Profile per Agent Role (Long-lived Specialists)

Setiap role = Hermes profile terpisah via `hermes profile create <name>`.

Setiap profile **WAJIB** punya full isolation:

- `HERMES_HOME` directory sendiri (`~/.hermes/profiles/<name>/`)
- `config.yaml` sendiri (LLM provider via 9router, model per role)
- API keys sendiri
- `SOUL.md` sendiri (specialized identity & decision authority)
- `MEMORY.md` & `USER.md` sendiri (no cross-contamination)
- Skills database sendiri (specialized accumulation)
- Sessions database sendiri
- Discord gateway sendiri (channel/bot terpisah per agent)
- systemd service sendiri

#### Layer 2 — Subagents (Ephemeral Tasks)

Di dalam setiap profile, gunakan subagent untuk:

- Parallel fan-out (multi-file processing, parallel queries)
- Zero-context-cost delegation
- Short-lived isolated execution

#### Shared Infrastructure (tetap single instance)

- 9router (LLM gateway untuk semua profile)
- Caddy reverse proxy
- VPS resource pool

### 2. Tech Stack — LOCKED

- **WAJIB** leverage existing stack: Hermes + 9router + Discord + Caddy
- **DILARANG** install framework orchestration eksternal (CrewAI / LangGraph / AutoGen)
- Mengikuti pola `scripts/XX-name.sh` (bash, idempotent, logging via `lib.sh`)

---

## Required Deliverables

### A. Initial Profile Roster

Format tabel:

| Profile Name | Role | Suggested LLM (via 9router) | Discord Channel | Trigger Condition |
|--------------|------|-----------------------------|-----------------|--------------------|
| ... | ... | ... | ... | ... |

**Initial roster** (untuk dilengkapi & dievaluasi):

- **orchestrator** — task router, planner, decision maker
- **researcher** — web research, doc lookup, technology scouting
- **executor** — code generation, file ops, command execution
- **reviewer** — code review, QA, suggest improvements

> Rekomendasikan profile tambahan yang krusial untuk multi-discipline software agency, dengan justifikasi: **kenapa harus jadi profile terpisah** (bukan cukup subagent dalam profile existing).

### B. Architecture & System Design

1. **High-level architecture diagram (Mermaid)** — perlihatkan posisi profiles, 9router, Discord gateway per profile, Caddy, systemd, shared filesystem
2. **Subagent lifecycle pattern** dalam profile (spawn → execute → report → terminate/persist)
3. **Inter-profile communication strategy** — rekomendasikan satu dari:
   - Discord channel relay
   - Shared filesystem handoff (input/output dir)
   - MCP server bridge
   - Database queue table

   Sertakan trade-off setiap option.
4. **Failure handling, retry strategy, circuit breaker** per profile
5. **Memory & skill curation strategy** (hindari skill drift jangka panjang)

### C. Discord Integration (Hybrid Visibility)

- **Channel structure**: per agent? per project? per task? — rekomendasikan
- **Visibility rules**: kapan agent-to-agent comms visible ke user, kapan internal saja
- **Command pattern** (slash commands? mentions? natural language?)
- **Output format** (threaded replies, embeds, status updates)
- **Human-in-the-loop checkpoint** pattern

### D. Per-Profile Configuration Templates

Untuk **SETIAP** profile, generate:

1. **`SOUL.md`** — identity, purpose, decision authority, tool permissions (allowlist), communication protocol, skill scope
2. **`config.yaml`** — LLM provider (via 9router endpoint), model selection per task type, memory provider, gateway config
3. **`.env` template** — env vars khusus profile (API keys, Discord bot token / channel ID)
4. **Skill seed list** — initial skills yang harus pre-installed
5. **systemd service file** — pola: `hermes-<profile>-gateway.service`

### E. Setup Scripts (mengikuti pola `scripts/XX-name.sh`)

- `41-setup-hermes-profiles.sh` — bootstrap semua profile (idempotent, pakai `hermes profile create`)
- `42-seed-profile-souls.sh` — copy `SOUL.md` template ke masing-masing profile
- `43-link-discord-channels.sh` — provision/map Discord channel & bot token per profile
- `55-setup-systemd-per-profile.sh` — generate systemd service per profile (dynamic)
- Update `60-setup-caddy.sh` jika butuh endpoint baru
- Update `90-doctor.sh` untuk health check per profile

### F. Cost Strategy via 9router

Sertakan recommended model routing per profile:

- **Orchestrator** → high-reasoning (premium OK, strategic decisions)
- **Researcher** → web-search capable + balanced cost
- **Executor** → coding-specialized (volume tinggi, cost-optimized)
- **Reviewer** → high-reasoning (catch subtle issues)
- **Profile lain** → justifikasi pilihan model

Format:

| Profile | Primary Model | Fallback Chain | Cost Tier | Reasoning |
|---------|---------------|----------------|-----------|-----------|
| ... | ... | ... | ... | ... |

### G. Implementation Roadmap (Phased)

- **Phase 1 (MVP)** — orchestrator + researcher + executor profiles, Discord visibility on, basic handoff
- **Phase 2 (Expansion)** — add reviewer, QA, additional profiles, skill curation
- **Phase 3 (Hardening)** — observability, cost monitoring, failure recovery, scale testing

### H. Documentation (semua sebagai file `.md` terpisah, agent-agnostic)

1. **`AGENTS.md`** — master context (project overview, architecture, tech stack, key paths, common commands, conventions). Compatible untuk Claude Code, Codex, Gemini, Kiro, dll.
2. **`CLAUDE.md`** — mirror/copy `AGENTS.md` untuk Claude Code auto-detect
3. **`ARCHITECTURE.md`** — system design + Mermaid diagrams
4. **`AGENT_REGISTRY.md`** — daftar semua profile + role + capability + Discord channel mapping
5. **`DISCORD_PLAYBOOK.md`** — cara interact dengan agency via Discord (commands, channel guide, escalation)
6. **`PROJECT_RULES.md`** — coding standards, naming, commit convention
7. **`WORKFLOW.md`** — git flow, PR process, profile-onboarding workflow
8. **`INDEX.md`** — module/package map (high-level only, hindari over-detailing)

### I. Reusable Prompt Templates (output as `.md`)

1. **`prompt-implementation.md`** — template untuk minta agent implementasikan feature baru (input: feature spec → output: code + test)
2. **`prompt-execution.md`** — template untuk minta agent run operational task (test, build, deploy)

---

## Research Mandatory

Lakukan **SEBELUM** generate output. Web search untuk:

- Hermes Agent **profiles feature** (v0.6.0+) — best practices, `HERMES_HOME` structure, gateway-per-profile
- Hermes **subagents pattern** within a profile
- Hermes **`SOUL.md` authoring** untuk specialized roles
- Hermes **Messaging Gateway** for Discord (multi-profile, channel routing)
- **9router** model routing & fallback config per agent
- **Production multi-agent patterns** 2025–2026 (handoff, memory isolation, failure recovery)
- **Inter-profile communication patterns** (filesystem, queue, MCP bridge)

---

## Constraints (HARD RULES)

- Production-ready, not toy code
- **WAJIB** leverage existing stack — **DILARANG** install framework eksternal
- Mengikuti pola `scripts/XX-name.sh` (bash, idempotent, logging)
- VPS-friendly (spawn-on-demand preferred, not always-on for all profiles)
- Cost-aware (9router fallback per profile)
- Agent-agnostic documentation (`AGENTS.md` universal)

---

## Output Format

- Markdown per deliverable file
- Mermaid diagrams untuk arsitektur & flow
- Tabel untuk komparasi, registry, model routing
- Setup scripts mengikuti pola existing (bash, idempotent, `lib.sh`)
- File structure recommendation untuk new files

---

## Clarification Required (BEFORE start working)

Tolong konfirmasi dulu sebelum mulai:

1. **VPS spec** — RAM/CPU/storage available untuk concurrent profiles? (target 3–5 profile aktif simultan)
2. **Budget per task** — limit token cost via 9router? batas harian?
3. **Persistence retention** — history per task disimpan berapa lama?
4. **Autonomy ceiling** — action apa yang **TIDAK BOLEH** autonomous? (e.g., git push to main, deploy production, delete files, spend > X tokens)
5. **Discord workspace** — greenfield atau ada existing channel structure yang harus diikuti?
6. **Skill sharing** — profile boleh saling pakai skill via shared directory, atau full isolation?
7. **External integrations** — ada 3rd party yang sudah ter-setup? (GitHub, Linear, Notion, dll)
8. **LLM provider preference per profile** — ada constraint khusus? (e.g., executor harus pakai Claude, researcher boleh pakai yang lebih murah)
9. **Phase 1 MVP scope** — agent mana yang priority untuk dibangun pertama kali?

---

## ✅ Pre-send Checklist

- [ ] Sudah baca prompt dari atas ke bawah, semua decision sesuai intent
- [ ] Daftar profile di "Initial Profile Roster" sudah complete sesuai kebutuhan
- [ ] 9 pertanyaan klarifikasi di bagian akhir sudah disiapkan jawabannya (atau biarkan agent yang tanya)
- [ ] Tech stack constraint sudah final (Hermes + 9router + Discord + Caddy)
- [ ] Roadmap Phase 1 scope sesuai prioritas bisnis

---

> **Catatan untuk pengirim**: Karena scope cukup besar, agent kemungkinan akan minta klarifikasi dulu sebelum mulai work — itu **sesuai desain**. Jangan paksa langsung eksekusi tanpa konfirmasi 9 pertanyaan di atas.

---

*Generated via prompting-enhancement session — v2 final*