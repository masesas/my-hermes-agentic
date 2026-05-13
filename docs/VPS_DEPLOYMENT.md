# Panduan Deploy VPS Morph AI Agent

Dokumen ini menjelaskan langkah demi langkah konfigurasi dan deployment Morph AI Agent di VPS Ubuntu 22.04. Panduan ini mengikuti skrip yang tersedia di folder `scripts/` dan target runtime yang dijelaskan di `AGENTS.md`.

> Jangan jalankan skrip deployment ini di laptop lokal kecuali mesin lokal tersebut memang target VPS.

---

## 1. Gambaran Deployment

Stack yang akan dipasang:

- **9Router** sebagai OpenAI-compatible LLM gateway di `127.0.0.1:20128`
- **Nginx** sebagai reverse proxy HTTPS publik jika VPS sudah memakai Nginx (`WEB_SERVER=nginx-direct`)
- **Caddy** sebagai opsi reverse proxy HTTPS publik jika VPS belum memakai Nginx (`WEB_SERVER=caddy`)
- **Hermes Agent** dengan profil `orchestrator`, `researcher`, dan `executor`
- **systemd** untuk service 9Router dan gateway Hermes
- **SQLite task queue** di `/var/lib/morph-agency/queue.db`
- **Discord bots** sebagai interface manusia ke tiap profil agent

Alur request:

```text
Discord / SSH CLI
  -> Hermes profile
  -> https://<PUBLIC_DOMAIN>/v1
  -> Nginx atau Caddy
  -> 9Router localhost:20128
  -> Provider LLM
```

---

## 2. Prasyarat

Pastikan tersedia:

- VPS Ubuntu 22.04 LTS
- Akses root atau user dengan `sudo`
- Domain/subdomain, misalnya `ai.example.com`
- DNS `A` record domain sudah mengarah ke IP publik VPS
- Port inbound terbuka: `22`, `80`, `443`
- Port `20128` **tidak** dibuka ke internet
- Minimal rekomendasi VPS: 2 vCPU, 4 GB RAM, 80 GB storage
- Token Discord bot untuk setiap profil, jika ingin multi-agent Discord:
  - `orchestrator`
  - `researcher`
  - `executor`
- API key provider LLM yang akan dikonfigurasi di dashboard 9Router

Validasi DNS dari komputer lokal:

```bash
dig +short ai.example.com
```

Output harus menunjukkan IP publik VPS.

---

## 3. Persiapan Awal VPS

Login ke VPS:

```bash
ssh root@<IP_VPS>
```

Update package dasar:

```bash
apt-get update
apt-get upgrade -y
```

Install `git` jika belum ada:

```bash
apt-get install -y git
```

Clone repository ke `/opt/ai-agent`:

```bash
cd /opt
git clone <REPO_URL> ai-agent
cd /opt/ai-agent
```

Jika repository sudah ada:

```bash
cd /opt/ai-agent
git pull --ff-only
```

---

## 4. Konfigurasi Environment

Salin template `.env`:

```bash
cp .env.example .env
nano .env
```

Isi nilai berikut:

```bash
PUBLIC_DOMAIN=ai.example.com
PUBLIC_BASE_URL=https://ai.example.com
ADMIN_EMAIL=admin@example.com
WEB_SERVER=nginx-direct

NINE_ROUTER_INITIAL_PASSWORD=<password-dashboard-yang-kuat>
NINE_ROUTER_JWT_SECRET=<secret-random-panjang>
NINE_ROUTER_API_KEY_SECRET=<secret-random-panjang>
NINE_ROUTER_MACHINE_ID_SALT=<secret-random-panjang>
NINE_ROUTER_NODE_BIN=
NINE_ROUTER_NPM_BIN=

NINE_ROUTER_API_KEY=
NINE_ROUTER_BASE_URL=https://ai.example.com/v1

HERMES_MODEL=orchestrator/powerful

DISCORD_BOT_TOKEN_ORCHESTRATOR=
DISCORD_BOT_TOKEN_RESEARCHER=
DISCORD_BOT_TOKEN_EXECUTOR=

HERMES_USER=hermes
HERMES_AGENT_NAME=hermes-orchestrator
```

