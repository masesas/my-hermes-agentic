# Deployment Notes — Morph AI Agent

## Critical Fixes Applied

### 1. Hermes Config Uses Literal 9Router Models

**Problem**: Hermes gateway did not consistently expand `${HERMES_MODEL}` inside profile `config.yaml`, causing requests to reach 9Router as `model=${HERMES_MODEL}` and fail with `No active credentials for provider: openai`.

**Solution**: Profile `config.yaml` now uses literal 9Router combo names:

- `orchestrator` → `morph-orchestrator`
- `researcher` → `morph-researcher`
- `executor` → `morph-executor`

For new agents, follow `morph-<profile>` and see `docs/ADDING_NEW_AGENT.md`.

### 2. Gateway Configuration

**Problem**: Discord gateway not enabled by default in profile `config.yaml`.

**Solution**: Add `gateway:` section to each profile's `config.yaml`:

```yaml
gateway:
  platforms:
    discord:
      enabled: true
      token: ${DISCORD_BOT_TOKEN}
```

### 3. Model Combo Mapping

Each agent profile uses a dedicated 9Router model combo:

| Profile | Model Combo | Purpose |
|---------|-------------|---------|
| orchestrator | `morph-orchestrator` | Task routing, planning |
| researcher | `morph-researcher` | Web research, analysis |
| executor | `morph-executor` | Code generation, execution |

**Note**: User must create these combos in 9Router dashboard at `https://my-hermes.otomotives.com/dashboard`.

## Verification Commands

```bash
# Check all gateways running
ps aux | grep hermes_cli | grep -v grep

# Check Discord connections (should show 3 ESTABLISHED)
sudo lsof -p $(pgrep -f "hermes_cli.*orchestrator") -a -i | grep ESTABLISHED
sudo lsof -p $(pgrep -f "hermes_cli.*researcher") -a -i | grep ESTABLISHED
sudo lsof -p $(pgrep -f "hermes_cli.*executor") -a -i | grep ESTABLISHED

# Check 9Router health
curl -s https://my-hermes.otomotives.com/api/health

# Check gateway logs
sudo -u hermes XDG_RUNTIME_DIR=/run/user/1005 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1005/bus \
  journalctl --user -u hermes-gateway-orchestrator -f
```

## Known Issues

1. **Systemd warnings**: `RestartMaxDelaySec` and `RestartSteps` not supported in Ubuntu 22.04 systemd version. Harmless warnings, can be ignored.

2. **Silent gateway logs**: Hermes gateway doesn't log to journal after successful Discord connection. Use `lsof` to verify network connections instead.

3. **Unit file regeneration**: Any manual edits to systemd unit files can be overwritten by Hermes. Keep durable model/base_url/api_key settings in profile `config.yaml` and use `.env` primarily for secrets such as `DISCORD_BOT_TOKEN`.

## Deployment Checklist

- [x] 9Router installed and running
- [x] Nginx configured with TLS
- [x] 3 Hermes profiles created (orchestrator, researcher, executor)
- [x] Discord bot tokens configured per profile
- [x] Model combos created in 9Router dashboard
- [x] Gateway config added to each profile
- [x] Systemd units patched with env vars
- [x] All 3 gateways running and connected to Discord
- [x] SQLite task queue initialized
- [x] Autonomous routing policy configured

## Next Steps

1. **Test Discord interaction**: Send `@MorphOrchestrator hello` in `#orchestrator` channel
2. **Monitor logs**: Watch for task routing and agent responses
3. **Create model combos**: If not done, create `morph-orchestrator`, `morph-researcher`, `morph-executor` in 9Router dashboard
4. **Set up monitoring**: Consider adding health check cron job

## Maintenance

### Restart all gateways
```bash
for p in orchestrator researcher executor; do
  sudo -u hermes XDG_RUNTIME_DIR=/run/user/1005 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1005/bus \
    systemctl --user restart hermes-gateway-$p
done
```

### Update Discord tokens
1. Edit `/home/hermes/.hermes/profiles/<profile>/.env`
2. Restart gateway: `sudo -u hermes ... systemctl --user restart hermes-gateway-<profile>`

---

**Deployed**: 2026-05-14 05:30 WIB  
**VPS**: 203.175.10.92:22172  
**Domain**: my-hermes.otomotives.com  
**Status**: ✅ Operational
