#!/usr/bin/env bash
set -euo pipefail

# Open SSH reverse tunnel from Kaggle notebook to VPS.
# After this runs, VPS port $VPS_TUNNEL_PORT forwards to Kaggle port $LOCAL_LLM_PORT.
#
# Required env vars:
#   VPS_HOST              — VPS IP or hostname
#   KAGGLE_TUNNEL_KEY_PATH — path to SSH private key (default: /tmp/kaggle_tunnel_key)
#
# Optional:
#   VPS_USER              — SSH user on VPS (default: kaggle-gpu)
#   VPS_PORT              — SSH port on VPS (default: 22)
#   LOCAL_LLM_PORT        — LLM server port on Kaggle (default: 8080)
#   VPS_TUNNEL_PORT       — port to expose on VPS (default: 8081)

VPS_HOST="${VPS_HOST:?VPS_HOST not set. Export VPS_HOST=your.vps.ip}"
VPS_USER="${VPS_USER:-kaggle-gpu}"
VPS_PORT="${VPS_PORT:-22}"
KEY_PATH="${KAGGLE_TUNNEL_KEY_PATH:-/tmp/kaggle_tunnel_key}"
LOCAL_PORT="${LOCAL_LLM_PORT:-8080}"
REMOTE_PORT="${VPS_TUNNEL_PORT:-8081}"

echo "=== Opening reverse SSH tunnel ==="
echo "Local:   localhost:$LOCAL_PORT (Kaggle LLM)"
echo "Remote:  $VPS_HOST:$REMOTE_PORT (VPS)"
echo "User:    $VPS_USER"
echo "Key:     $KEY_PATH"
echo ""

if [[ ! -f "$KEY_PATH" ]]; then
    echo "ERROR: SSH key not found at $KEY_PATH"
    echo "Load the key from Kaggle secrets before running this script."
    exit 1
fi
chmod 600 "$KEY_PATH"

# Verify LLM server is running before opening tunnel
echo "Checking LLM server on localhost:$LOCAL_PORT..."
for i in $(seq 1 12); do
    if curl -sf "http://localhost:$LOCAL_PORT/v1/models" &>/dev/null; then
        echo "LLM server is ready."
        break
    fi
    if [[ $i -eq 12 ]]; then
        echo "WARNING: LLM server not responding after 60s. Opening tunnel anyway."
    else
        echo "Waiting for LLM server... ($((i*5))s)"
        sleep 5
    fi
done

echo ""
echo "Opening tunnel (Ctrl+C to close)..."
echo "Once connected, test from VPS: curl http://localhost:$REMOTE_PORT/v1/models"
echo ""

# Open the reverse tunnel with auto-reconnect loop
while true; do
    ssh -N \
        -R "${REMOTE_PORT}:localhost:${LOCAL_PORT}" \
        -i "$KEY_PATH" \
        -p "$VPS_PORT" \
        -o StrictHostKeyChecking=no \
        -o ServerAliveInterval=30 \
        -o ServerAliveCountMax=3 \
        -o ConnectTimeout=15 \
        -o ExitOnForwardFailure=yes \
        "${VPS_USER}@${VPS_HOST}"

    EXIT_CODE=$?
    echo "Tunnel dropped (exit code $EXIT_CODE). Reconnecting in 10 seconds..."
    sleep 10
done