Buat secret random, contoh:

```bash
openssl rand -hex 32
```

Amankan permission `.env`:

```bash
chmod 600 .env
```

Catatan penting:

- `NINE_ROUTER_API_KEY` dikosongkan dulu karena dibuat setelah dashboard 9Router aktif.
- `HERMES_MODEL` harus sesuai alias/combo yang nanti dibuat di 9Router.
- Gunakan `WEB_SERVER=nginx-direct` jika VPS sudah memakai Nginx sebagai load balancer/webserver.
- Gunakan `WEB_SERVER=caddy` hanya jika ingin repo ini mengelola Caddy di port publik `80/443`.
- Isi `NINE_ROUTER_NODE_BIN` dan `NINE_ROUTER_NPM_BIN` hanya jika setup NVM membuat skrip atau systemd salah memakai Node lama.
- Jangan commit `.env` ke Git.

---

## 5. Jalankan Preflight

Validasi OS dan env minimum:

```bash
sudo ./scripts/00-preflight.sh
```

Skrip ini memastikan:

- OS adalah Ubuntu 22.04
- `sudo` dan `systemd` tersedia
- variabel `PUBLIC_DOMAIN`, `PUBLIC_BASE_URL`, dan `ADMIN_EMAIL` sudah terisi

Jika gagal, perbaiki pesan error terlebih dahulu sebelum lanjut.

---

## 6. Install Dependency Sistem

Jalankan:

```bash
sudo ./scripts/10-install-system-deps.sh
```

Skrip ini memasang:

- package dasar: `curl`, `git`, `jq`, `ufw`, `build-essential`, `ripgrep`, `sqlite3`, `unzip`
- Node.js 20 jika belum tersedia
- Caddy jika `WEB_SERVER=caddy`; jika `WEB_SERVER=nginx-direct`, instalasi Caddy akan diskip
- UFW rules untuk `OpenSSH`, `80/tcp`, dan `443/tcp`

Cek firewall:

```bash
sudo ufw status
```

---

## 7. Install dan Build 9Router

Jalankan:

```bash
sudo ./scripts/20-install-9router.sh
```

Skrip ini akan:

- membuat user sistem `router9`
- clone/update 9Router ke `/opt/9router/app`
- install dependency Node.js
- build aplikasi 9Router
- memilih Node.js `>=20.9.0` secara eksplisit, termasuk dari NVM root atau user `agentic` jika tersedia
- membuat wrapper `/opt/9router/bin/npm-run` dan `/opt/9router/bin/npm-start` agar build dan systemd tidak jatuh ke Node lama
- membuat env runtime di `/etc/9router/9router.env`
- menyiapkan data directory `/var/lib/9router`

Pastikan tidak ada error build sebelum lanjut.

Jika muncul error seperti:

```text
You are using Node.js 19.7.0. For Next.js, Node.js version ">=20.9.0" is required.
```

set path Node/NPM NVM secara eksplisit di `.env`, contoh:

```bash
NINE_ROUTER_NODE_BIN=/root/.nvm/versions/node/v24.0.0/bin/node
NINE_ROUTER_NPM_BIN=/root/.nvm/versions/node/v24.0.0/bin/npm
```

Lalu jalankan ulang:

```bash
sudo ./scripts/20-install-9router.sh
sudo ./scripts/50-setup-systemd.sh
```

---

## 8. Install Service systemd untuk 9Router

Jalankan:

```bash
sudo ./scripts/50-setup-systemd.sh
```

Skrip ini menginstal unit systemd dari folder `systemd/`, lalu mengaktifkan service yang diperlukan.

Cek status 9Router:

```bash
sudo systemctl status 9router
```

Cek log jika ada masalah:

```bash
sudo journalctl -u 9router -f
```

---

## 9. Konfigurasi Web Server Publik

Pilih salah satu mode sesuai kondisi VPS.

### Opsi A: Nginx Direct

Gunakan opsi ini jika VPS sudah memakai Nginx sebagai load balancer dan webserver. Ini adalah mode yang direkomendasikan untuk setup Anda.

