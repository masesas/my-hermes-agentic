# Autonomous Discord Agents

Dokumen ini menjelaskan cara menjalankan agent Discord yang auto-reply dan saling berkoordinasi secara autonomous dengan pola aman: **Orchestrator + SQLite queue**. Discord digunakan sebagai human interface dan progress log, bukan sebagai sumber state utama antar-agent.

---

## 1. Prinsip Operasi

Mode autonomous yang direkomendasikan:

```text
Human -> #orchestrator
Orchestrator -> /var/lib/morph-agency/queue.db
Researcher/Executor -> claim assigned task
Researcher/Executor -> post progress ke channel masing-masing
Researcher/Executor -> write result ke queue/handoff
Orchestrator -> synthesize -> reply final ke #orchestrator
```

Aturan utama:

- Orchestrator adalah satu-satunya agent yang boleh membuat atau assign task.
- Researcher dan executor tidak boleh delegate ke agent lain.
- Setiap pesan agent-to-agent harus punya `task_id`.
- Worker mengabaikan pesan bot yang tidak berasal dari orchestrator.
- Discord message chain dibatasi `max_reply_depth=3` untuk mencegah loop.
- SQLite queue adalah source of truth; Discord hanya progress/UI.

---

## 2. File Konfigurasi

Konfigurasi shared:

```text
config/agency/autonomous-routing.yaml
```

Saat setup VPS, file ini disalin ke:

```text
/var/lib/morph-agency/config/autonomous-routing.yaml
```

Policy per profile:

```text
config/hermes/profiles/orchestrator/discord-policy.yaml
config/hermes/profiles/researcher/discord-policy.yaml
config/hermes/profiles/executor/discord-policy.yaml
```

Saat setup VPS, policy disalin ke:

```text
/home/hermes/.hermes/profiles/<profile>/discord-policy.yaml
```

Env profile berisi pointer:

```bash
MORPH_AUTONOMOUS_MODE=orchestrated
MORPH_ROUTING_POLICY=/var/lib/morph-agency/config/autonomous-routing.yaml
MORPH_DISCORD_POLICY=/home/hermes/.hermes/profiles/<profile>/discord-policy.yaml
```

---

## 3. Setup di VPS

Jalankan urutan berikut setelah Hermes profiles dibuat:

```bash
cd /opt/ai-agent
sudo ./scripts/41-setup-hermes-profiles.sh
sudo ./scripts/42-seed-profile-souls.sh
sudo ./scripts/43-link-discord-channels.sh
sudo ./scripts/44-configure-agent-routing.sh
sudo ./scripts/55-setup-systemd-per-profile.sh
```

`44-configure-agent-routing.sh` akan:

- memasang `/var/lib/morph-agency/config/autonomous-routing.yaml`
- memasang `discord-policy.yaml` ke tiap profile
- menambahkan env autonomous ke profile `.env`
- memastikan tabel queue tambahan tersedia:
  - `task_events`
  - `task_results`
  - `agent_messages`

---

## 4. Lifecycle Service

Default yang aman:

```bash
sudo systemctl enable --now hermes-orchestrator-gateway
sudo systemctl disable --now hermes-researcher-gateway
sudo systemctl disable --now hermes-executor-gateway
```

Mode ini membuat orchestrator always-on, sementara worker dinyalakan saat dibutuhkan.

Jika ingin semua agent selalu auto-reply:

```bash
sudo systemctl enable --now hermes-researcher-gateway
sudo systemctl enable --now hermes-executor-gateway
```

Untuk kembali ke spawn-on-demand:

```bash
sudo systemctl disable --now hermes-researcher-gateway
sudo systemctl disable --now hermes-executor-gateway
```

---

## 5. Format Task Queue

Task minimal di tabel `tasks`:

```json
{
  "task_id": "abc123",
  "type": "research",
  "profile_target": "researcher",
  "payload": {
    "request": "Compare deployment options",
    "acceptance_criteria": ["sources cited", "recommendation included"],
    "reply_channel": "researcher"
  },
  "status": "pending",
  "priority": 0
}
```

Progress worker ditulis ke `task_events`:

```text
started -> progress_update -> blocked/succeeded/failed
```

