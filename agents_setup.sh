#!/usr/bin/env bash
# TMLink 3-Agent System Setup
# Pulls images, starts services, and imports all n8n workflows.
# All sensitive values are read from .env — nothing is hardcoded here.
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e " ${GREEN}OK${NC}"; }
warn() { echo -e " ${YELLOW}$*${NC}"; }
fail() { echo -e " ${RED}FAILED${NC}"; echo "$*" >&2; exit 1; }

echo "============================================"
echo "  TMLink 3-Agent System Setup"
echo "============================================"
echo ""

# ── Verify Docker ────────────────────────────────────────────
echo -n "Checking Docker... "
command -v docker &>/dev/null || fail "Docker not found. Install from https://docs.docker.com/get-docker/"
COMPOSE="docker compose"
$COMPOSE version &>/dev/null || COMPOSE="docker-compose"
$COMPOSE version &>/dev/null || fail "Docker Compose not found."
ok

# ── Load .env ────────────────────────────────────────────────
echo -n "Checking .env... "
if [ ! -f .env ]; then
    echo ""
    warn "NOT FOUND — copying .env.example to .env"
    cp .env.example .env
    echo ""
    echo "  Please edit .env and set all required values, then re-run."
    echo "  Required: N8N_USER_EMAIL, N8N_USER_PASSWORD,"
    echo "            TMLINK_EMAIL, GMAIL_APP_PASSWORD,"
    echo "            APPROVER_EMAIL, SMTP_FROM"
    exit 1
fi
# Source .env but do NOT override variables already exported in the shell
while IFS='=' read -r key value; do
    # Skip comments and blank lines
    [[ "$key" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${key// }" ]] && continue
    # Only set if not already in environment
    if [[ -z "${!key+x}" ]]; then
        export "$key=$value"
    fi
done < .env
ok

# Validate required vars
for var in TMLINK_EMAIL GMAIL_APP_PASSWORD; do
    if [ -z "${!var:-}" ]; then
        fail "Required variable $var is not set in .env"
    fi
done

# ── Pull & Build ─────────────────────────────────────────────
echo ""
echo "Pulling images..."
$COMPOSE -f docker-compose.official.yml pull

echo "Building agents-ui..."
$COMPOSE -f docker-compose.official.yml build agents-ui auth-store

# ── Start TMLink first (it downloads an ML model on first boot) ──
echo ""
echo "Starting TMLink and auth-store..."
$COMPOSE -f docker-compose.official.yml up -d tmlink auth-store

# ── Wait for TMLink ──────────────────────────────────────────
# First boot downloads sentence-transformers (~300 MB) — allow up to 10 min.
echo ""
echo -n "Waiting for TMLink (first boot may take up to 10 min for model download)..."
for i in $(seq 1 150); do
    STATUS=$(docker inspect --format='{{.State.Health.Status}}' tmlink-official 2>/dev/null)
    if [ "$STATUS" = "healthy" ]; then
        ok; break
    fi
    if [ "$STATUS" = "unhealthy" ]; then
        fail "TMLink failed healthcheck. Check logs: $COMPOSE -f docker-compose.official.yml logs tmlink"
    fi
    sleep 4; echo -n "."
    [ "$i" -eq 150 ] && fail "Timeout (10 min). Check logs: $COMPOSE -f docker-compose.official.yml logs tmlink"
done

# ── Start remaining services now that TMLink is healthy ──────
echo "Starting n8n and agents-ui..."
$COMPOSE -f docker-compose.official.yml up -d n8n agents-ui

# ── Wait for n8n ─────────────────────────────────────────────
echo -n "Waiting for n8n..."
for i in $(seq 1 60); do
    if docker exec n8n wget -qO- http://localhost:5678/healthz &>/dev/null; then
        ok; break
    fi
    sleep 2; echo -n "."
    [ "$i" -eq 60 ] && fail "n8n timeout. Check logs: $COMPOSE -f docker-compose.official.yml logs n8n"
done

echo -n "Checking auth-store..."
docker ps --format '{{.Names}}' | grep -q tmlink-auth-store && ok || warn "NOT DETECTED (proceeding anyway)"

# ── Import n8n workflows via CLI (always overwrites existing) ─
echo ""
echo "Importing workflows into n8n..."

# The n8n container mounts ./n8n/workflows at /workflows (read-only)
# We use the n8n CLI directly inside the container — no REST API auth needed.

# auth-subworkflow ID is hardcoded in the JSON (tmlink-auth-subworkflow)
# The other workflows reference it by that ID — no placeholder substitution needed.

# Import all workflows from the mounted /workflows directory
docker exec n8n n8n import:workflow --separate --input=/workflows 2>&1
echo -e " ${GREEN}Workflows imported.${NC}"

# Activate core workflows via CLI (IMAP extractor excluded)
echo "Activating workflows..."
for wf_id in \
    "tmlink-auth-subworkflow" \
    "YFpqBNyG2DDg49s8" \
    "oE6OicF4tAAauSzn" \
    "NA75Lt2HXfZpwl0V" \
    "2z1FrDtmxQGwLVCq" \
    "otp-submit-workflow" \
    "linkage-status-workflow"; do
    docker exec n8n n8n update:workflow --id="$wf_id" --active=true 2>/dev/null \
        && echo "  Activated: $wf_id" \
        || echo "  Could not activate: $wf_id"
done

# Restart n8n so activated workflows register their webhooks
echo "Restarting n8n to apply activations..."
docker restart n8n >/dev/null
echo -n "Waiting for n8n..."
for i in $(seq 1 30); do
    if docker exec n8n wget -qO- http://localhost:5678/healthz &>/dev/null; then
        ok; break
    fi
    sleep 2; echo -n "."
    [ "$i" -eq 30 ] && warn "n8n slow to restart — check with: make logs-n8n"
done

# ── Summary ──────────────────────────────────────────────────
echo ""
echo "============================================"
echo -e "  ${GREEN}Setup complete!${NC}"
echo "============================================"
echo ""
AGENTS_PORT="${PORT_AGENTS_UI:-3001}"
N8N_PORT="${PORT_N8N:-5678}"
TMLINK_PORT="${PORT_TMLINK_UI:-8501}"
echo "  TMLink UI:    http://localhost:${TMLINK_PORT}"
echo "  n8n Editor:   http://localhost:${N8N_PORT}"
echo "  Agents UI:    http://localhost:${AGENTS_PORT}"
echo ""
echo "Next steps:"
echo "  1. Open the Agents UI at http://localhost:${AGENTS_PORT}"
echo "  2. Register your email, check your inbox for the OTP code"
echo "  3. Enter the OTP code in the UI to complete login"
echo "  4. Upload your CSV and run record linkage"
