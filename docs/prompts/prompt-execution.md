# Execution Prompt Template

## Usage

Send this to the **orchestrator** agent (via Discord `#orchestrator`) or directly to the **executor** when you need an operational task performed: running tests, building, deploying, health checks, migrations, backups, or any command-based operation.

Copy the template below, fill in the bracketed fields, and delete any sections that do not apply.

---

## Template

```
### Task Type

[test | build | deploy | health-check | migration | backup | cleanup | restart]

### Environment

- **Target**: [e.g. VPS production, local dev, staging]
- **Working directory**: [e.g. /home/hermes/workspace/morph-ai-agent]
- **Branch** (if relevant): [e.g. main, feat/task-priority]

### Command / Action

[Specific command or sequence of actions to execute. Be explicit.]

### Pre-conditions

- [ ] [What must be true before execution, e.g. "All tests passing on current branch"]
- [ ] [e.g. "9router service is running"]
- [ ] [e.g. "Database backup completed within last 24 hours"]

### Expected Outcome

[What success looks like. Be specific enough that the executor can verify.]

### Rollback Plan

[What to do if the task fails or produces unexpected results.]
- Step 1: [e.g. "Restore database from backup at /var/lib/morph-agency/backups/"]
- Step 2: [e.g. "Restart the service: sudo systemctl restart hermes-orchestrator-gateway"]
- Step 3: [e.g. "Notify user in #orchestrator with the error output"]

### Reporting

Return the following in the task result:
- [ ] Full command output (stdout + stderr)
- [ ] Exit code
- [ ] Duration
- [ ] Artifacts produced (file paths, URLs, or identifiers)
- [ ] Pass/fail summary
```

---

## Example: Run Test Suite

```
### Task Type

test

### Environment

- **Target**: VPS production
- **Working directory**: /home/hermes/workspace/morph-ai-agent
- **Branch**: feat/task-priority

### Command / Action

Run the full test suite and report results with coverage:

1. `npm run typecheck`
2. `npm run test:unit -- --reporter=verbose`
3. `npm run test:integration` (if available)

### Pre-conditions

- [ ] Branch `feat/task-priority` is checked out
- [ ] Dependencies installed (`node_modules` present)
- [ ] No uncommitted changes in the working directory

### Expected Outcome

- Typecheck exits with 0 errors.
- All unit tests pass.
- Integration tests pass (or are skipped with a note if not configured).
- Coverage report is generated showing 80%+ on changed files.

### Rollback Plan

No rollback needed. Tests are read-only and do not modify state.

### Reporting

- [ ] Full test output with pass/fail per test file
- [ ] Exit code for each command
- [ ] Duration per step
- [ ] Coverage percentage for changed files
- [ ] Summary: total passed / failed / skipped
```

---

## Example: Health Check

```
### Task Type

health-check

### Environment

- **Target**: VPS production
- **Working directory**: /home/hermes/workspace/morph-ai-agent
- **Branch**: N/A (checking running services)

### Command / Action

Run the full system health check:

1. `bash scripts/90-doctor.sh`
2. `systemctl status hermes-orchestrator-gateway.service`
3. `systemctl status 9router.service`
4. `curl -s http://localhost:4000/health` (9router health endpoint)
5. `df -h /var/lib/morph-agency/` (disk usage)
6. `free -h` (memory usage)

### Pre-conditions

- [ ] SSH access to VPS is available
- [ ] systemd services are expected to be running

### Expected Outcome

- `90-doctor.sh` exits 0 with all checks green.
- Both systemd services show `active (running)`.
- 9router health endpoint returns 200.
- Disk usage below 85%.
- Memory usage below 80%.

### Rollback Plan

Not applicable. Health checks are read-only. If issues are found:
- Report findings to user in #orchestrator.
- Suggest remediation steps but do not act without approval.

### Reporting

- [ ] Full output of each command
- [ ] Service status (active/inactive/failed) for each systemd unit
- [ ] HTTP status code from health endpoint
- [ ] Disk usage percentage
- [ ] Memory usage (used / total)
- [ ] Overall health: HEALTHY | DEGRADED | UNHEALTHY
```

---

## Example: Database Migration

```
### Task Type

migration

### Environment

- **Target**: VPS production
- **Working directory**: /home/hermes/workspace/morph-ai-agent
- **Branch**: feat/task-priority

### Command / Action

Run the task-priority migration:

1. Back up the current database:
   `cp /var/lib/morph-agency/queue.db /var/lib/morph-agency/backups/queue-$(date +%Y%m%d-%H%M%S).db`
2. Run the migration:
   `bash scripts/45-migrate-task-priority.sh`
3. Verify the schema change:
   `sqlite3 /var/lib/morph-agency/queue.db ".schema tasks"`

### Pre-conditions

- [ ] Database backup directory exists: `/var/lib/morph-agency/backups/`
- [ ] No active tasks in `processing` status (check with:
      `sqlite3 /var/lib/morph-agency/queue.db "SELECT count(*) FROM tasks WHERE status='processing'"`)
- [ ] Migration script exists and is executable

### Expected Outcome

- Backup file created in `/var/lib/morph-agency/backups/`.
- Migration script exits 0.
- `tasks` table schema includes `priority INTEGER NOT NULL DEFAULT 0`.
- Existing rows have `priority = 0`.
- Running the migration a second time produces no errors (idempotent).

### Rollback Plan

1. Stop the orchestrator: `sudo systemctl stop hermes-orchestrator-gateway`
2. Restore the backup: `cp /var/lib/morph-agency/backups/queue-<timestamp>.db /var/lib/morph-agency/queue.db`
3. Restart the orchestrator: `sudo systemctl start hermes-orchestrator-gateway`
4. Report the rollback to user in #orchestrator.

### Reporting

- [ ] Backup file path and size
- [ ] Migration script output
- [ ] Schema verification output
- [ ] Idempotency verification (second run output)
- [ ] Exit codes for each step
- [ ] Duration
```

---

## Tips

- **Always include a rollback plan** for tasks that modify state (migrations, deployments, config changes). For read-only tasks (tests, health checks), note that rollback is not applicable.
- **Check pre-conditions before executing.** The executor will verify them, but listing them explicitly avoids wasted cycles.
- **One task per prompt.** If you need to run tests, then deploy, then health-check, send three separate prompts or let the orchestrator sequence them.
- **Be explicit about what to report.** The executor will return what you ask for. If you need coverage numbers, say so. If you only need pass/fail, say that.
- **Use the environment section** to prevent mistakes. Specifying the target and working directory eliminates ambiguity about where commands run.