Hasil final worker ditulis ke `task_results` dan/atau handoff file:

```text
/var/lib/morph-agency/handoff/<task-id>/
```

---

## 6. Format Pesan Discord Agent

Progress visible di channel worker:

```text
[task:abc123][researcher][progress] Reading official docs and comparing options.
```

Result visible:

```text
[task:abc123][researcher][result:partial] Findings written to handoff/abc123/report.md
```

Orchestrator final reply di `#orchestrator`:

```text
Task abc123 complete. Summary: ...
Researcher: ...
Executor: ...
Next step: ...
```

---

## 7. Guardrail Anti-Loop

Policy wajib:

| Rule | Tujuan |
| --- | --- |
| `orchestrator_is_only_task_assigner=true` | Worker tidak saling membuat task |
| `workers_may_not_delegate=true` | Mencegah recursive delegation |
| `require_task_id_for_agent_messages=true` | Mencegah bot merespons chatter umum |
| `ignore_unassigned_bot_messages=true` | Mencegah loop antar-bot |
| `max_reply_depth=3` | Membatasi chain Discord |

Jika agent menerima pesan bot tanpa `task_id`, respon yang benar adalah diam atau ringkasan singkat tanpa memicu agent lain.

---

## 8. Smoke Test

Cek routing policy terpasang:

```bash
sudo ls -l /var/lib/morph-agency/config/autonomous-routing.yaml
sudo ls -l /home/hermes/.hermes/profiles/orchestrator/discord-policy.yaml
```

Cek tabel queue:

```bash
sudo sqlite3 /var/lib/morph-agency/queue.db ".tables"
```

Harus ada:

```text
tasks profile_health task_events task_results agent_messages
```

Test Discord:

```text
@MorphOrchestrator buat task dummy untuk researcher: jelaskan peran kamu dalam 2 kalimat. Gunakan task_id test001.
```

Ekspektasi:

- Orchestrator menerima request di `#orchestrator`.
- Researcher hanya merespons jika task diarahkan ke `researcher`.
- Progress muncul di `#researcher`.
- Final summary kembali ke `#orchestrator`.

---

## 9. Troubleshooting

### Worker Tidak Merespons

Cek service:

```bash
sudo systemctl status hermes-researcher-gateway
sudo journalctl -u hermes-researcher-gateway -n 100 --no-pager
```

Cek policy:

```bash
sudo grep MORPH_ /home/hermes/.hermes/profiles/researcher/.env
```

### Bot Saling Reply Terus

Lakukan mitigasi cepat:

```bash
sudo systemctl stop hermes-researcher-gateway
sudo systemctl stop hermes-executor-gateway
```

Lalu cek:

- apakah worker menerima pesan dari bot selain orchestrator
- apakah pesan agent punya `task_id`
- apakah channel permission terlalu longgar
- apakah `max_reply_depth` di policy masih `3`

### Queue Tidak Ada Tabel Tambahan

Jalankan ulang:

```bash
sudo ./scripts/44-configure-agent-routing.sh
```

---

## 10. Production Recommendation

Rekomendasi production awal:

- `orchestrator`: always-on
- `researcher`: spawn-on-demand
- `executor`: spawn-on-demand
- komunikasi antar-agent: SQLite queue
- Discord: log, progress, escalation, final answer
- approval manusia: wajib untuk deploy, delete, protected branch push, package install, dan high-cost task

---

## 11. Strict Discord Addressing Model

This section exists because Discord threads can keep multiple bots as thread
participants. Participation history MUST NOT be treated as message addressing.

### Owner Channel Rule

Each profile has exactly one owner channel:

| Profile | Owner channel | Default responder when no bot is mentioned |
| --- | --- | --- |
| `orchestrator` | `#orchestrator` | Yes |
| `researcher` | `#researcher` | Yes, but only for task-scoped messages |
| `executor` | `#executor` | Yes, but only for task-scoped messages |

In a thread under `#orchestrator`, an unmentioned human message belongs to the
orchestrator only. Researcher/executor MUST stay silent even if they were
previously mentioned in the same thread.

### Mention Rule

If a human explicitly mentions a bot, only that bot responds.

Examples in an `#orchestrator` thread:

