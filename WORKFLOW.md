# Workflow

Development workflows for the Morph AI Agent project.

---

## Adding a New Agent Profile

> Current deployment note: the production VPS uses `WEB_SERVER=nginx-direct`, 9Router at `https://my-hermes.otomotives.com`, and Hermes gateways as **user-level systemd services** owned by user `hermes`. For the full operational runbook, see `docs/ADDING_NEW_AGENT.md`.

### Step 1: Define the Agent Contract

Choose the stable profile name first; it is reused across repo config, Discord, 9Router, and systemd.

| Layer | Pattern | Example |
| --- | --- | --- |
| Profile | lowercase single word | `reviewer` |
| Hermes agent name | `hermes-<profile>` | `hermes-reviewer` |
| 9Router combo | `morph-<profile>` | `morph-reviewer` |
| Discord bot | `Morph<Profile>` | `MorphReviewer` |
| Discord channel | `#<profile>` | `#reviewer` |
| User systemd unit | `hermes-gateway-<profile>.service` | `hermes-gateway-reviewer.service` |

Document the role, permissions, lifecycle, and escalation path before creating runtime files.

### Step 2: Create Local Profile Files

Recommended shortcut:

```bash
./scripts/45-create-agent-profile.sh
```

The generator asks for the profile role, purpose, 9Router combo, Discord bot/channel, lifecycle, access preset, and skill playbook options. It creates the baseline files listed below. You may also create them manually if the profile needs a custom structure.

Create the profile directory and configuration:

```text
config/hermes/profiles/<name>/
  SOUL.md              # Identity, purpose, authority, tool permissions, avoid list, defaults
  config.yaml          # Runtime config with 9Router model combo
  discord-policy.yaml  # Discord channel policy and interaction rules, if needed
```

### Step 3: Write `SOUL.md`

Follow the established SOUL.md structure:

```markdown
# Hermes <Name>

## Identity
- Name, Role, Expertise, Purpose, Authority, Communication channel

## Style
- Communication style and output format guidelines

## Avoid
- Explicit list of prohibited actions

## Defaults
- Default behaviors when instructions are ambiguous
```

Reference existing profiles in `config/hermes/profiles/` for examples.

### Step 4: Create `config.yaml`

Use **literal 9Router values** in `model.default`, `model.base_url`, and `model.api_key`. Do not use `${HERMES_MODEL}` for `model.default`; the active Hermes gateway deployment has shown that placeholder can remain unresolved at runtime.

Required baseline:

```yaml
agent:
  name: hermes-<profile>
  max_turns: 80

model:
  provider: custom
  default: morph-<profile>
  base_url: https://my-hermes.otomotives.com/v1
  api_key: local-9router-placeholder

terminal:
  backend: local
  cwd: /home/hermes/workspace
  timeout: 600
  persistent_shell: true

memory:
  memory_enabled: true

timezone: Asia/Jakarta

discord:
  require_mention: true
  auto_thread: true

gateway:
  platforms:
    discord:
      enabled: true
      token: ${DISCORD_BOT_TOKEN}

streaming:
  enabled: true
  transport: edit

group_sessions_per_user: true
```

Add delegation, approval, terminal, and tool constraints based on the agent role. Only the orchestrator should have broad delegation authority.

### Step 5: Register the 9Router Combo

Create the matching combo in the 9Router dashboard:

```text
https://my-hermes.otomotives.com/dashboard
```

Combo name:

```text
morph-<profile>
```

Verify it before connecting Discord:

```bash
curl -sS https://my-hermes.otomotives.com/v1/chat/completions   -H 'Content-Type: application/json'   -H 'Authorization: Bearer local-9router-placeholder'   -d '{"model":"morph-<profile>","messages":[{"role":"user","content":"reply with OK only"}],"max_tokens":10}'
```

### Step 6: Create the Discord Bot

