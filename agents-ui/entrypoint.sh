#!/bin/sh
# Generate /config.js from environment variables at container startup.
# This avoids hardcoding URLs in the HTML and keeps the image re-usable
# across environments by changing env vars only.

N8N_BASE="${N8N_BASE:-/n8n/webhook}"
TMLINK_API_BASE="${TMLINK_API_BASE:-http://localhost:8000}"

cat > /usr/share/nginx/html/config.js <<EOF
window.TMLINK_CONFIG = {
  n8nBase:  "${N8N_BASE}",
  apiBase:  "${TMLINK_API_BASE}"
};
EOF

exec "$@"
