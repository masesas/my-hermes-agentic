# Morph AI Agent — Quick Start

## Status Check

```bash
# Check all services
ssh agentic@203.175.10.92 -p 22172 "
  echo '=== 9Router ==='
  curl -s https://my-hermes.otomotives.com/api/health
  echo
  echo
  echo '=== Hermes Gateways ==='
  ps aux | grep hermes_cli | grep -v grep | wc -l
  echo ' gateways running'
  echo
  echo '=== Discord Connections ==='
  sudo lsof -i | grep hermes_cli | grep ESTABLISHED | wc -l
  echo ' Discord connections'
"
```

## Restart Gateways

```bash
ssh agentic@203.175.10.92 -p 22172 "
  for p in orchestrator researcher executor; do
    sudo -u hermes XDG_RUNTIME_DIR=/run/user/1005 \
      DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1005/bus \
      systemctl --user restart hermes-gateway-\$p
  done
  echo 'All gateways restarted'
"
```

## View Logs

```bash
# Orchestrator
ssh agentic@203.175.10.92 -p 22172 "
  sudo -u hermes XDG_RUNTIME_DIR=/run/user/1005 \
    DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1005/bus \
    journalctl --user -u hermes-gateway-orchestrator -f
"

# Researcher
ssh agentic@203.175.10.92 -p 22172 "
  sudo -u hermes XDG_RUNTIME_DIR=/run/user/1005 \
    DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1005/bus \
    journalctl --user -u hermes-gateway-researcher -f
"

# Executor
ssh agentic@203.175.10.92 -p 22172 "
  sudo -u hermes XDG_RUNTIME_DIR=/run/user/1005 \
    DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1005/bus \
    journalctl --user -u hermes-gateway-executor -f
"
```

## Update Discord Tokens

```bash
# 1. Edit .env locally
vim .env

# 2. Sync to VPS
scp -P 22172 .env agentic@203.175.10.92:~/my-hermes-agentic/.env

# 3. Update profile .env files
ssh agentic@203.175.10.92 -p 22172 "
  cd ~/my-hermes-agentic
  for p in orchestrator researcher executor; do
    sudo cp .env /home/hermes/.hermes/profiles/\$p/.env
    sudo chown hermes:hermes /home/hermes/.hermes/profiles/\$p/.env
  done
"

# 4. Restart gateways (see above)
```

## Access 9Router Dashboard

1. Open: https://my-hermes.otomotives.com/dashboard
2. Login with provider credentials (Claude, Gemini, etc.)
3. Create model combos:
   - `morph-orchestrator`
   - `morph-researcher`
   - `morph-executor`

## Test Discord Bots

1. Open Discord server
2. Go to `#orchestrator` channel
3. Send: `@MorphOrchestrator hello`
4. Bot should respond within a few seconds

## Troubleshooting

### Gateway not starting
```bash
# Check systemd unit
ssh agentic@203.175.10.92 -p 22172 "
  cat /home/hermes/.config/systemd/user/hermes-gateway-orchestrator.service
"

# Check literal model config
ssh agentic@203.175.10.92 -p 22172 "
  grep -A4 '^model:' /home/hermes/.hermes/profiles/orchestrator/config.yaml
"

# Expected: default: morph-orchestrator, not ${HERMES_MODEL}
```

### Discord bot not responding
```bash
# Check Discord connection
ssh agentic@203.175.10.92 -p 22172 "
  sudo lsof -p \$(pgrep -f 'hermes_cli.*orchestrator') -a -i | grep ESTABLISHED
"

# Should show connection to 162.159.*.234:443

# Check Discord token
ssh agentic@203.175.10.92 -p 22172 "
  grep DISCORD_BOT_TOKEN /home/hermes/.hermes/profiles/orchestrator/.env
"

# Verify bot has proper intents in Discord Developer Portal:
# - MESSAGE CONTENT INTENT
# - SERVER MEMBERS INTENT
# - PRESENCE INTENT
```

### Model not found error
```bash
# Check if model combo exists in 9Router
curl -s https://my-hermes.otomotives.com/v1/models | jq '.data[] | select(.id | contains("morph"))'

# If empty, create combos in dashboard
```

## Important Files

| File | Purpose |
|------|---------|
| `/home/hermes/.hermes/profiles/<profile>/.env` | Profile environment vars |
| `/home/hermes/.hermes/profiles/<profile>/config.yaml` | Profile configuration |
| `/home/hermes/.config/systemd/user/hermes-gateway-<profile>.service` | Systemd unit |
| `/var/lib/morph-agency/queue.db` | SQLite task queue |
| `/etc/nginx/sites-enabled/my-hermes.otomotives.com.conf` | Nginx config |

## Maintenance Schedule

- **Daily**: Check gateway status, Discord connections
- **Weekly**: Review logs for errors, check disk space
- **Monthly**: Update Hermes CLI, rotate logs
- **As needed**: Update Discord tokens, add new profiles

---

**Quick Links**:
- Dashboard: https://my-hermes.otomotives.com/dashboard
- Health: https://my-hermes.otomotives.com/api/health
- Models: https://my-hermes.otomotives.com/v1/models
- VPS: ssh agentic@203.175.10.92 -p 22172
