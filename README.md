# TMLink n8n-Agent System

An automated record linkage system built on the **official `taiwotman/tmlink` Docker image** — no source code required. Three n8n agents handle registration, file upload/approval, and record search through a simple web UI.

---

## Quick Answer: Official Image or Source Code?

> **Official Docker image only.**
> This system pulls `taiwotman/tmlink:latest` directly from Docker Hub. There is no TMLink source code in this repo — the agents wrap TMLink's REST API with n8n automation workflows.

---

## Prerequisites

- **Docker Desktop** (Mac/Windows) or **Docker Engine + Compose** (Linux)
- A **Gmail account** with 2-Step Verification enabled (TMLink sends OTP codes to this address)
- Ports `3001`, `5678`, `8501` available on your machine (all configurable in `.env`)

---

## Setup

### 1. Enter the project directory

```bash
cd tmlink   # where docker-compose.official.yml lives
```

### 2. Create your `.env` file

```bash
cp .env.example .env
```

Edit `.env` and fill in your values:

```env
# ── n8n login ────────────────────────────────────────────────
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=YourSecurePassword

# ── Your email (used to log in to TMLink) ────────────────────
TMLINK_EMAIL=you@gmail.com
APPROVER_EMAIL=you@gmail.com
SMTP_FROM=you@gmail.com

# ── Gmail App Password (required for TMLink OTP emails) ──────
# Generate at: myaccount.google.com → Security → App Passwords
GMAIL_APP_PASSWORD=your-app-password

# ── Internal URLs (do not change) ────────────────────────────
TMLINK_API_URL=http://tmlink-official:8000
WEBHOOK_URL=http://localhost:5678/
GENERIC_TIMEZONE=UTC
N8N_BASE=/n8n/webhook
TMLINK_API_BASE=http://localhost:3001/tmlink-api
```

### 3. Run setup

```bash
make setup
```

> **First time only — always use `make setup`, not `make start`.**
> `make setup` pulls images, builds containers, starts services, and imports/activates all n8n workflows.
> `make start` only starts containers — it does not import workflows and will leave the system non-functional on a fresh machine.

**First startup takes 2–5 minutes** — TMLink needs time to initialise.

### 4. Create the n8n owner account (one-time)

After `make setup` completes, open **http://localhost:5678** in your browser. n8n will show a one-time account setup wizard — fill in any email and password to create your owner account. This does not affect the workflows, which are already active.

> You only need to do this once. After the account is created, n8n will not show the wizard again.

---

## Starting and Stopping

```bash
make setup      # FIRST TIME ONLY — pulls, builds, imports workflows, starts everything
make start      # subsequent starts after setup is done (data preserved)
make stop       # stop all services (data preserved)
make restart    # stop then start
make status     # show running containers and ports
make logs       # follow logs for all services
make logs-n8n   # follow n8n logs only
make logs-tmlink # follow TMLink logs only
make reset      # full wipe + re-setup (WARNING: deletes all data and re-runs setup)
```

> **Note:** TMLink stores uploaded files and linkage results in memory. If `tmlink-official` restarts, you must re-upload your file and run linkage again.

---

## Service URLs

| Service | Default Port | `.env` variable | URL |
|---|---|---|---|
| **Agents UI** | 3001 | `PORT_AGENTS_UI` | http://localhost:3001 |
| **TMLink UI** | 8501 | `PORT_TMLINK_UI` | http://localhost:8501 |
| **TMLink API** | 3001/tmlink-api | via nginx proxy | http://localhost:3001/tmlink-api |
| **n8n Editor** | 5678 | `PORT_N8N` | http://localhost:5678 |

**n8n login:** credentials from your `.env` (`N8N_BASIC_AUTH_USER` / `N8N_BASIC_AUTH_PASSWORD`)

### Changing ports

If any port conflicts with another service, change the `PORT_*` value in `.env` and restart:

```env
PORT_AGENTS_UI=3001
PORT_N8N=5678
PORT_TMLINK_UI=8501
```

```bash
make restart
```

---

## Usage

### Register an account

1. Open **http://localhost:3001**
2. Click **Register** and enter your email
3. TMLink emails you a one-time code — check your inbox
4. Enter the OTP in the UI to complete registration

### Upload a file for record linkage

1. Click **Upload File** and select your CSV
2. The CSV must have name columns — any of these are accepted:
   `first_name`, `firstname`, `fname`, `given_name` / `last_name`, `lastname`, `lname`, `surname`