Pastikan `.env` berisi:

```bash
WEB_SERVER=nginx-direct
PUBLIC_DOMAIN=ai.example.com
PUBLIC_BASE_URL=https://ai.example.com
NINE_ROUTER_BASE_URL=https://ai.example.com/v1
```

Jalankan skrip Caddy tetap aman dilakukan; skrip akan mendeteksi `WEB_SERVER=nginx-direct` dan skip setup Caddy:

```bash
sudo ./scripts/60-setup-caddy.sh
```

Tambahkan server block Nginx untuk domain agent, contoh:

```nginx
server {
    listen 80;
    server_name ai.example.com;

    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ai.example.com;

    ssl_certificate /etc/letsencrypt/live/ai.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/ai.example.com/privkey.pem;

    client_max_body_size 50m;

    location / {
        proxy_pass http://127.0.0.1:20128;
        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

Jika TLS Anda dikelola oleh load balancer lain atau Cloudflare, sesuaikan bagian `ssl_certificate` dengan setup yang sudah ada.

Validasi dan reload Nginx:

```bash
sudo nginx -t
sudo systemctl reload nginx
```

Buka dashboard:

```text
https://ai.example.com/dashboard
```

Jika dashboard belum bisa dibuka:

- pastikan Nginx server block aktif
- pastikan TLS certificate valid
- pastikan Nginx bisa mengakses `127.0.0.1:20128`
- cek log Nginx dan 9Router

```bash
sudo journalctl -u nginx -f
sudo journalctl -u 9router -f
```

### Opsi B: Caddy HTTPS

Gunakan opsi ini hanya jika VPS belum memakai Nginx di port `80/443`.

Pastikan `.env` berisi:

```bash
WEB_SERVER=caddy
```

Jalankan:

```bash
sudo ./scripts/60-setup-caddy.sh
```

Skrip ini akan:

- render template `config/caddy/Caddyfile`
- validasi konfigurasi Caddy
- memasang ke `/etc/caddy/Caddyfile`
- reload atau restart Caddy

Cek status Caddy:

```bash
sudo systemctl status caddy
```

Buka dashboard:

```text
https://ai.example.com/dashboard
```

Jika HTTPS belum aktif:

- pastikan DNS sudah mengarah ke VPS
- pastikan port `80` dan `443` terbuka
- cek log Caddy:

```bash
sudo journalctl -u caddy -f
```

---

## 10. Konfigurasi 9Router Dashboard

Masuk ke dashboard:

```text
https://ai.example.com/dashboard
```

Login menggunakan `NINE_ROUTER_INITIAL_PASSWORD` dari `.env`.

Di dashboard 9Router:

1. Tambahkan provider LLM yang ingin digunakan.
2. Masukkan API key provider.
3. Buat alias/combo sesuai kebutuhan agent.
4. Minimal buat combo yang sama dengan `.env`:

```text
orchestrator/powerful
```

Rekomendasi combo:

| Combo | Kegunaan | Contoh routing |
| --- | --- | --- |
| `combo:premium` atau `orchestrator/powerful` | planning, arsitektur, synthesis | model terkuat + fallback |
| `combo:balanced` | research dan analisis umum | model menengah |
| `combo:budget` | eksekusi rutin, coding sederhana | model hemat |

Buat API key untuk Hermes dari dashboard 9Router, lalu update `.env`:

```bash
nano /opt/ai-agent/.env
```

Isi:

```bash
NINE_ROUTER_API_KEY=<api-key-dari-dashboard-9router>
```

Simpan dan pastikan permission tetap aman:

```bash
chmod 600 /opt/ai-agent/.env
```

Tes endpoint model:

```bash
source /opt/ai-agent/.env
curl -fsS "https://${PUBLIC_DOMAIN}/v1/models" \
  -H "Authorization: Bearer ${NINE_ROUTER_API_KEY}" | jq .
