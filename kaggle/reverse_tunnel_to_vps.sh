#!/usr/bin/env bash
# Do NOT use set -e — SSH failure must not kill the reconnect loop.
set -uo pipefail

# Open SSH reverse tunnel from Kaggle notebook to VPS.
# After this runs, VPS port $VPS_TUNNEL_PORT forwards to Kaggle port $LOCAL_LLM_PORT.

VPS_HOST="${VPS_HOST:?VPS_HOST not set. Export VPS_HOST=your.vps.ip}"
VPS_USER="${VPS_USER:-kaggle-gpu}"
VPS_PORT="${VPS_PORT:-22}"
KEY_PATH="${KAGGLE_TUNNEL_KEY_PATH:-/tmp/kaggle_tunnel_key}"
LOCAL_PORT="${LOCAL_LLM_PORT:-8080}"
REMOTE_PORT="${VPS_TUNNEL_PORT:-8081}"
SSH_LOG="/tmp/tunnel_ssh.log"

echo "=== Opening reverse SSH tunnel ==="
echo "Local:   localhost:$LOCAL_PORT (Kaggle LLM)"
echo "Remote:  $VPS_HOST:$REMOTE_PORT (VPS)"
echo "User:    $VPS_USER"
echo "Key:     $KEY_PATH"
echo ""

if [[ ! -f "$KEY_PATH" ]]; then
    echo "ERROR: SSH key not found at $KEY_PATH"
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

ATTEMPT=0
while true; do
    ATTEMPT=$((ATTEMPT + 1))
    echo "[attempt $ATTEMPT] Connecting to $VPS_USER@$VPS_HOST..."
    > "$SSH_LOG"

    # Use explicit 'localhost:PORT' bind address — avoids ambiguity when the SSH
    # client sends an empty bind string that some sshd configs reject.
    ssh -N \
        -R "localhost:${REMOTE_PORT}:localhost:${LOCAL_PORT}" \
        -i "$KEY_PATH" \
        -p "$VPS_PORT" \
        -o StrictHostKeyChecking=no \
        -o ServerAliveInterval=30 \
        -o ServerAliveCountMax=3 \
        -o ConnectTimeout=15 \
        -o ExitOnForwardFailure=yes \
        -o LogLevel=VERBOSE \
        "${VPS_USER}@${VPS_HOST}" 2>>"$SSH_LOG" \
    && EXIT_CODE=0 || EXIT_CODE=$?

    echo "[attempt $ATTEMPT] Tunnel exited (code $EXIT_CODE). Last SSH log:"
    tail -10 "$SSH_LOG" | sed 's/^/  /'
    echo "Reconnecting in 10 seconds..."
    sleep 10
done
