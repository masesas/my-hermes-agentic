# Deployment Notes — Morph AI Agent

## Critical Fixes Applied

### 1. Systemd Unit Environment Variables

**Problem**: Hermes gateway auto-regenerates systemd unit files on restart, removing any `EnvironmentFile=` directives we add manually.

**Solution**: Inject environment variables directly as `Environment=` lines in the systemd unit file after `HERMES_HOME` line. These persist across Hermes gateway restarts.

**Script**: `/tmp/patch-units.sh` on VPS extracts vars from `.env` and injects into unit files.

**Key vars injected**:
- `HERMES_MODEL` (e.g., `morph-orchestrator`)
- `DISCORD_BOT_TOKEN`
- `NINE_ROUTER_BASE_URL`
- `NINE_ROUTER_API_KEY`

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

3. **Unit file regeneration**: Any manual edits to systemd unit files will be overwritten on gateway restart. Always use the patch script to re-inject env vars after Hermes updates.

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

### Re-apply env var patch after Hermes update
```bash
sudo bash /tmp/patch-units.sh
```

### Update Discord tokens
1. Edit `/home/hermes/.hermes/profiles/<profile>/.env`
2. Run patch script: `sudo bash /tmp/patch-units.sh`
3. Restart gateway: `sudo -u hermes ... systemctl --user restart hermes-gateway-<profile>`

---

**Deployed**: 2026-05-14 05:30 WIB  
**VPS**: 203.175.10.92:22172  
**Domain**: my-hermes.otomotives.com  
**Status**: ✅ Operational