```

---

## 11. Install Hermes Agent

Jalankan:

```bash
sudo ./scripts/30-install-hermes.sh
```

Skrip ini akan memasang Hermes dan membuat user runtime sesuai `HERMES_USER`, default:

```text
hermes
```

Cek binary Hermes:

```bash
command -v hermes
```

---

## 12. Setup Profil Orchestrator Legacy

Untuk kompatibilitas mode single orchestrator, jalankan:

```bash
sudo ./scripts/40-setup-hermes-orchestrator.sh
```

Skrip ini membutuhkan:

- `NINE_ROUTER_API_KEY`
- `NINE_ROUTER_BASE_URL`
- `HERMES_MODEL`

Hasil utamanya adalah konfigurasi Hermes dasar untuk orchestrator.

---

## 13. Setup Multi-Agent Profiles

Buat profil `orchestrator`, `researcher`, dan `executor`:

```bash
sudo ./scripts/41-setup-hermes-profiles.sh
```

Skrip ini akan:

- membuat Hermes profiles di `/home/hermes/.hermes/profiles/<profile>`
- membuat direktori shared di `/var/lib/morph-agency/`
- membuat SQLite queue di `/var/lib/morph-agency/queue.db`

Seed SOUL dan config per profile:

```bash
sudo ./scripts/42-seed-profile-souls.sh
```

Skrip ini menyalin konfigurasi dari:

```text
config/hermes/profiles/<name>/
```

ke:

```text
/home/hermes/.hermes/profiles/<name>/
```

Pasang routing autonomous dan policy anti-loop untuk komunikasi antar-agent:

```bash
sudo ./scripts/44-configure-agent-routing.sh
```

Untuk detail mode autonomous Discord, lihat:

```text
docs/AUTONOMOUS_DISCORD_AGENTS.md
```

---

## 14. Konfigurasi Discord Bots

Untuk panduan lengkap membuat server/channel/role dan invite bot Discord, lihat:

```text
docs/DISCORD_SETUP.md
```

Di Discord Developer Portal:

1. Buat application/bot untuk `MorphOrchestrator`.
2. Buat application/bot untuk `MorphResearcher`.
3. Buat application/bot untuk `MorphExecutor`.
4. Invite bot ke server Discord Anda.
5. Buat channel:

```text
#orchestrator
#researcher
#executor
```

6. Berikan permission bot hanya ke channel yang sesuai jika ingin isolasi ketat.

Update `.env`:

```bash
nano /opt/ai-agent/.env
```

Isi token:

```bash
DISCORD_BOT_TOKEN_ORCHESTRATOR=<token-bot-orchestrator>
DISCORD_BOT_TOKEN_RESEARCHER=<token-bot-researcher>
DISCORD_BOT_TOKEN_EXECUTOR=<token-bot-executor>
```

Link token ke masing-masing profile:

```bash
sudo ./scripts/43-link-discord-channels.sh
```

Catatan:

- Skrip ini hanya memasukkan token ke `.env` profile Hermes.
- Pembuatan channel, invite bot, dan permission tetap dilakukan manual di Discord.

---

## 15. Setup systemd Per Profile

Jalankan:

```bash
sudo ./scripts/55-setup-systemd-per-profile.sh
```

Skrip ini akan membuat unit:

```text
hermes-orchestrator-gateway.service
hermes-researcher-gateway.service
hermes-executor-gateway.service
```

Behavior default:

- `orchestrator` di-enable dan start otomatis jika `DISCORD_BOT_TOKEN_ORCHESTRATOR` tersedia
- `researcher` dan `executor` dibuat tetapi tidak otomatis aktif karena spawn-on-demand

Cek status orchestrator:

```bash
sudo systemctl status hermes-orchestrator-gateway
```

Start researcher atau executor secara manual saat dibutuhkan:

```bash
sudo systemctl start hermes-researcher-gateway
sudo systemctl start hermes-executor-gateway
```

Stop worker setelah selesai:

```bash
sudo systemctl stop hermes-researcher-gateway
sudo systemctl stop hermes-executor-gateway
```

---

## 16. Jalankan Health Check

Jalankan doctor:

```bash
sudo ./scripts/90-doctor.sh
```

Health check mencakup:

- service systemd utama
- keberadaan profile Hermes
- unit systemd per profile
- akses SQLite queue
- direktori shared `/var/lib/morph-agency`
- disk usage
- endpoint 9Router `/v1/models`
- smoke test Hermes LLM jika env tersedia

Jika gagal, baca pesan error dan cek log service terkait.

---

## 17. Smoke Test Manual

Tes 9Router lokal dari VPS:

```bash
source /opt/ai-agent/.env
curl -fsS http://127.0.0.1:20128/v1/models \
  -H "Authorization: Bearer ${NINE_ROUTER_API_KEY}" | jq .
