# Morph Task Multi-Project Support

`morph-task` supports project namespaces with `--project` or `MORPH_PROJECT`.

## Usage

```bash
morph-task --project client-a create --target executor --kind execution --title "Fix login"
morph-task --project client-a claim --target executor <bead-id>
morph-task --project client-a health
morph-task --project client-a audit --limit 20
```

If no project is provided, `default` is used.

## Policy

Projects are configured in `config/agency/role-policy.yaml`:

```yaml
projects:
  client-a:
    workspace: /home/hermes/workspace/client-a
    handoff_dir: /var/lib/morph-agency/handoff/client-a
    allowed_profiles:
      - orchestrator
      - researcher
      - executor
```

`allowed_profiles` gates which profiles may operate in that project.

## Runtime State

Runtime assignments and policy violations include `project_id`. This keeps Beads tasks, assignment claims, audit logs, and health summaries project-scoped while retaining one shared SQLite runtime DB.

## Workspace Model

Each project should have its own Beads workspace:

```text
/home/hermes/workspace/<project>/.beads
```

The real Beads binary remains shared at:

```text
/opt/morph-agency/bin/bd
```

## Discord Model

Recommended Discord mapping is one orchestrator channel with one thread per project. Workers should still only accept orchestrator-originated task IDs.

## Reconcile

Run read-only drift checks per project:

```bash
morph-task --project client-a reconcile
```

The command emits JSON with missing runtime assignments and runtime assignments whose Beads records cannot be shown.
