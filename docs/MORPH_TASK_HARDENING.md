# Morph Task Hardening

`morph-task` is the required task-operation wrapper for Morph agency profiles. It enforces role boundaries before any Beads or SQLite runtime operation runs.

## Direct `bd` Guard

`scripts/47-install-morph-task.sh` installs a guard at `/usr/local/bin/bd` by default. The guard exits with code `126` and instructs agents to use `morph-task`.

Install the real Beads binary with `scripts/46-install-beads.sh`. It should live outside generic worker PATH, defaulting to:

```text
/opt/morph-agency/bin/bd
```

`morph-task` calls the real binary through `MORPH_BEADS_BIN` or `backend.beads_bin` in `/var/lib/morph-agency/config/role-policy.yaml`.

## Role Boundaries

- `orchestrator`: may create, assign, close, ready, show, and doctor; may not claim or submit worker results.
- `researcher`: may claim/progress/result only `researcher` tasks; may not create, assign, close, or execute work.
- `executor`: may claim/progress/result only `executor` tasks; may not create, assign, close, or research work.

Denied actions are audited to `policy_violations` when a runtime DB is available.

## VPS Verification

After installing Beads and `morph-task`:

```bash
sudo ./scripts/46-install-beads.sh
sudo ./scripts/47-install-morph-task.sh
sudo -u hermes env MORPH_PROFILE=orchestrator morph-task doctor
sudo -u hermes env MORPH_PROFILE=executor morph-task assign --target researcher some-task-id
```

The second command should pass. The third command should be denied and audited.

## Operations Commands

Use these commands for non-E2E operational checks:

```bash
morph-task audit --limit 20
morph-task health
scripts/48-build-morph-task.sh
```

`audit` lists recent denied policy actions. `health` summarizes runtime assignment status and policy violation counts.

## Rollback

To temporarily roll back the direct `bd` guard:

```bash
sudo rm -f /usr/local/bin/bd
sudo ln -s /opt/morph-agency/bin/bd /usr/local/bin/bd
```

To roll back profile usage, remove these keys from each profile `.env`:

```text
MORPH_PROFILE
MORPH_TASK_BIN
MORPH_ROLE_POLICY
MORPH_RUNTIME_DB
MORPH_BEADS_BIN
MORPH_BEADS_WORKSPACE
MORPH_DENY_DIRECT_BD
```

Then re-run the earlier profile setup scripts and restart Hermes profile gateways.