```

Tes 9Router publik:

```bash
source /opt/ai-agent/.env
curl -fsS "https://${PUBLIC_DOMAIN}/v1/models" \
  -H "Authorization: Bearer ${NINE_ROUTER_API_KEY}" | jq .
```

Tes Hermes one-shot:

```bash
sudo -iu hermes hermes -p orchestrator -z "Reply exactly: OK"
```

Tes Discord:

1. Buka channel `#orchestrator`.
2. Kirim pesan singkat, misalnya:

```text
ping. reply exactly OK
```

3. Cek log jika bot tidak merespons:

```bash
sudo journalctl -u hermes-orchestrator-gateway -f
```

---

## 18. Menjalankan Semua Skrip Otomatis

Repository juga menyediakan runner:

```bash
sudo ./scripts/99-run-all.sh --dry-run
```

Jika urutan sudah sesuai, Anda bisa menjalankan:

```bash
sudo ./scripts/99-run-all.sh
```

Namun untuk setup pertama, disarankan menjalankan manual bertahap karena ada langkah dashboard 9Router yang harus dilakukan di tengah proses.

Contoh menjalankan subset:

```bash
sudo ./scripts/99-run-all.sh --only 00-preflight.sh --only 90-doctor.sh
```

---

## 19. Operasional Harian

Status service:

```bash
sudo systemctl status 9router
sudo systemctl status caddy
sudo systemctl status hermes-orchestrator-gateway
```

Log service:

```bash
sudo journalctl -u 9router -f
sudo journalctl -u caddy -f
sudo journalctl -u hermes-orchestrator-gateway -f
```

Restart service:

```bash
sudo systemctl restart 9router
sudo systemctl restart caddy
sudo systemctl restart hermes-orchestrator-gateway
```

Masuk sebagai user Hermes:

```bash
sudo -iu hermes
```

Chat CLI dengan profile:

```bash
hermes -p orchestrator chat
```

One-shot prompt:

```bash
hermes -p orchestrator -z "Buat ringkasan status sistem."
```

---

## 20. Update Deployment

Untuk update repository dan re-apply config:

```bash
cd /opt/ai-agent
git pull --ff-only
sudo ./scripts/42-seed-profile-souls.sh
sudo ./scripts/44-configure-agent-routing.sh
sudo ./scripts/55-setup-systemd-per-profile.sh
sudo ./scripts/60-setup-caddy.sh
sudo ./scripts/90-doctor.sh
```

Jika ada perubahan dependency 9Router:

```bash
sudo ./scripts/20-install-9router.sh
sudo systemctl restart 9router
```

---

## 21. Troubleshooting

### Dashboard tidak bisa dibuka

Cek DNS:

```bash
dig +short ai.example.com
```

Cek Caddy:

```bash
sudo caddy validate --config /etc/caddy/Caddyfile
sudo journalctl -u caddy -n 100 --no-pager
```

Cek service 9Router:

```bash
sudo systemctl status 9router
sudo journalctl -u 9router -n 100 --no-pager
```

### 9Router `/v1/models` gagal

Cek env API key:

```bash
grep '^NINE_ROUTER_API_KEY=' /opt/ai-agent/.env
```

Cek local endpoint:

```bash
source /opt/ai-agent/.env
curl -v http://127.0.0.1:20128/v1/models \
  -H "Authorization: Bearer ${NINE_ROUTER_API_KEY}"
```

### Hermes tidak menjawab

Cek profile ada:

```bash
ls -la /home/hermes/.hermes/profiles/
```

Cek env profile:

```bash
sudo ls -la /home/hermes/.hermes/profiles/orchestrator/
```