1. Create a Discord application and bot in the Discord Developer Portal.
2. Name it `Morph<Profile>`.
3. Enable required intents, especially `MESSAGE CONTENT INTENT`.
4. Invite it to the server with permission to read and send messages in `#<profile>`.
5. Store the token in the profile `.env` on the VPS as `DISCORD_BOT_TOKEN`.
6. Add the token to the project `.env` using a profile-specific name such as `DISCORD_BOT_TOKEN_REVIEWER` for repeatable setup.

### Step 7: Seed the Profile on the VPS

Sync repo changes first:

```bash
rsync -az --exclude='.git' --exclude='.env'   -e 'ssh -p 22172' ./ agentic@203.175.10.92:~/my-hermes-agentic/
```

Create and seed the profile:

```bash
PROFILE=<profile>

sudo -iu hermes /home/hermes/.local/bin/hermes profile create "$PROFILE" || true

sudo install -o hermes -g hermes -m 0644   ~/my-hermes-agentic/config/hermes/profiles/$PROFILE/SOUL.md   /home/hermes/.hermes/profiles/$PROFILE/SOUL.md

sudo install -o hermes -g hermes -m 0644   ~/my-hermes-agentic/config/hermes/profiles/$PROFILE/config.yaml   /home/hermes/.hermes/profiles/$PROFILE/config.yaml
```

Create the profile env file:

```bash
sudo install -o hermes -g hermes -m 0600 /dev/null   /home/hermes/.hermes/profiles/$PROFILE/.env

sudo tee /home/hermes/.hermes/profiles/$PROFILE/.env >/dev/null <<'EOF'
DISCORD_BOT_TOKEN=replace-with-profile-token
GATEWAY_ALLOW_ALL_USERS=true
NINE_ROUTER_BASE_URL=https://my-hermes.otomotives.com/v1
NINE_ROUTER_API_KEY=local-9router-placeholder
EOF

sudo chown hermes:hermes /home/hermes/.hermes/profiles/$PROFILE/.env
sudo chmod 600 /home/hermes/.hermes/profiles/$PROFILE/.env
```

### Step 8: Install User-Level systemd Gateway

The active deployment uses user-level systemd units, not root-level `hermes-<profile>-gateway.service` units.

```bash
PROFILE=<profile>

sudo -iu hermes /home/hermes/.local/bin/hermes --profile "$PROFILE" gateway install

sudo -u hermes XDG_RUNTIME_DIR=/run/user/1005   DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1005/bus   systemctl --user daemon-reload

sudo -u hermes XDG_RUNTIME_DIR=/run/user/1005   DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1005/bus   systemctl --user enable --now hermes-gateway-$PROFILE
```

Unit path:

```text
/home/hermes/.config/systemd/user/hermes-gateway-<profile>.service
```

Hermes may regenerate the unit file. Keep durable runtime settings in `config.yaml` and the profile `.env`, not in manual edits to the generated service file.

### Step 9: Update Setup Scripts and Runtime Routing

For repeatability, update the setup scripts if the profile is part of the standard deployment:

- Add the profile to `41-setup-hermes-profiles.sh`
- Add SOUL/config seeding to `42-seed-profile-souls.sh`
- Add Discord token/channel mapping to `43-link-discord-channels.sh`
- Add user-service handling to `55-setup-systemd-per-profile.sh` if that script is still used
- Add health checks to `90-doctor.sh`

If the agent participates in autonomous routing, update the routing policy on the VPS:

```text
/var/lib/morph-agency/config/autonomous-routing.yaml
```

### Step 10: Update Documentation

- Add the profile to `AGENT_REGISTRY.md`
- Update `DISCORD_PLAYBOOK.md` channel structure if humans interact with it directly
- Update `ARCHITECTURE.md` cost strategy and role tables if it is a permanent profile
- Update `docs/ADDING_NEW_AGENT.md` if the operational process changes

### Step 11: Test

1. Verify the 9Router combo responds.
2. Run a CLI one-shot:

```bash
sudo -iu hermes /home/hermes/.local/bin/hermes --profile <name> -z "Reply exactly: OK"
```

