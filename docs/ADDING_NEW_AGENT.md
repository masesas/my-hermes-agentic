# Adding a New Agent

Panduan ini adalah referensi operasional untuk menambahkan agent Hermes baru pada deployment Morph AI Agent saat ini.

> Status deployment saat ini: VPS memakai `WEB_SERVER=nginx-direct`, 9Router publik di `https://my-hermes.otomotives.com`, dan gateway Hermes berjalan sebagai **user-level systemd service** milik user `hermes`.


---

## Shortcut: Interactive Profile Generator

Untuk membuat struktur profile baru lebih cepat, gunakan script interaktif:

```bash
./scripts/45-create-agent-profile.sh
```

Script ini akan menanyakan kebutuhan agent baru, lalu menghasilkan:

```text
config/hermes/profiles/<profile>/SOUL.md
config/hermes/profiles/<profile>/config.yaml
config/hermes/profiles/<profile>/discord-policy.yaml
config/hermes/profiles/<profile>/.env.template
config/hermes/profiles/<profile>/README.md
config/hermes/profiles/<profile>/skills/<profile>-playbook/SKILL.md
```

Script juga dapat memakai profile existing seperti `executor`, `researcher`, atau `orchestrator` sebagai referensi gaya dan dapat menyalin folder `skills/` bila profile referensi memilikinya.

Tetap lakukan langkah manual berikut setelah generator selesai:

1. Review hasil `SOUL.md` dan `config.yaml`.
2. Buat 9Router combo `morph-<profile>`.
3. Buat Discord bot dan channel.
4. Tambahkan token `DISCORD_BOT_TOKEN_<PROFILE>` ke `.env`.
5. Sync ke VPS dan install user-level gateway.

---

## Naming Convention

Gunakan nama yang konsisten di semua layer:

| Layer | Format | Contoh untuk `reviewer` |
| --- | --- | --- |
| Profile | lowercase single word | `reviewer` |
| Hermes agent name | `hermes-<profile>` | `hermes-reviewer` |
| 9Router combo | `morph-<profile>` | `morph-reviewer` |
| Discord bot | `Morph<Profile>` | `MorphReviewer` |
| Discord channel | `#<profile>` | `#reviewer` |
| User systemd unit | `hermes-gateway-<profile>.service` | `hermes-gateway-reviewer.service` |

---

## 1. Create 9Router Model Combo

Di dashboard 9Router:

```text
https://my-hermes.otomotives.com/dashboard
```

Buat combo dengan nama:

```text
morph-<profile>
```

Contoh:

```text
morph-reviewer
```

Pastikan combo dapat dipanggil dari OpenAI-compatible endpoint:

```bash
curl -sS https://my-hermes.otomotives.com/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer local-9router-placeholder' \
  -d '{"model":"morph-reviewer","messages":[{"role":"user","content":"reply with OK only"}],"max_tokens":10}'
```

Jika combo benar, response akan stream token dari model provider yang dipilih.

---

## 2. Create Discord Bot and Channel

Di Discord Developer Portal:

1. Buat application baru.
2. Buat bot dengan nama `Morph<Profile>`.
3. Aktifkan intent yang dibutuhkan:
   - `MESSAGE CONTENT INTENT`
   - `SERVER MEMBERS INTENT` jika bot perlu baca member/mention lebih lengkap
   - `PRESENCE INTENT` hanya jika memang dibutuhkan
4. Invite bot ke server dengan permission untuk membaca dan mengirim pesan.
5. Buat channel `#<profile>`.
6. Simpan token di `.env` root project dengan format:

```bash
DISCORD_BOT_TOKEN_REVIEWER=replace-with-token
```

Jangan commit token ke Git.

---

## 3. Add Local Profile Files

Buat directory:

```text
config/hermes/profiles/<profile>/
```

Minimal file:

```text
config/hermes/profiles/<profile>/SOUL.md
config/hermes/profiles/<profile>/config.yaml
config/hermes/profiles/<profile>/discord-policy.yaml
```

### `SOUL.md`

Ikuti struktur profile existing:

```markdown
# Hermes <Profile>

## Identity
- Name, role, expertise, purpose, authority, channel

## Style
- Communication style and output format

## Avoid
- Explicit list of prohibited actions

## Defaults
- Default behavior when instructions are ambiguous
```

### `config.yaml`

Gunakan **nilai literal** untuk `model.default`, `base_url`, dan `api_key`. Jangan memakai `${HERMES_MODEL}` karena Hermes gateway pada deployment ini tidak mengekspansi placeholder tersebut secara konsisten.

```yaml
agent:
  name: hermes-reviewer
  max_turns: 80

model:
  provider: custom
  default: morph-reviewer
  base_url: https://my-hermes.otomotives.com/v1
  api_key: local-9router-placeholder

terminal:
  backend: local
  cwd: /home/hermes/workspace
  timeout: 600
  persistent_shell: true

memory:
  memory_enabled: true

compression:
  threshold: 0.45

display:
  streaming: false

approvals:
  mode: smart

security:
  redact_secrets: true
  tirith_enabled: true

checkpoints:
  enabled: true
  max_snapshots: 50

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
  enabled: false
  transport: final

group_sessions_per_user: true
```

---

## 4. Register the Agent in Repo Metadata

Update file berikut:

- `AGENT_REGISTRY.md` — tambahkan row profile dan detail permission.
- `DISCORD_PLAYBOOK.md` — tambahkan channel dan routing behavior bila channel baru berinteraksi dengan manusia.
- `ARCHITECTURE.md` — tambahkan ke cost strategy atau diagram jika role baru permanen.
- `WORKFLOW.md` — update jika ada perubahan proses onboarding.

