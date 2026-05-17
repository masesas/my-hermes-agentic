# Morph Task Command Cheat Sheet

Quick reference untuk orchestrator, researcher, dan executor. Copy-paste ready, semua command udah include `--project` explicit.

---

## Orchestrator Commands

### Create Task (Research)
```bash
export MORPH_PROFILE=orchestrator
morph-task --project <project-name> create \
  --target researcher \
  --kind research \
  --title "Research: Docker health check best practices"
```

### Create Task (Implementation)
```bash
export MORPH_PROFILE=orchestrator
morph-task --project <project-name> create \
  --target executor \
  --kind execution \
  --title "Implement: Payment endpoint"
```

### Assign Task
```bash
morph-task --project <project-name> assign \
  --target researcher \
  <bead-id>
```

### Check Ready Tasks
```bash
morph-task --project <project-name> ready
```

### Show Task Detail
```bash
morph-task --project <project-name> show <bead-id>
```

### Close Task
```bash
morph-task --project <project-name> close <bead-id> \
  --reason "Task completed successfully"
```

### Health Check
```bash
morph-task --project <project-name> health
```

### Audit Violations
```bash
morph-task --project <project-name> audit --limit 20
```

### Reconcile (Beads vs Runtime)
```bash
morph-task --project <project-name> reconcile
```

### List Projects
```bash
morph-task projects
```

### Show Project Detail
```bash
morph-task projects <project-name>
```

---

## Researcher Commands

### Claim Task
```bash
export MORPH_PROFILE=researcher
morph-task --project <project-name> claim \
  --target researcher \
  <bead-id>
```

### Report Progress
```bash
morph-task --project <project-name> progress \
  --target researcher \
  --message "Found 3 relevant API docs" \
  <bead-id>
```

### Submit Result
```bash
morph-task --project <project-name> result \
  --target researcher \
  --status completed \
  --message "Research complete: 3 best practices documented" \
  <bead-id>
```

### Check Ready Tasks (for me)
```bash
morph-task --project <project-name> ready
```

---

## Executor Commands

### Claim Task
```bash
export MORPH_PROFILE=executor
morph-task --project <project-name> claim \
  --target executor \
  <bead-id>
```

### Report Progress
```bash
morph-task --project <project-name> progress \
  --target executor \
  --message "Tests passing, creating PR" \
  <bead-id>
```

### Submit Result
```bash
morph-task --project <project-name> result \
  --target executor \
  --status completed \
  --message "Feature merged: PR #42" \
  <bead-id>
```

### Check Ready Tasks (for me)
```bash
morph-task --project <project-name> ready
```

---

## Common Pitfalls & Fixes

| Error | Cause | Fix |
|-------|-------|-----|
| `claim requires --target` | Missing `--target` flag | Always include `--target <profile>` |
| `create requires --kind` | Missing `--kind` flag | Use `--kind research` or `--kind execution` |
| `create requires --title` | Missing `--title` flag | Always include `--title "..."` |
| `project not found` | Project not in policy | Run `morph-task projects` to list valid projects |
| `denied: profile not allowed` | Profile not in project ACL | Check `role-policy.yaml` for allowed_profiles |

---

## Project Context Rules

1. **Always explicit:** Use `--project <name>` in every command
2. **Thread naming:** Discord threads should follow `proj/<project>/<topic>`
3. **No silent defaults:** Never rely on `MORPH_DEFAULT_PROJECT` for client work
4. **Verify first:** Run `morph-task projects` to confirm project exists

---

## Environment Setup

### Orchestrator
```bash
export MORPH_PROFILE=orchestrator
export MORPH_PROJECT=<project-name>  # optional, but --project flag is safer
```

### Researcher
```bash
export MORPH_PROFILE=researcher
export MORPH_PROJECT=<project-name>
```

### Executor
```bash
export MORPH_PROFILE=executor
export MORPH_PROJECT=<project-name>
```

---

## Quick E2E Flow Example

```bash
# 1. Orchestrator creates research task
export MORPH_PROFILE=orchestrator
RESEARCH_ID=$(morph-task --project client-a create \
  --target researcher \
  --kind research \
  --title "Research: Payment gateway options" | grep -oP 'bead=\K[^ ]+')

# 2. Orchestrator assigns to researcher
morph-task --project client-a assign --target researcher $RESEARCH_ID

# 3. Researcher claims
export MORPH_PROFILE=researcher
morph-task --project client-a claim --target researcher $RESEARCH_ID

# 4. Researcher submits result
morph-task --project client-a result \
  --target researcher \
  --status completed \
  --message "Found 3 viable options: Stripe, Midtrans, Xendit" \
  $RESEARCH_ID

# 5. Orchestrator creates implementation task
export MORPH_PROFILE=orchestrator
IMPL_ID=$(morph-task --project client-a create \
  --target executor \
  --kind execution \
  --title "Implement: Stripe payment integration" | grep -oP 'bead=\K[^ ]+')

# 6. Orchestrator assigns to executor
morph-task --project client-a assign --target executor $IMPL_ID

# 7. Executor claims
export MORPH_PROFILE=executor
morph-task --project client-a claim --target executor $IMPL_ID

# 8. Executor submits result
morph-task --project client-a result \
  --target executor \
  --status completed \
  --message "Feature merged: PR #123" \
  $IMPL_ID

# 9. Orchestrator closes both tasks
export MORPH_PROFILE=orchestrator
morph-task --project client-a close $RESEARCH_ID --reason "Research delivered"
morph-task --project client-a close $IMPL_ID --reason "Implementation delivered"
```

---

## Debugging Commands

### Check if morph-task is working
```bash
morph-task --version
morph-task doctor
```

### Verify project exists
```bash
morph-task projects | jq '.[] | select(.name=="<project-name>")'
```

### Check runtime health
```bash
morph-task --project <project-name> health
```

### Find recent violations
```bash
morph-task --project <project-name> audit --limit 10
```

### Check Beads vs runtime drift
```bash
morph-task --project <project-name> reconcile
```

---

## Notes

- All commands assume `morph-task` binary is in `$PATH` (installed at `/opt/morph-agency/bin/morph-task`)
- `MORPH_ROLE_POLICY` env var should point to `/var/lib/morph-agency/config/role-policy.yaml`
- Beads workspace per project: `/home/hermes/workspace/<project>/.beads`
- Handoff directory per project: `/var/lib/morph-agency/handoff/<project>`