Cek log gateway:

```bash
sudo journalctl -u hermes-orchestrator-gateway -n 100 --no-pager
```

Tes tanpa Discord:

```bash
sudo -iu hermes hermes -p orchestrator -z "Reply exactly: OK"
```

### Discord bot tidak online

Pastikan:

- token bot benar dan belum di-rotate
- bot sudah di-invite ke server
- intent dan permission Discord sesuai kebutuhan Hermes gateway
- `DISCORD_BOT_TOKEN_ORCHESTRATOR` sudah terisi di `/opt/ai-agent/.env`
- `sudo ./scripts/43-link-discord-channels.sh` sudah dijalankan ulang setelah token diubah
- service sudah direstart:

```bash
sudo systemctl restart hermes-orchestrator-gateway
```

---

## 22. Keamanan

Checklist minimum:

- Jangan expose `127.0.0.1:20128` ke internet.
- Gunakan Nginx atau Caddy sebagai reverse proxy HTTPS publik.
- Jika memakai `WEB_SERVER=nginx-direct`, pastikan Nginx hanya proxy ke `127.0.0.1:20128` dan tidak membuka port `20128` publik.
- Simpan secret hanya di `.env` dan file env runtime, bukan di Git.
- Permission file secret harus `600`.
- Gunakan secret random panjang untuk semua `NINE_ROUTER_*_SECRET`.
- Rotasi `NINE_ROUTER_API_KEY` jika pernah bocor ke chat atau log.
- Batasi akses SSH, idealnya gunakan SSH key dan disable password login.
- Backup `/var/lib/morph-agency/queue.db` jika task queue mulai berisi data penting.

---

## 23. Urutan Cepat Deployment Pertama

Ringkasan perintah utama:

```bash
cd /opt
git clone <REPO_URL> ai-agent
cd /opt/ai-agent
cp .env.example .env
nano .env
chmod 600 .env

sudo ./scripts/00-preflight.sh
sudo ./scripts/10-install-system-deps.sh
sudo ./scripts/20-install-9router.sh
sudo ./scripts/50-setup-systemd.sh
sudo ./scripts/60-setup-caddy.sh
```

Jika memakai `WEB_SERVER=nginx-direct`, perintah `60-setup-caddy.sh` hanya melakukan skip aman. Setelah itu pasang atau update server block Nginx agar domain agent proxy ke `http://127.0.0.1:20128`.

Lalu buka dashboard:

```text
https://<PUBLIC_DOMAIN>/dashboard
```

Konfigurasi provider, combo, dan API key. Setelah itu:

```bash
nano .env

sudo ./scripts/30-install-hermes.sh
sudo ./scripts/40-setup-hermes-orchestrator.sh
sudo ./scripts/41-setup-hermes-profiles.sh
sudo ./scripts/42-seed-profile-souls.sh
sudo ./scripts/43-link-discord-channels.sh
sudo ./scripts/44-configure-agent-routing.sh
sudo ./scripts/55-setup-systemd-per-profile.sh
sudo ./scripts/90-doctor.sh
```

Deployment dianggap berhasil jika:

- `sudo ./scripts/90-doctor.sh` tidak menunjukkan failure kritis
- `https://<PUBLIC_DOMAIN>/dashboard` bisa dibuka
- endpoint `/v1/models` mengembalikan model list
- `hermes -p orchestrator -z "Reply exactly: OK"` menjawab `OK`
- bot Discord orchestrator online dan merespons di `#orchestrator`

---

## 24. Hal yang Perlu Diklarifikasi Sebelum Production

Sebelum digunakan production, putuskan beberapa hal ini:

- Domain final yang akan dipakai untuk `PUBLIC_DOMAIN`.
- Provider LLM dan combo final untuk `premium`, `balanced`, dan `budget`.
- Apakah `researcher` dan `executor` tetap spawn-on-demand atau dibuat always-on.
- Apakah tiap profile memakai bot Discord terpisah atau satu bot shared.
- Strategi backup untuk `/var/lib/morph-agency/` dan `/var/lib/9router`.
- Kebijakan akses SSH dan admin dashboard 9Router.