3. Verify gateway status:

```bash
sudo -u hermes XDG_RUNTIME_DIR=/run/user/1005   DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1005/bus   systemctl --user status hermes-gateway-<name>
```

4. Verify Discord connection:

```bash
PID=$(pgrep -f 'hermes_cli.main --profile <name> gateway run' | head -1)
sudo lsof -p "$PID" -a -i | grep ESTABLISHED
```

5. Send a Discord smoke test:

```text
@Morph<Name> reply with OK only
```

6. Run `90-doctor.sh` once it includes the new profile.

## Modifying an Existing Profile

1. Edit the relevant files in `config/hermes/profiles/<name>/`
2. If modifying SOUL.md: restart the user-level gateway service
3. If modifying config.yaml: restart the user-level gateway service
4. If modifying LLM combo: update 9Router dashboard; no 9Router restart is normally needed if the dashboard persists it
5. Test the change with a representative CLI one-shot and Discord mention
6. Commit with message: `refactor: update <profile> <what changed>`

---

## Testing Profile Changes

### Local Validation

```bash
# Validate YAML syntax
python3 -c "import yaml; yaml.safe_load(open('config/hermes/profiles/<name>/config.yaml'))"

# Verify SOUL.md structure
grep -c "^## " config/hermes/profiles/<name>/SOUL.md
# Expected: 4 sections (Identity, Style, Avoid, Defaults)
```

### On-VPS Smoke Test

```bash
# Interactive test (no Discord)
sudo -iu hermes hermes -p <name> chat

# One-shot test
sudo -iu hermes hermes -p <name> -z "Reply exactly: OK"

# Full gateway test
sudo -u hermes XDG_RUNTIME_DIR=/run/user/1005 \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1005/bus \
  systemctl --user restart hermes-gateway-<name>

sudo -u hermes XDG_RUNTIME_DIR=/run/user/1005 \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1005/bus \
  journalctl --user -u hermes-gateway-<name> -f
# Then send a test message via Discord
```

### Integration Test

Send a multi-step task through the orchestrator that exercises the modified profile:

```
@Orchestrator test the <profile> agent with: <representative task>
```

---

## Git Flow

### Feature Development

```
main
  └── feat/<description>    ← work here
        └── PR → main       ← review required
```

1. Create branch: `git checkout -b feat/<description>`
2. Make changes, commit with conventional messages
3. Push: `git push -u origin feat/<description>`
4. Open PR against `main`
5. Request review (or use the reviewer profile when available)
6. Merge after approval

### Commit Checklist

Before committing:

- [ ] Scripts have `set -euo pipefail` and `source lib.sh`
- [ ] No secrets in committed files
- [ ] YAML files parse without errors
- [ ] SOUL.md has all 4 required sections
- [ ] config.yaml has all required fields
- [ ] `AGENT_REGISTRY.md` is updated if profiles changed
- [ ] Conventional commit message format used

---

## Profile Onboarding Checklist

Use this checklist when adding a new profile:

- [ ] `config/hermes/profiles/<name>/SOUL.md` created with all sections
- [ ] `config/hermes/profiles/<name>/config.yaml` created with literal `morph-<name>` model
- [ ] 9Router combo `morph-<name>` exists and direct API test passes
- [ ] Discord bot created and token stored
- [ ] Discord channel `#<name>` created
- [ ] User-level systemd unit `hermes-gateway-<name>.service` installed under `/home/hermes/.config/systemd/user/`
- [ ] Setup scripts updated (`41`, `42`, `43`, `55`, `90`) if agent is part of standard deployment
- [ ] `AGENT_REGISTRY.md` updated
- [ ] `DISCORD_PLAYBOOK.md` updated (if new channel)
- [ ] `ARCHITECTURE.md` memory budget updated
- [ ] Smoke test passed (CLI one-shot)
- [ ] Gateway test passed (Discord message and `lsof` established connection)
- [ ] `90-doctor.sh` health check passes
