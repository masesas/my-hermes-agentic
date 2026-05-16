# Beads ↔ SQLite Reconcile Plan

`morph-task` currently uses Beads as the task graph and SQLite as runtime enforcement state. This creates a controlled dual-state system that needs reconciliation before production-scale autonomy.

## Implemented Command

```bash
morph-task --project <project-id> reconcile
```

Current implementation is read-only. It compares Beads ready task IDs with SQLite runtime assignments and emits a JSON report.

## Read-Only Mode

Default mode should report:

- Runtime assignments with missing Beads records.
- Beads tasks labeled `target:<profile>` with no runtime assignment.
- Claimed runtime assignments whose Beads status is not in progress.
- Completed runtime assignments whose Beads task is still open.
- Policy violations per profile.

## Future Fix Mode

`--fix` should only perform safe/idempotent repairs:

- Create missing runtime assignment for Beads task with target label.
- Re-apply Beads status from runtime assignment status.
- Mark orphaned runtime assignment as `blocked` rather than deleting it.

## Safety

- Never delete Beads tasks automatically.
- Never close tasks automatically without orchestrator confirmation.
- Always emit JSON summary for audit.