| Human message | Expected responders |
| --- | --- |
| `what is the status?` | `MorphOrchestrator` only |
| `@MorphResearcher find the latest docs` | `MorphResearcher` only |
| `@MorphExecutor apply the patch` | `MorphExecutor` only |
| `@MorphResearcher @MorphExecutor status?` | Both may respond only if each has a valid task context |
| `continue` after researcher was mentioned earlier | `MorphOrchestrator` only |

### Config Keys

Shared routing policy:

```yaml
discord:
  thread_addressing_mode: explicit_mention_only
  thread_participation_implies_addressing: false
  unmentioned_human_message_owner_only: true
  defer_when_other_agent_mentioned: true
  owner_channel_map:
    orchestrator: orchestrator
    researcher: researcher
    executor: executor
```

Per-profile policy:

```yaml
owner_channel: researcher
reply_only_in_owner_channel_or_when_mentioned: true
thread_addressing_mode: explicit_mention_only
reply_policy:
  require_mention_outside_owner_channel: true
  defer_when_other_agent_mentioned: true
```

Optional per-profile env variables:

```bash
DISCORD_OWNER_CHANNELS_ORCHESTRATOR=<channel_id_for_orchestrator>
DISCORD_OWNER_CHANNELS_RESEARCHER=<channel_id_for_researcher>
DISCORD_OWNER_CHANNELS_EXECUTOR=<channel_id_for_executor>
```

`DISCORD_OWNER_CHANNELS_*` means: "this bot is the default responder for
un-mentioned human messages in these channels." It does **not** mean the bot can
only be mentioned there. A correctly implemented gateway should still allow an
explicit `@MorphResearcher` or `@MorphExecutor` mention from any channel/thread
where the bot has Discord access.

If Hermes currently ignores one of these fields or env variables, the same
behavior is still reinforced in each profile's `SOUL.md`. For a hard technical
enforcement layer, implement these fields inside the Discord gateway event
filter before messages are sent to the model:

```text
if message does not mention this bot:
    allow only if parent_channel == this_bot.owner_channel
else:
    allow regardless of channel, subject to user allow-list and task policy
```

---

## 12. Preventing Internal Monologue Leaks

Agents MUST NOT post planning narration or scratchpad text to Discord. Examples
that must never appear as Discord messages:

```text
Need maybe env vars DISCORD_ALLOWED_CHANNELS? Search all relevant.
Need patch .env home channels and maybe researcher .env.
Good, clean done. No /tmp/beads* directories remain.
Good! Now let me also create a detailed written version for reference:
```

These lines are internal workflow narration. The user should only see structured
status, result, blocker, or clarifying question messages.

### Config hardening

Do **not** disable Hermes streaming entirely. In current Hermes gateway behavior,
`streaming.enabled: false` can result in Discord receiving only a reaction/ack and
no text reply. Keep the compatible edit transport enabled, and control message
quality through SOUL output discipline:

```yaml
display:
  streaming: true

streaming:
  enabled: true
  transport: edit
```

The intended behavior is one edited/updated Discord message per turn, not a silent
reaction-only acknowledgment.

### Recommended output contract

Workers should post at most:

```text
[task:<id>][researcher][progress] Reviewing official docs and source references.
[task:<id>][researcher][result:succeeded] Findings written to handoff/<task-id>.md.
```

Orchestrator should post one concise final message to the user after delegated
work is complete.

### Emergency mitigation

If agents start leaking internal narration again:

```bash
sudo systemctl stop hermes-researcher-gateway
sudo systemctl stop hermes-executor-gateway
sudo ./scripts/42-seed-profile-souls.sh
sudo ./scripts/44-configure-agent-routing.sh
sudo ./scripts/55-setup-systemd-per-profile.sh
```

Then restart only orchestrator first:

```bash
sudo systemctl restart hermes-orchestrator-gateway
```

Bring workers back only after a smoke test confirms the orchestrator is the only
unmentioned responder in `#orchestrator`.

---

## 13. Smoke Test for Discord Addressing

Create a thread under `#orchestrator`.

1. Send: `@MorphOrchestrator say OK only`
   - Expected: only MorphOrchestrator replies.
