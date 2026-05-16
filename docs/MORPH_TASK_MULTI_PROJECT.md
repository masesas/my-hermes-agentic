# Morph Task Multi-Project Support

`morph-task` supports project namespaces so a single Morph agency can serve
multiple clients or product lines while keeping their tasks, audit logs, and
Beads workspaces fully isolated.

This document is the operational runbook. The CLI contract is the source of
truth for behavior.

---

## 1. Concept

A project is an isolated namespace with its own:

- Beads workspace (`/home/hermes/workspace/<project>/.beads`)
- Handoff directory (`/var/lib/morph-agency/handoff/<project>`)
- Runtime assignment rows (filtered by `project_id` in `runtime_assignments`)
- Policy violation audit rows (filtered by `project_id` in `policy_violations`)
- Allowed-profile gate (in `role-policy.yaml`)

All projects share a single SQLite runtime DB (`/var/lib/morph-agency/queue.db`)
and a single Beads binary (`/opt/morph-agency/bin/bd`).

---

## 2. Selecting the active project

Every `morph-task` invocation resolves the active project in this order:

1. `--project <name>` flag
2. `MORPH_PROJECT` environment variable
3. `MORPH_DEFAULT_PROJECT` environment variable
4. The literal string `default`

```bash
morph-task --project client-a create --target executor --kind execution --title "Fix login"
MORPH_PROJECT=client-a morph-task ready
morph-task ready                  # uses MORPH_DEFAULT_PROJECT from profile .env
```

The Authorize policy gate denies the request if:

- The project name is not declared in `role-policy.yaml` under `projects:`.
- The active profile is not listed in that project's `allowed_profiles`.

---

## 3. Policy file format

`config/agency/role-policy.yaml` deployed to
`/var/lib/morph-agency/config/role-policy.yaml`:

```yaml
projects:
  default:
    workspace: /home/hermes/workspace/default
    handoff_dir: /var/lib/morph-agency/handoff/default
    allowed_profiles:
      - orchestrator
      - researcher
      - executor

  client-a:
    workspace: /home/hermes/workspace/client-a
    handoff_dir: /var/lib/morph-agency/handoff/client-a
    allowed_profiles:
      - orchestrator
      - researcher
      - executor
```

`allowed_profiles` is the only authoritative ACL. Empty list means "all
configured profiles allowed". Any profile not listed is denied with
`ErrProjectDenied`.

---

## 4. Onboarding a new project

Use the idempotent script. It can be re-run safely.

```bash
sudo /opt/ai-agent/scripts/51-create-project.sh client-a
# or restrict allowed profiles:
sudo /opt/ai-agent/scripts/51-create-project.sh client-a orchestrator,executor
```

The script:

1. Creates `/home/hermes/workspace/client-a` (owned by hermes).
2. Runs `bd init` inside it (if Beads binary is installed).
3. Creates `/var/lib/morph-agency/handoff/client-a`.
4. Appends a `projects.client-a` block to the deployed `role-policy.yaml`
   if missing.
5. Calls `morph-task --project client-a projects client-a` to verify the
   project is accepted by the wrapper.

After onboarding, the project is immediately usable by the orchestrator.

---

## 5. Inspecting projects

```bash
morph-task projects                   # JSON list of all configured projects
morph-task projects client-a          # detail + assignment counts + violation count
morph-task --project client-a health  # per-project health summary
morph-task --project client-a audit   # per-project policy violations
morph-task --project client-a reconcile  # Beads <-> runtime drift report
```

`audit` and `health` are **project-scoped** by design: violations or
assignments from another project are never visible from the wrong project
context. This is enforced at the SQL query level, not just at presentation.

---

## 6. Discord model

The orchestrator parses thread titles to determine the project. Convention:

```text
proj/<project>/<topic>
```

Example: `#orchestrator` channel, thread `proj/client-a/fix-login-bug`.

The orchestrator must:

- Use `<project>` from the thread title for every downstream `morph-task` call.
- Announce the active project once at the start of the conversation.
- Ask the user to specify the project if the thread title does not match the
  pattern. Never silently default to `default` for client work.

Workers MUST reject task hand-offs that do not include an explicit
`--project <name>`.

---

## 7. Periodic reconcile

Per-project drift detection (Beads ready tasks vs runtime assignments) can be
automated via systemd user timers.

```bash
# Install the templates once
install -m 644 systemd/morph-reconcile@.service /home/hermes/.config/systemd/user/
install -m 644 systemd/morph-reconcile@.timer   /home/hermes/.config/systemd/user/

# Enable per project
sudo -iu hermes systemctl --user daemon-reload
sudo -iu hermes systemctl --user enable --now morph-reconcile@default.timer
sudo -iu hermes systemctl --user enable --now morph-reconcile@client-a.timer
```

Reconcile output is captured in journald and never mutates state.

---

## 8. Health & audit isolation guarantees

The following queries are filtered by `project_id` in `apps/morph-task/internal/runtime/store.go`:

- `HealthSummary(ctx, projectID)` — assignment counts and violation counts.
- `ListPolicyViolations(ctx, projectID, limit)` — recent denied actions.
- `ListAssignments(ctx, projectID)` — all assignments for the project.

Regression test: `TestProjectIsolationForHealthAndAudit` in
`apps/morph-task/internal/runtime/store_test.go` exercises the cross-project
leakage scenario and asserts strict isolation.

---

## 9. Migrating an existing single-project deployment

Existing deployments started life as a single `default` project. Migration is
automatic because:

- The SQLite schema declares `project_id TEXT NOT NULL DEFAULT 'default'`,
  so existing rows are already labelled `default`.
- The CLI falls back to `default` when no project is specified.
- The deployed `role-policy.yaml` already declares the `default` project.

To verify after upgrade:

```bash
sudo /opt/ai-agent/scripts/90-doctor.sh
sudo -u hermes morph-task --project default reconcile
```

No data migration script is needed.

---

## 10. Hardening checklist

- [ ] `role-policy.yaml` lists every project, with explicit `allowed_profiles`.
- [ ] Each project has its own `bd`-initialized workspace.
- [ ] Each project has its own handoff directory with 750 permissions.
- [ ] Orchestrator SOUL.md mandates `--project` on every `morph-task` call.
- [ ] Worker SOUL.md forbids overriding the project from the assignment.
- [ ] `90-doctor.sh` is green for every declared project.
- [ ] `morph-reconcile@<project>.timer` is enabled for every active project.
- [ ] Discord threads use `proj/<project>/<topic>` naming.

---

## 11. Failure modes & troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `denied: project denied: client-a` | Project not in `role-policy.yaml` | Run `51-create-project.sh client-a` |
| `denied: profile X cannot access project Y` | Profile not in `allowed_profiles` | Edit `role-policy.yaml`, restart agent |
| `bd: workspace not initialized` | Beads workspace missing `.beads` dir | Run `51-create-project.sh <project>` (idempotent) |
| `reconcile` reports `bead_missing_runtime_assignment` | Bead created via direct `bd` (bypass) | Investigate; only orchestrator should create. Re-assign via `morph-task assign` |
| `reconcile` reports `runtime_missing_bead` | Assignment row points to deleted bead | Manually close in runtime DB or re-create the bead |
| `health` shows zero for known-active project | Wrong `--project` value | Confirm spelling against `morph-task projects` |
