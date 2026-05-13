# Panduan Setup Discord Channel untuk Agent

Dokumen ini menjelaskan cara menyiapkan Discord server, channel, role, permission, dan bot token untuk agent Morph AI Agent: `orchestrator`, `researcher`, dan `executor`.

Untuk mode auto-reply dan komunikasi autonomous antar-agent, lihat `docs/AUTONOMOUS_DISCORD_AGENTS.md` setelah setup channel dan bot selesai.

---

## 1. Target Struktur Discord

Struktur channel yang direkomendasikan:

```text
Morph AI Agency
├── 📌 control
│   ├── #orchestrator
│   ├── #status
│   └── #escalation
├── 🤖 agents
│   ├── #researcher
│   └── #executor
└── 🧾 archive
    ├── #task-archive
    └── #incident-log
```

Minimal channel yang wajib dibuat:

| Channel | Wajib | Fungsi |
| --- | --- | --- |
| `#orchestrator` | Ya | Interface utama user ke Orchestrator |
| `#researcher` | Ya | Output research, analisis, dan scouting teknologi |
| `#executor` | Ya | Output eksekusi coding, build, test, dan git workflow |
| `#status` | Disarankan | Ringkasan status task dan heartbeat agent |
| `#escalation` | Disarankan | Approval manual untuk aksi sensitif |
| `#task-archive` | Opsional | Arsip hasil task selesai |
| `#incident-log` | Opsional | Log insiden, failure, atau debugging production |

---

## 2. Pola Bot yang Direkomendasikan

Gunakan **satu Discord bot per profile agent** agar isolasi channel dan token lebih jelas.

| Agent Profile | Bot Name | Channel Utama | Env Var |
| --- | --- | --- | --- |
| `orchestrator` | `MorphOrchestrator` | `#orchestrator` | `DISCORD_BOT_TOKEN_ORCHESTRATOR` |
| `researcher` | `MorphResearcher` | `#researcher` | `DISCORD_BOT_TOKEN_RESEARCHER` |
| `executor` | `MorphExecutor` | `#executor` | `DISCORD_BOT_TOKEN_EXECUTOR` |

Alternatif satu bot shared memungkinkan, tetapi tidak direkomendasikan untuk setup awal karena permission dan debugging lebih sulit dipisahkan.

---

## 3. Buat Role Discord

Di Discord server, buat role berikut:

| Role | Untuk | Permission Umum |
| --- | --- | --- |
| `Agency Admin` | Human admin | Full access ke semua channel agency |
| `Agency Operator` | User yang boleh memberi task | Read/send di `#orchestrator`, read di channel agent |
| `Morph Orchestrator` | Bot `MorphOrchestrator` | Send/read di control dan agent channels |
| `Morph Researcher` | Bot `MorphResearcher` | Send/read di `#researcher`, read limited di `#orchestrator` |
| `Morph Executor` | Bot `MorphExecutor` | Send/read di `#executor`, read limited di `#orchestrator` |

Permission role bot yang biasanya diperlukan:

- View Channel
- Send Messages
- Send Messages in Threads
- Create Public Threads
- Read Message History
- Add Reactions
- Embed Links
- Attach Files
- Use Slash Commands, jika Hermes gateway mendukung command interaction
- Mention Everyone **off** kecuali benar-benar diperlukan
- Manage Channels **off** untuk setup awal
- Administrator **off** untuk production

---

## 4. Buat Channel dan Permission

### 4.1 `#orchestrator`

Channel utama untuk user mengirim task.

Rekomendasi akses:

| Role | Access |
| --- | --- |
| `Agency Admin` | Read + Send |
| `Agency Operator` | Read + Send |
| `Morph Orchestrator` | Read + Send + Threads |
| `Morph Researcher` | Read only atau no access |
| `Morph Executor` | Read only atau no access |

Gunakan channel ini untuk request seperti:

```text
@MorphOrchestrator buat REST API auth dengan JWT, PostgreSQL, dan test coverage minimal 80%.
```

### 4.2 `#researcher`

Channel untuk hasil research dan analisis.

Rekomendasi akses:

| Role | Access |
| --- | --- |
| `Agency Admin` | Read + Send |
| `Agency Operator` | Read only |
| `Morph Orchestrator` | Read + Send |
| `Morph Researcher` | Read + Send + Threads |
| `Morph Executor` | Read only |

### 4.3 `#executor`

Channel untuk output coding, build, test, dan git workflow.

Rekomendasi akses:

| Role | Access |
| --- | --- |
| `Agency Admin` | Read + Send |
| `Agency Operator` | Read only |
| `Morph Orchestrator` | Read + Send |
| `Morph Researcher` | Read only |
| `Morph Executor` | Read + Send + Threads |

