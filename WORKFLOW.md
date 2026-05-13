# Workflow

Development workflows for the Morph AI Agent project.

---

## Adding a New Agent Profile

### Step 1: Define the Profile

Create the profile directory and configuration:

```
config/hermes/profiles/<name>/
  SOUL.md       # Identity, purpose, authority, tool permissions, avoid list, defaults
  config.yaml   # LLM combo, delegation limits, terminal config
```

### Step 2: Write the SOUL.md

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

### Step 3: Create config.yaml

Required fields:

```yaml
agent:
  name: hermes-<profile>
  max_turns: <80 for workers, 160 for orchestrator>

model:
  provider: custom
  default: combo:<premium|balanced|budget>
  base_url: ${NINE_ROUTER_BASE_URL}
  api_key: ${NINE_ROUTER_API_KEY}

delegation:
  max_concurrent_children: 2
  max_spawn_depth: 1
  orchestrator_enabled: false    # true only for orchestrator
```

### Step 4: Register the LLM Combo

If the profile needs a new 9Router combo, add it to the 9Router configuration. See `ARCHITECTURE.md` for existing combo definitions.

### Step 5: Create the Discord Bot

1. Create a new Discord bot in the Discord Developer Portal
2. Name it `Morph<Profile>` (e.g., `MorphReviewer`)
3. Grant required intents: Message Content, Guild Messages
4. Store the bot token in the profile's `.env` file
5. Create the corresponding Discord channel `#<profile>`

### Step 6: Create the systemd Service

Add a service file following the naming pattern:

```ini
# systemd/hermes-<profile>-gateway.service
[Unit]
Description=Hermes <Profile> Discord gateway
After=network-online.target 9router.service
Wants=network-online.target

[Service]
Type=simple
User=hermes
Group=hermes
WorkingDirectory=/home/hermes/workspace
ExecStart=/home/hermes/.local/bin/hermes -p <profile> gateway start
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

### Step 7: Update Setup Scripts

- Add the profile to `41-setup-hermes-profiles.sh`
- Add the SOUL.md seeding to `42-seed-profile-souls.sh`
- Add Discord channel/bot mapping to `43-link-discord-channels.sh`
- Add the systemd unit to `55-setup-systemd-per-profile.sh`

### Step 8: Update Documentation

- Add the profile to `AGENT_REGISTRY.md`
- Update `DISCORD_PLAYBOOK.md` channel structure if needed
- Update `ARCHITECTURE.md` diagrams and memory budget

### Step 9: Test

1. Run `hermes profile create <name>` on the VPS
2. Copy SOUL.md and config.yaml to the profile directory
3. Start the gateway: `hermes -p <name> gateway start`
4. Send a test task via Discord or CLI
5. Verify the agent responds correctly
6. Run `90-doctor.sh` to confirm health checks pass

---

## Modifying an Existing Profile

1. Edit the relevant files in `config/hermes/profiles/<name>/`
2. If modifying SOUL.md: the change takes effect on next gateway restart
3. If modifying config.yaml: restart the systemd service
4. If modifying LLM combo: update 9Router config and restart 9Router
5. Test the change with a representative task
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
sudo systemctl restart hermes-<name>-gateway
sudo journalctl -u hermes-<name>-gateway -f
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
- [ ] `config/hermes/profiles/<name>/config.yaml` created with correct combo
- [ ] 9Router combo exists (or new combo added)
- [ ] Discord bot created and token stored
- [ ] Discord channel `#<name>` created
- [ ] `systemd/hermes-<name>-gateway.service` created
- [ ] Setup scripts updated (`41`, `42`, `43`, `55`)
- [ ] `AGENT_REGISTRY.md` updated
- [ ] `DISCORD_PLAYBOOK.md` updated (if new channel)
- [ ] `ARCHITECTURE.md` memory budget updated
- [ ] Smoke test passed (CLI one-shot)
- [ ] Gateway test passed (Discord message)
- [ ] `90-doctor.sh` health check passes
