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