### 4.4 `#status`

Channel status ringkas, idealnya read-only untuk user umum.

Rekomendasi akses:

| Role | Access |
| --- | --- |
| `Agency Admin` | Read + Send |
| `Agency Operator` | Read only |
| `Morph Orchestrator` | Read + Send |
| `Morph Researcher` | Read + Send |
| `Morph Executor` | Read + Send |

### 4.5 `#escalation`

Channel approval manual untuk aksi berisiko.

Rekomendasi akses:

| Role | Access |
| --- | --- |
| `Agency Admin` | Read + Send |
| `Agency Operator` | Read + Send, jika boleh approve |
| `Morph Orchestrator` | Read + Send |
| `Morph Researcher` | No access atau read only |
| `Morph Executor` | No access atau read only |

Gunakan channel ini untuk approval seperti deploy production, delete file, push ke protected branch, atau install package system.

---

## 5. Buat Bot di Discord Developer Portal

Ulangi langkah ini untuk setiap bot: `MorphOrchestrator`, `MorphResearcher`, dan `MorphExecutor`.

1. Buka Discord Developer Portal.
2. Pilih **New Application**.
3. Isi nama application, contoh `MorphOrchestrator`.
4. Masuk ke menu **Bot**.
5. Klik **Add Bot** jika bot belum dibuat.
6. Reset/copy bot token.
7. Simpan token ke tempat aman sementara, lalu masukkan ke `.env` di VPS.

Aktifkan intent sesuai kebutuhan gateway Hermes. Untuk bot yang membaca isi pesan biasa, biasanya diperlukan:

- Server Members Intent, jika gateway perlu membaca/memberi konteks member
- Message Content Intent, jika gateway membaca isi message non-slash-command

Jika Hermes hanya memakai slash command atau interaction, `Message Content Intent` mungkin tidak wajib. Untuk setup awal, aktifkan `Message Content Intent` agar natural language mention di channel dapat diproses.

---

## 6. Invite Bot ke Server

Di setiap application bot:

1. Buka menu **OAuth2**.
2. Buka **URL Generator**.
3. Pilih scopes:

```text
bot
applications.commands
```

4. Pilih bot permissions minimum:

```text
View Channels
Send Messages
Send Messages in Threads
Create Public Threads
Read Message History
Add Reactions
Embed Links
Attach Files
Use Slash Commands
```

5. Copy generated URL.
6. Buka URL tersebut dan invite bot ke server.
7. Assign role yang sesuai ke bot:

| Bot | Role |
| --- | --- |
| `MorphOrchestrator` | `Morph Orchestrator` |
| `MorphResearcher` | `Morph Researcher` |
| `MorphExecutor` | `Morph Executor` |

---

## 7. Konfigurasi `.env` di VPS

Edit env repository:

```bash
cd /opt/ai-agent
nano .env
```

Isi token bot:

```bash
DISCORD_BOT_TOKEN_ORCHESTRATOR=<token-morph-orchestrator>
DISCORD_BOT_TOKEN_RESEARCHER=<token-morph-researcher>
DISCORD_BOT_TOKEN_EXECUTOR=<token-morph-executor>
```

Pastikan permission `.env` aman:

```bash
chmod 600 /opt/ai-agent/.env
```

Link token ke profile Hermes:

```bash
cd /opt/ai-agent
sudo ./scripts/43-link-discord-channels.sh
```

Skrip ini akan menulis `DISCORD_BOT_TOKEN` ke masing-masing profile env:

```text
/home/hermes/.hermes/profiles/orchestrator/.env
/home/hermes/.hermes/profiles/researcher/.env
/home/hermes/.hermes/profiles/executor/.env
```

---

## 8. Start Gateway Agent

Setup systemd per profile:

```bash
cd /opt/ai-agent
sudo ./scripts/55-setup-systemd-per-profile.sh
```

Behavior default:

- `hermes-orchestrator-gateway` enabled dan started jika token orchestrator tersedia.
- `hermes-researcher-gateway` dibuat tapi disabled.
- `hermes-executor-gateway` dibuat tapi disabled.

Cek orchestrator:

```bash
sudo systemctl status hermes-orchestrator-gateway
sudo journalctl -u hermes-orchestrator-gateway -f
```

Jika ingin menyalakan worker secara manual:

```bash
sudo systemctl start hermes-researcher-gateway
sudo systemctl start hermes-executor-gateway
```

Jika ingin worker always-on, enable service:

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

## 9. Smoke Test Discord