2. Send: `@MorphResearcher say RESEARCHER only`
   - Expected: only MorphResearcher replies.
3. Send without mention: `continue`
   - Expected: only MorphOrchestrator replies.
4. Send: `@MorphExecutor say EXECUTOR only`
   - Expected: only MorphExecutor replies.
5. Send without mention: `status?`
   - Expected: only MorphOrchestrator replies.

Failure means the Discord gateway is still using thread participation as
addressing. Apply the owner-channel filter before invoking Hermes.

---

## 14. Known Runtime Pitfalls from VPS Troubleshooting

### 14.1 9Router API Path Is `/api/v1`

For the current 9Router deployment used by this project, the OpenAI-compatible
API base URL is:

```bash
NINE_ROUTER_BASE_URL=http://127.0.0.1:20128/api/v1
```

Not:

```bash
NINE_ROUTER_BASE_URL=http://127.0.0.1:20128/v1
```

Validate models:

```bash
curl -i http://127.0.0.1:20128/api/v1/models \
  -H "Authorization: Bearer $NINE_ROUTER_API_KEY"
```

Validate chat:

```bash
curl -i http://127.0.0.1:20128/api/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $NINE_ROUTER_API_KEY" \
  -d '{
    "model": "morph-orchestrator",
    "messages": [{"role": "user", "content": "Reply exactly: OK"}],
    "max_tokens": 50
  }'
```

### 14.2 Model Combo Names Are Per Profile

This project expects one 9Router combo per active profile:

| Profile | 9Router combo |
| --- | --- |
| `orchestrator` | `morph-orchestrator` |
| `researcher` | `morph-researcher` |
| `executor` | `morph-executor` |

Set these in root `.env`:

```bash
HERMES_MODEL_ORCHESTRATOR=morph-orchestrator
HERMES_MODEL_RESEARCHER=morph-researcher
HERMES_MODEL_EXECUTOR=morph-executor
```

`scripts/42-seed-profile-souls.sh` injects each value into the matching profile.
It also hardcodes `model.default` in runtime `config.yaml` because some Hermes
gateway versions do not expand `${HERMES_MODEL}` in that field and will send the
literal string `${HERMES_MODEL}` to 9Router.

Symptom of this bug:

```text
model=${HERMES_MODEL} summary=HTTP 404: No active credentials for provider: openai
```

### 14.3 `DISCORD_ALLOWED_USERS` Should Be Explicit

Some Hermes gateway versions treat an empty `DISCORD_ALLOWED_USERS=` as deny-all,
not allow-all.

Symptom:

```text
Unauthorized user: <discord_user_id> (<name>) on discord
```

Fix:

```bash
sudo sed -i '/^DISCORD_ALLOWED_USERS=/c\DISCORD_ALLOWED_USERS=<your_discord_user_id>' \
  /home/hermes/.hermes/profiles/orchestrator/.env
```

Then restart the active gateway service.

### 14.4 User-Level vs System-Level Gateway Services

Two service naming schemes may exist during migration/troubleshooting:

| Type | Service name |
| --- | --- |
| User-level Hermes native | `hermes-gateway-orchestrator` |
| System-level project template | `hermes-orchestrator-gateway` |

Check which one is active before editing env/overrides:

```bash
sudo -u hermes XDG_RUNTIME_DIR=/run/user/$(id -u hermes) \
  systemctl --user status hermes-gateway-orchestrator --no-pager

sudo systemctl status hermes-orchestrator-gateway --no-pager
```

Inspect process environment for the active service:

```bash
UPID=$(sudo -u hermes XDG_RUNTIME_DIR=/run/user/$(id -u hermes) \
  systemctl --user show hermes-gateway-orchestrator --property=MainPID --value)

sudo cat /proc/$UPID/environ | tr '\0' '\n' | \
  grep -E "NINE_ROUTER|HERMES_MODEL|DISCORD_ALLOWED_USERS"
```

If both services are active, disable one to avoid two bots racing to handle the
same Discord events.

### 14.5 Rotate Leaked Credentials

If `DISCORD_BOT_TOKEN`, `NINE_ROUTER_API_KEY`, or provider API keys are pasted into
logs, chat, GitHub issues, or support channels, treat them as compromised and rotate
immediately.
