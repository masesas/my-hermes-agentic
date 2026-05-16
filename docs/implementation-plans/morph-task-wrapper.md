# Morph Task Wrapper Implementation Plan

## Objective

Build `morph-task`, a role-enforcing CLI wrapper that lets Morph agents use Beads (`bd`) for task graph management while keeping Morph-specific runtime coordination in SQLite.

This plan is intentionally not executed yet. Implementation should happen step by step after review.

## Target Architecture

```text
Agent profile
  -> morph-task CLI
  -> role-policy.yaml permission check
  -> Beads (`bd`) for task graph operations
  -> SQLite runtime bus for locks, messages, health, Discord mapping, audit
```

## Non-Goals

- Do not replace Hermes.
- Do not let workers call `bd` directly.
- Do not remove the existing SQLite queue immediately.
- Do not grant researcher/executor delegation permissions.
- Do not implement autonomous behavior solely through prompts.

## Phase 0 — Skeleton

Status: scaffolded only.

Deliverables:

- `apps/morph-task/go.mod`
- `apps/morph-task/cmd/morph-task/main.go`
- placeholder internal packages under `apps/morph-task/internal/`
- `config/agency/role-policy.yaml`
- this implementation plan

Acceptance criteria:

- `cd apps/morph-task && go test ./...` passes with placeholder packages.
- `cd apps/morph-task && go run ./cmd/morph-task --version` prints a dev version.
- Any planned command exits with a clear “not implemented yet” message.

## Phase 1 — Policy Engine

Status: policy engine, YAML loading, CLI command authorization wiring, and role-boundary unit tests implemented. Beads and SQLite integration are still pending.

Deliverables:

- Parse `config/agency/role-policy.yaml`.
- Resolve active profile from `MORPH_PROFILE`.
- Add command authorization checks:
  - `create`, `assign`, `close`: orchestrator only.
  - `claim`: worker only for own target profile.
  - `result`: worker only for own target profile.
  - `ready`, `show`: profile-scoped reads unless orchestrator.
- Add table-driven unit tests for allow/deny decisions.

Acceptance criteria:

- Unknown profile is denied.
- Researcher cannot create/assign execution tasks.
- Executor cannot create/assign research tasks.
- Orchestrator can create/assign but cannot claim worker tasks.

## Phase 2 — Beads Client

Status: typed Beads client and fake-runner unit tests implemented. CLI backend wiring is intentionally still pending.

Deliverables:

- Typed subprocess wrapper around `bd`.
- Always request JSON output where supported.
- Add timeout and structured error handling.
- Commands:
  - `bd create`
  - `bd show`
  - `bd ready`
  - `bd update`
  - `bd close`

Acceptance criteria:

- Wrapper never shells through string concatenation.
- `bd` path comes from policy/config.
- Failures include command, exit code, stderr summary, and profile context.

## Phase 3 — SQLite Runtime Bus

Status: runtime migrations, assignment creation, atomic claim logic, and runtime unit tests implemented. CLI integration is still pending.

Deliverables:

- Runtime migrations for:
  - `runtime_assignments`
  - `runtime_locks`
  - `agent_messages`
  - `profile_health`
  - `policy_violations`
- Claim locking with atomic transaction.
- Mapping from Beads task ID to target profile.

Acceptance criteria:

- Two workers cannot claim the same task concurrently.
- Worker cannot claim task assigned to another profile.
- Policy violations are auditable.

## Phase 4 — Command Implementation

Status: all planned core commands plus `doctor` are wired through policy, Beads client interfaces, and SQLite runtime interfaces with fake-backed tests. Install integration is pending.

Deliverables:

- `morph-task create --target <profile> --kind <kind> --title <title>`
- `morph-task assign <id> --target <profile>`
- `morph-task ready`
- `morph-task claim <id>`
- `morph-task progress <id> --message <text>`
- `morph-task result <id> --status <status> --summary <text>`
- `morph-task close <id>`
- `morph-task doctor`

Acceptance criteria:

- Every mutating command checks policy first.
- Denied mutating commands write policy violation audit events.
- Command output is stable and can be consumed by agents.

## Phase 5 — Install and Integration

Status: install script, role policy deployment, profile env wiring, and SOUL task-operation rules implemented. Beads binary installation itself remains external/pending.

Deliverables:

- `scripts/47-install-morph-task.sh`
- Install binary to `/usr/local/bin/morph-task` or `/opt/morph-agency/bin/morph-task`.
- Install `role-policy.yaml` to `/var/lib/morph-agency/config/role-policy.yaml`.
- Add profile env vars:
  - `MORPH_PROFILE`
  - `MORPH_ROLE_POLICY`
  - `MORPH_RUNTIME_DB`
- Update profile `SOUL.md` files to require `morph-task` for task operations.

Acceptance criteria:

- `morph-task doctor` passes on VPS.
- Each Hermes profile resolves its own `MORPH_PROFILE`.
- Worker profiles are told never to call `bd` directly.

## Phase 6 — Hardening

Status: Beads install script, direct `bd` guard, role-boundary regression tests, audit/health commands, release build helper, policy violation auditing, and rollback documentation implemented.

Deliverables:

- Move `bd` out of generic worker PATH where practical.
- Add policy violation metrics/reporting.
- Add regression tests for role boundaries.
- Add rollback procedure.

Acceptance criteria:

- Researcher cannot assign or execute through wrapper.
- Executor cannot assign or perform research delegation through wrapper.
- Orchestrator cannot accidentally bypass worker execution path through wrapper.

## Open Decisions

- Exact Beads install path on VPS.
- Whether `bd close` should be orchestrator-only or allowed for assigned worker after result submission.
- Whether existing `tasks` table remains indefinitely or is gradually replaced by Beads IDs.
- Whether to enforce direct `bd` blocking via PATH, shell profile, filesystem permissions, or Hermes tool policy.
