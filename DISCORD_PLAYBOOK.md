# Discord Playbook

How to interact with the Morph AI Software Agency via Discord.

For server/channel/bot setup instructions, see `docs/DISCORD_SETUP.md`.

---

## Channel Structure

| Channel | Purpose | Who writes | Who reads |
|---------|---------|------------|-----------|
| `#orchestrator` | Primary user interface. Send tasks here. | User, Orchestrator | All |
| `#researcher` | Research agent output and findings. | Researcher | User (read-only), Orchestrator |
| `#executor` | Execution logs, code output, build results. | Executor | User (read-only), Orchestrator |
| `#status` | Automated status updates from all agents. | All agents | User (read-only) |
| `#escalation` | Human-in-the-loop checkpoints requiring approval. | Orchestrator | User (action required) |

---

## Visibility Rules

| Communication Path | Visibility | Location |
|--------------------|------------|----------|
| User to Orchestrator | Always visible | `#orchestrator` main channel |
| Orchestrator to Worker | Visible | Respective agent channel (`#researcher`, `#executor`) |
| Agent to Agent (internal) | Visible but threaded | Threads within agent channels |
| Results and summaries | Posted back to user | `#orchestrator` (reply to original message) |
| Status broadcasts | Automated | `#status` |
| Escalation requests | Requires user action | `#escalation` |

---

## Command Patterns

### Primary: Natural Language via Mention

```
@Orchestrator build a REST API for user authentication with JWT
```

The orchestrator decomposes the task, delegates to specialists, and reports the synthesized result back in `#orchestrator`.

### Direct Agent Commands (Advanced Users)

```
@Researcher research the best Go HTTP frameworks for production use in 2026
```

```
@Executor run tests in /home/hermes/workspace/api-server
```

Direct commands bypass the orchestrator. Use only when you know which agent should handle the task.

### Task Management

```
@Orchestrator status                    — show active tasks
@Orchestrator cancel <task-id>          — cancel a running task
@Orchestrator retry <task-id>           — retry a failed task
@Orchestrator priority high <task-id>   — change task priority
```

---

## Human-in-the-Loop Checkpoints

The following actions require explicit user approval in `#escalation`:

| Action | Trigger | User Response |
|--------|---------|---------------|
| Deploy to production | Any production deployment command | Reply with `approve` or `reject` |
| Delete files | File deletion outside `/tmp` and handoff dirs | Reply with `approve` or `reject` |
| Push to main/master | Git push to protected branches | Reply with `approve` or `reject` |
| Cost > $5 per task | Single task estimated to exceed $5 via 9Router | Notification only (auto-proceeds unless rejected within 60s) |
| System package install | `sudo apt install` or global package installs | Reply with `approve` or `reject` |

### Escalation Message Format

```
--- APPROVAL REQUIRED ---
Action: Deploy to production
Profile: executor
Task ID: a1b2c3d4
Details: Push tag v1.2.0 and deploy to production server
Risk: HIGH

Reply with: approve / reject
Timeout: 30 minutes (auto-reject if no response)
---
```

---

## Output Formats

### Threaded Replies (Multi-Step Tasks)

Multi-step tasks use threaded replies to keep the main channel clean:

```
#orchestrator
  User: @Orchestrator build auth API with JWT
  Orchestrator: Starting task. Delegating to researcher and executor.
    Thread:
      [1/4] Researching JWT libraries... (delegated to researcher)
      [2/4] Research complete. 3 options evaluated.
      [3/4] Implementing with go-jwt v5... (delegated to executor)
      [4/4] Implementation complete. Tests passing.
  Orchestrator: Task complete. Summary: [final result]
```

### Code Output

Code output uses fenced code blocks with language tags:

````
```go
func AuthMiddleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        // ...
    })
}
```
````

### Task Progress Embeds

```
--- TASK STATUS ---
ID: a1b2c3d4
Status: processing
Profile: executor
Progress: 3/5 subtasks complete
Duration: 2m 14s
---
```

### Error Alerts

```
--- ERROR [HIGH] ---
Task ID: a1b2c3d4
Profile: executor
Error: Build failed — missing dependency "github.com/golang-jwt/jwt/v5"
Attempted fixes: 1/3
Next: Retrying with dependency resolution
---
```

Severity levels: `CRITICAL`, `HIGH`, `MEDIUM`, `LOW`.

---

## Best Practices

1. **One task per message.** The orchestrator handles decomposition. Send a single request and let it break it down.
2. **Be specific about acceptance criteria.** "Build an API" is valid. "Build a REST API with JWT auth, PostgreSQL storage, and 80% test coverage" is better.
3. **Check `#status` for progress.** Avoid polling the orchestrator with "is it done yet?"
4. **Use `#escalation` promptly.** Unanswered escalation requests auto-reject after 30 minutes.
5. **Direct commands for simple tasks.** If you just need a quick research lookup, talk directly to `@Researcher` instead of routing through the orchestrator.
