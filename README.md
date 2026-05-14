# Hermes Orchestrator VPS Starter

Starter kit for a native Ubuntu 22.04 VPS deployment:

- 1 Hermes Agent orchestrator
- 9Router as a public OpenAI-compatible endpoint
- HTTPS reverse proxy via existing Nginx (`WEB_SERVER=nginx-direct`) or Caddy (`WEB_SERVER=caddy`)
- CLI over SSH
- Discord gateway via systemd

This repository only creates install/config scripts. Do not run these scripts on your local machine unless it is the target VPS.

## Topology

```text
User CLI / Discord
        |
        v
Hermes Orchestrator
        |
        v
https://your-domain/v1
        |
        v
9Router public endpoint + dashboard
        |
        v
Provider combo / alias / fallback
```

## VPS Requirements

- Ubuntu 22.04
- A domain pointing to the VPS, for example `ai.example.com`
- Root or sudo access
- Open inbound ports: `22`, `80`, `443`
- Do not expose port `20128` directly to the internet

## Setup Flow

For the complete Indonesian step-by-step VPS deployment guide, see:

```text
docs/VPS_DEPLOYMENT.md
```

For Discord server, channel, role, and bot setup, see:

```text
docs/DISCORD_SETUP.md
```

For autonomous Discord agent routing and anti-loop policy, see:

```text
docs/AUTONOMOUS_DISCORD_AGENTS.md

docs/ADDING_NEW_AGENT.md
```

On the VPS:

```bash
cd /opt
git clone <your-repo-url> ai-agent
cd ai-agent/starter-vps
cp .env.example .env
nano .env
```

Run the base 9Router stack first:

```bash
sudo ./scripts/00-preflight.sh
sudo ./scripts/10-install-system-deps.sh
sudo ./scripts/20-install-9router.sh
sudo ./scripts/50-setup-systemd.sh
sudo ./scripts/60-setup-caddy.sh
```

If `.env` sets `WEB_SERVER=nginx-direct`, `60-setup-caddy.sh` skips Caddy setup. Configure Nginx to proxy the agent domain directly to `http://127.0.0.1:20128`.

## Important Manual Step

After your public reverse proxy is running, open:

```text
https://your-domain/dashboard
```

Log in with `NINE_ROUTER_INITIAL_PASSWORD`, configure providers, then create:

- an API key for Hermes
- a model alias or combo named `orchestrator/powerful`

Put the generated API key into `.env`:

```bash
NINE_ROUTER_API_KEY=...
```

Then install and configure Hermes:

```bash
sudo ./scripts/30-install-hermes.sh
sudo ./scripts/40-setup-hermes-orchestrator.sh
sudo ./scripts/41-setup-hermes-profiles.sh
sudo ./scripts/42-seed-profile-souls.sh
sudo ./scripts/43-link-discord-channels.sh
sudo ./scripts/44-configure-agent-routing.sh
sudo ./scripts/50-setup-systemd.sh
sudo ./scripts/55-setup-systemd-per-profile.sh
sudo ./scripts/90-doctor.sh
```

## Operating Commands

```bash
sudo systemctl status 9router
sudo systemctl status 9router
sudo -u hermes XDG_RUNTIME_DIR=/run/user/1005 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1005/bus systemctl --user status hermes-gateway-orchestrator
sudo journalctl -u 9router -f
sudo -u hermes XDG_RUNTIME_DIR=/run/user/1005 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1005/bus journalctl --user -u hermes-gateway-orchestrator -f
```

CLI:

```bash
sudo -iu hermes
hermes
```

One-shot smoke test:

```bash
sudo -iu hermes hermes -z "Reply exactly: OK"
```

## Security Notes

- Keep `/etc/9router/9router.env` and `/home/hermes/.hermes/.env` readable only by their owners.
- Use long random values for all 9Router secrets.
- Keep Nginx or Caddy in front of 9Router; do not publish `:20128`.
- Keep request debug logging disabled unless you are diagnosing an issue.
- Rotate the 9Router API key if it is ever pasted into logs or chat.
