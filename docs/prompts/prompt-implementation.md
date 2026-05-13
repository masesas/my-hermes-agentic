# Implementation Prompt Template

## Usage

Send this to the **orchestrator** agent (via Discord `#orchestrator` or directly to the executor) when you need a new feature implemented. The orchestrator will decompose the task if needed, delegate research to the researcher profile, and hand off implementation to the executor profile.

Copy the template below, fill in the bracketed fields, and delete any sections that do not apply.

---

## Template

```
### Context
- **Project**: [project name or repo path, e.g. morph-ai-agent]
- **Module**: [affected module/area, e.g. auth, task-queue, discord-gateway]
- **Branch**: [target branch name, e.g. feat/user-auth]
- **Working directory**: [path, e.g. /home/hermes/workspace/morph-ai-agent]

### Feature Specification

[Describe the feature in detail. Include:]
- What it should do (functional behavior)
- Who or what triggers it (user action, cron, event, API call)
- Expected inputs and outputs
- Acceptance criteria (when is this "done"?)

### Technical Requirements

- [ ] [Requirement 1, e.g. "Use bcrypt for password hashing with cost factor 12"]
- [ ] [Requirement 2, e.g. "Store sessions in SQLite, not memory"]
- [ ] [Requirement 3, e.g. "Expose REST endpoint POST /api/auth/login"]

### Constraints

- [Performance: e.g. "Response time < 200ms at p95"]
- [Compatibility: e.g. "Must work on Node 20 LTS"]
- [Dependencies: e.g. "No new runtime dependencies beyond what is in package.json"]
- [Security: e.g. "All user input must be validated with zod schemas"]

### Research Needed (optional)

[If the executor needs information before starting, describe what the researcher
should look up first. The orchestrator will route this automatically.]

- [e.g. "Compare argon2 vs bcrypt for password hashing — performance on 2 vCPU"]
- [e.g. "Find the current best practice for JWT refresh token rotation"]

### Expected Output

- [ ] Implementation code in the specified module
- [ ] Unit tests (80%+ coverage on new code)
- [ ] Integration test (if the feature touches the database or external APIs)
- [ ] Updated documentation (if the feature adds a new endpoint, config, or CLI command)
- [ ] Conventional commit(s) on the specified branch

### Validation Criteria

- [ ] All existing tests still pass (no regressions)
- [ ] New tests pass
- [ ] No lint errors
- [ ] Build succeeds
- [ ] Feature works as specified in the acceptance criteria
- [ ] No hardcoded secrets or credentials
```

---

## Example: Filled-In Template

```
### Context
- **Project**: morph-ai-agent
- **Module**: task-queue
- **Branch**: feat/task-priority
- **Working directory**: /home/hermes/workspace/morph-ai-agent

### Feature Specification

Add a priority field to the SQLite task queue so the orchestrator can mark
tasks as urgent. Tasks with higher priority should be claimed before lower
priority tasks, regardless of creation time.

Acceptance criteria:
1. Tasks accept a `priority` integer (0 = normal, 1 = high, 2 = urgent).
2. The claim query orders by priority DESC, then created_at ASC.
3. The orchestrator can set priority when enqueuing via `enqueue_task()`.
4. Default priority is 0 if not specified.

### Technical Requirements

- [ ] Add `priority INTEGER NOT NULL DEFAULT 0` column to the `tasks` table
- [ ] Update the atomic claim query to order by `priority DESC, created_at ASC`
- [ ] Update `enqueue_task()` to accept an optional `priority` parameter
- [ ] Add migration script following existing `scripts/XX-name.sh` pattern

### Constraints

- No new dependencies. Use the existing `better-sqlite3` driver.
- Migration must be idempotent (safe to run multiple times).
- Backward compatible: existing tasks without priority default to 0.

### Research Needed (optional)

None. The existing schema and claim pattern are documented in ARCHITECTURE.md.

### Expected Output

- [ ] Migration script: `scripts/45-migrate-task-priority.sh`
- [ ] Updated queue module with priority support
- [ ] Unit tests covering: enqueue with priority, claim ordering, default value
- [ ] Integration test: enqueue 3 tasks with mixed priority, verify claim order
- [ ] Commit on `feat/task-priority` branch

### Validation Criteria

- [ ] All existing tests still pass
- [ ] New tests pass with 80%+ coverage on changed files
- [ ] `scripts/45-migrate-task-priority.sh` is idempotent (run twice, no error)
- [ ] Build succeeds
- [ ] Manual verification: enqueue urgent + normal tasks, claim returns urgent first
- [ ] No hardcoded values (priority levels defined as constants)
```

---

## Tips

- **Be specific about acceptance criteria.** Vague specs produce vague implementations. If you know what "done" looks like, write it down.
- **Include constraints up front.** Telling the executor "no new dependencies" after implementation wastes a full cycle.
- **Use the research section** when you are unsure about the best approach. The orchestrator will route a research task to the researcher before handing off to the executor.
- **One feature per prompt.** If you need multiple features, send separate prompts. The orchestrator can parallelize them.
- **Reference existing patterns.** Point to files in the codebase that follow the pattern you want replicated (e.g., "follow the same structure as `scripts/50-setup-systemd.sh`").