### 9.1 Cek Bot Online

Di Discord server, pastikan bot muncul online:

- `MorphOrchestrator`
- `MorphResearcher`, jika service sedang running
- `MorphExecutor`, jika service sedang running

Jika bot offline, cek log:

```bash
sudo journalctl -u hermes-orchestrator-gateway -n 100 --no-pager
```

### 9.2 Test Orchestrator

Kirim di `#orchestrator`:

```text
@MorphOrchestrator reply exactly: OK
```

Ekspektasi:

```text
OK
```

### 9.3 Test Researcher

Jika researcher gateway sedang running, kirim di `#researcher`:

```text
@MorphResearcher jelaskan secara singkat tugas utama kamu.
```

### 9.4 Test Executor

Jika executor gateway sedang running, kirim di `#executor`:

```text
@MorphExecutor jelaskan secara singkat tugas utama kamu.
```

---

## 10. Checklist Setup

Gunakan checklist ini sebelum production:

- [ ] Server Discord sudah dibuat atau channel agency sudah dibuat di server existing.
- [ ] Category `control`, `agents`, dan `archive` sudah dibuat jika diperlukan.
- [ ] Channel `#orchestrator`, `#researcher`, `#executor`, `#status`, dan `#escalation` sudah dibuat.
- [ ] Role `Agency Admin`, `Agency Operator`, `Morph Orchestrator`, `Morph Researcher`, dan `Morph Executor` sudah dibuat.
- [ ] Permission setiap channel sudah sesuai isolasi agent.
- [ ] Bot `MorphOrchestrator`, `MorphResearcher`, dan `MorphExecutor` sudah dibuat di Developer Portal.
- [ ] Bot token sudah dimasukkan ke `/opt/ai-agent/.env`.
- [ ] `sudo ./scripts/43-link-discord-channels.sh` sudah dijalankan.
- [ ] `sudo ./scripts/55-setup-systemd-per-profile.sh` sudah dijalankan.
- [ ] `MorphOrchestrator` online dan merespons di `#orchestrator`.
- [ ] Worker bot hanya dinyalakan sesuai strategi lifecycle: spawn-on-demand atau always-on.
- [ ] `#escalation` hanya bisa diakses oleh human yang boleh approve aksi berisiko.

---

## 11. Troubleshooting

### Bot Offline

Cek service:

```bash
sudo systemctl status hermes-orchestrator-gateway
sudo journalctl -u hermes-orchestrator-gateway -n 100 --no-pager
```

Pastikan token sudah masuk ke profile env:

```bash
sudo grep '^DISCORD_BOT_TOKEN=' /home/hermes/.hermes/profiles/orchestrator/.env
```

Jika token berubah, jalankan ulang:

```bash
sudo ./scripts/43-link-discord-channels.sh
sudo systemctl restart hermes-orchestrator-gateway
```

### Bot Online tapi Tidak Merespons

Periksa:

- Bot punya permission `View Channel`, `Send Messages`, dan `Read Message History`.
- `Message Content Intent` aktif jika memakai pesan natural language.
- User mention bot yang benar, misalnya `@MorphOrchestrator`.
- Bot berada di channel yang benar.
- Log gateway tidak menunjukkan error LLM atau Discord API.

### Bot Menjawab di Channel yang Salah

Periksa permission channel dan role bot. Untuk isolasi ketat:

- `MorphOrchestrator` hanya send di `#orchestrator`, `#status`, `#escalation`, dan read/send terbatas di channel worker.
- `MorphResearcher` hanya send di `#researcher` dan `#status`.
- `MorphExecutor` hanya send di `#executor` dan `#status`.

### Token Bocor

Segera lakukan:

1. Reset token di Discord Developer Portal.
2. Update `/opt/ai-agent/.env`.
3. Jalankan ulang link script:

```bash
sudo ./scripts/43-link-discord-channels.sh
```

4. Restart service terkait:

```bash
sudo systemctl restart hermes-orchestrator-gateway
sudo systemctl restart hermes-researcher-gateway
sudo systemctl restart hermes-executor-gateway
```

---

## 12. Rekomendasi Production

- Jangan beri permission `Administrator` ke bot.
- Gunakan satu bot token per agent profile.
- Batasi `#escalation` hanya untuk admin/operator yang boleh approve.
- Simpan token hanya di `.env` VPS dan profile `.env`, bukan di chat atau Git.
- Gunakan thread untuk task multi-step agar channel utama tetap bersih.
- Arsipkan task selesai ke `#task-archive` jika output penting untuk audit.
- Review permission channel setiap kali menambah agent profile baru.