3. Click **Submit** — the agent stores the file and shows **Approve / Reject** buttons
4. Click **Approve** — the file is sent to TMLink and linkage runs in the background
5. Wait ~30 seconds, then use Search

### Search records (Basic Search)

1. Click **Search / Query**
2. Enter a full name e.g. `John Smith`
3. Returns the record and all similar/duplicate records TMLink found during linkage

> Basic search is an **exact name match** on the linked results. If you search `John`, it returns records where the first or last name is exactly "John" and their linked duplicates. For fuzzy/AI-powered search, see Advanced Search below.

### Advanced Search (AI-powered)

The **`/ask`** endpoint accepts natural language questions and uses the AI engine to generate SQL. To enable it: query agent can be updated to call `/ask` instead of `/search_records`


### Enter OTP manually (no IMAP)

1. Click **Submit OTP** in the Agents UI
2. Enter the 6-digit code from your email

---

## How Searches Work

TMLink's search operates on **linkage results**, not on the raw uploaded file. This means:

1. You upload a CSV with records (e.g. 500 rows)
2. TMLink's linkage engine compares every pair and finds near-duplicates (e.g. `John Michael` ≈ `Jon Michael` ≈ `Jonathan Michaels`)
3. Each record gets a `similar_record` and `similarity_score` in the output
4. **Basic search** (`/search_records`): enter a name → returns that record and its duplicates found during linkage
5. **Advanced search** (`/ask`): natural language → AI generates SQL → runs against linked dataset

Search returns **no results** if linkage hasn't been run yet, or if the dataset has no similar records.

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  Agents UI  :3001                        │
│             (nginx static frontend)                      │
└────────────────────┬────────────────────────────────────┘
                     │ HTTP webhooks
┌────────────────────▼────────────────────────────────────┐
│                  n8n  :5678                              │
│  ┌─────────────────────────────────────────────────┐    │
│  │  Register Agent    → /auth/api/ (register)      │    │
│  │  Register Verify   → /auth/api/verify_email     │    │
│  │  Link Agent        → /api/upload_file_to_link   │    │
│  │                    → /api/link_record            │    │
│  │  Query Agent       → /api/search_records        │    │
│  │  Auth Sub-Workflow → cookie management          │    │
│  │  IMAP Extractor    → Gmail IMAP (optional)      │    │
│  └─────────────────────────────────────────────────┘    │
└──────────┬──────────────────────┬───────────────────────┘
           │ REST API             │ session cookie
┌──────────▼──────────┐  ┌───────▼────────────┐
│  taiwotman/tmlink   │  │  auth-store :8080  │
│  :8501 (Streamlit)  │  │  (cookie cache)    │
│  :8000 (FastAPI)    │  └────────────────────┘
└─────────────────────┘
```

**Components:**
- **`taiwotman/tmlink`** — Official image. Runs both the Streamlit UI and FastAPI backend. Uploaded data lives in memory — resets on container restart.
- **`n8n`** — Hosts all automation workflows. Workflow definitions persist in a Docker volume.
- **`auth-store`** — Custom microservice that caches the TMLink session cookie so all agents share one authenticated session.
- **`agents-ui`** — Static HTML/JS frontend served by nginx.

---

## Troubleshooting

```bash
make status            # are all containers running?
make logs-tmlink       # TMLink startup issues?
make logs-n8n          # n8n workflow issues?
make reset             # full wipe + re-setup (WARNING: deletes all n8n data)
```

**IMAP crash loop** (`"Imap connection closed unexpectedly"` repeating in n8n logs):
The Gmail App Password is invalid or expired. Go to n8n UI → **TMLink IMAP Code Extractor** → toggle it **off**. Enter OTP codes manually until a new App Password is configured.

---

## File Structure

```
tmlink/
├── docker-compose.official.yml   # Main compose file
├── .env                          # Your config (never commit this)
├── .env.example                  # Template
├── agents_setup.sh               # One-command setup script
├── agents-ui/                    # Frontend (nginx + HTML/JS)
├── auth-store/                   # Session cookie microservice
└── n8n/
    └── workflows/
        ├── auth-subworkflow.json      # Shared session manager
        ├── register-agent.json        # Registration flow
        ├── register-verify.json       # OTP verification
        ├── link-agent.json            # File upload + linkage
        ├── query-agent.json           # Record search
        ├── otp-submit.json            # Manual OTP entry
        └── imap-extractor.json        # Auto Gmail OTP (optional, off by default)
```
