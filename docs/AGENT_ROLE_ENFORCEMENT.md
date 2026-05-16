# Agent Role Enforcement Runbook

This runbook addresses behavior drift where agents learned the wrong responsibilities before `morph-task` existed.

## Enforcement Layers

1. **Prompt layer**: profile `SOUL.md` says what the agent should do.
2. **Task wrapper layer**: `morph-task` enforces who can create, assign, claim, result, close, audit, and health-check tasks.
3. **Discord policy layer**: worker profiles reject direct human tasks and worker-to-worker messages.
4. **Runtime DB layer**: SQLite records assignments, claims, completions, and policy violations.
5. **Shell/PATH layer**: `/usr/local/bin/bd` is a guard; real Beads lives at `/opt/morph-agency/bin/bd`.

## Recommended Reset

Use selective reset instead of rebuilding the VPS:

```bash
sudo ./scripts/49-reset-agent-memory.sh
```

The script backs up profile/runtime state, removes learned memory/session/cache, clears queue/handoff state, and reinstalls SOUL/routing/wrapper policy.

Defaults:

```text
PROFILES=orchestrator,researcher,executor
RESET_QUEUE=true
RESET_HANDOFF=true
RESET_POLICY_AUDIT=false
```

Set `RESET_POLICY_AUDIT=true` only if old denied-action history is no longer useful.

## Tool Permission Target Model

Hermes tool permissions should eventually be narrowed to this model:

| Profile | Allowed | Denied |
|---|---|---|
| `orchestrator` | `morph-task create/assign/ready/show/close/doctor/audit/health` | direct code execution, direct research, `bd`, worker result submission |
| `researcher` | read-only shell, web/docs lookup, `morph-task claim/progress/result` for `researcher` | file writes outside handoff, build/test/deploy, assign/create/close, `bd` |
| `executor` | workspace file ops, build/test, `morph-task claim/progress/result` for `executor` | assign/create/close, open-ended research delegation, `bd` |

Until Hermes exposes hard per-command allowlists in config, enforce this through `morph-task`, direct `bd` guard, Discord policy, SOUL rules, and reset hygiene.

## Discord Rules

- Humans send tasks only to `#orchestrator`.
- Worker channels are progress/output logs, not task intake surfaces.
- Workers accept only orchestrator-originated messages with valid task IDs.
- Worker-to-worker task delegation is denied.

## Drift Monitoring

Run periodically:

```bash
morph-task audit --limit 20
morph-task health
```

Warning signals:

- Repeated denied `assign` by `executor` or `researcher`.
- Worker attempts to close tasks.
- Orchestrator attempts to claim/result worker tasks.
- Pending/claimed assignments accumulating without result.

## Beads ↔ SQLite Drift

Known drift cases:

- Bead exists but runtime assignment insert failed.
- Runtime assignment exists but Bead was closed manually.
- Claim succeeded in SQLite but Beads update failed.
- Result succeeded in SQLite but Beads update failed.

Next planned mitigation: `morph-task reconcile` to compare Beads task state with `runtime_assignments` and repair or report drift.