Jika agent ikut autonomous routing, update juga:

- routing policy di `/var/lib/morph-agency/config/autonomous-routing.yaml` pada VPS
- script setup queue/routing bila tersedia di repo

---

## 5. Sync Repo and Env to VPS

Dari local project:

```bash
rsync -az --exclude='.git' --exclude='.env' \
  -e 'ssh -p 22172' ./ agentic@203.175.10.92:~/my-hermes-agentic/

scp -P 22172 .env agentic@203.175.10.92:~/my-hermes-agentic/.env
```

---

## 6. Create Hermes Profile on VPS

SSH ke VPS:

```bash
ssh agentic@203.175.10.92 -p 22172
```

Buat profile dan seed file:

```bash
PROFILE=reviewer

sudo -iu hermes /home/hermes/.local/bin/hermes profile create "$PROFILE" || true

sudo install -o hermes -g hermes -m 0644 \
  ~/my-hermes-agentic/config/hermes/profiles/$PROFILE/SOUL.md \
  /home/hermes/.hermes/profiles/$PROFILE/SOUL.md

sudo install -o hermes -g hermes -m 0644 \
  ~/my-hermes-agentic/config/hermes/profiles/$PROFILE/config.yaml \
  /home/hermes/.hermes/profiles/$PROFILE/config.yaml
```

Tambahkan `.env` profile. Minimal:

```bash
sudo tee /home/hermes/.hermes/profiles/$PROFILE/.env >/dev/null <<'EOF'
DISCORD_BOT_TOKEN=replace-with-profile-token
GATEWAY_ALLOW_ALL_USERS=true
NINE_ROUTER_BASE_URL=https://my-hermes.otomotives.com/v1
NINE_ROUTER_API_KEY=local-9router-placeholder
EOF

sudo chown hermes:hermes /home/hermes/.hermes/profiles/$PROFILE/.env
sudo chmod 600 /home/hermes/.hermes/profiles/$PROFILE/.env
```

---

## 7. Install User-Level Gateway Service

Deployment aktif memakai user-level systemd milik user `hermes`, bukan unit root-level `hermes-<profile>-gateway.service`.

```bash
PROFILE=reviewer

sudo -iu hermes /home/hermes/.local/bin/hermes --profile "$PROFILE" gateway install

sudo -u hermes XDG_RUNTIME_DIR=/run/user/1005 \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1005/bus \
  systemctl --user daemon-reload
```

Unit akan berada di:

```text
/home/hermes/.config/systemd/user/hermes-gateway-<profile>.service
```

> Catatan: Hermes dapat me-regenerate unit file saat restart. Jangan bergantung pada edit manual `EnvironmentFile=` untuk config utama. Untuk deployment ini, nilai model/base_url sudah dibuat literal di `config.yaml`.

---

## 8. Start and Verify the Agent

Start gateway:

```bash
PROFILE=reviewer

sudo -u hermes XDG_RUNTIME_DIR=/run/user/1005 \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1005/bus \
  systemctl --user enable --now hermes-gateway-$PROFILE
```

Cek status:

```bash
sudo -u hermes XDG_RUNTIME_DIR=/run/user/1005 \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1005/bus \
  systemctl --user status hermes-gateway-reviewer
```

Cek koneksi Discord:

```bash
PID=$(pgrep -f 'hermes_cli.main --profile reviewer gateway run' | head -1)
sudo lsof -p "$PID" -a -i | grep ESTABLISHED
```

Expected: koneksi HTTPS established ke `162.159.*.*:443` atau endpoint Discord/Cloudflare lain.

---

## 9. Smoke Test

CLI one-shot:

```bash
sudo -iu hermes /home/hermes/.local/bin/hermes --profile reviewer -z 'reply with OK only'
```

Expected:

```text
OK
```

Discord test:

```text
@MorphReviewer reply with OK only
```

Jika muncul error `No active credentials for provider: openai`, cek lagi:

1. `config.yaml` tidak boleh berisi `default: ${HERMES_MODEL}`.
2. 9Router combo `morph-reviewer` harus ada.
3. Combo harus punya provider credential aktif.
4. Gateway harus sudah restart bersih setelah config diubah.

---

## 10. Update Health Checks and Automation

Setelah agent stabil:

- tambahkan profile ke script setup profile jika ingin idempotent (`scripts/41-*`, `scripts/42-*`, `scripts/43-*`, `scripts/55-*` bila masih dipakai)
- tambahkan ke doctor script bila health check harus mencakup agent baru
- tambahkan ke autonomous routing policy bila orchestrator boleh mendelegasikan task ke agent tersebut
- update backup/restore procedure jika profile perlu persistent memory khusus

---

## Checklist

- [ ] Role dan nama profile ditentukan
- [ ] 9Router combo `morph-<profile>` dibuat dan berhasil dites
- [ ] Discord bot `Morph<Profile>` dibuat dan di-invite
- [ ] Channel `#<profile>` dibuat
- [ ] `SOUL.md` dibuat
- [ ] `config.yaml` dibuat dengan model literal `morph-<profile>`
- [ ] `.env` profile dibuat dengan token bot benar
- [ ] Hermes profile dibuat di VPS
- [ ] User-level systemd gateway di-install
- [ ] Gateway active dan punya koneksi Discord established
- [ ] CLI one-shot smoke test berhasil
- [ ] Discord mention test berhasil
- [ ] `AGENT_REGISTRY.md` dan docs terkait di-update
