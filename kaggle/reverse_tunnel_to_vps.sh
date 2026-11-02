#!/usr/bin/env bash
# Do NOT use set -e — SSH failure must not kill the reconnect loop.
set -uo pipefail

# Open SSH reverse tunnel from Kaggle notebook to VPS.
# After this runs, VPS port $VPS_TUNNEL_PORT forwards to Kaggle port $LOCAL_LLM_PORT.
#
# VPS must listen on port 2222 (added alongside port 22):
#   Port 22
#   Port 2222
#   Match User kaggle-gpu
#       AllowTcpForwarding yes
#       GatewayPorts clientspecified

VPS_HOST="${VPS_HOST:?VPS_HOST not set. Export VPS_HOST=your.vps.ip}"
VPS_USER="${VPS_USER:-kaggle-gpu}"
# Port 2222 is used because Kaggle notebooks block outbound TCP port 22.
VPS_PORT="${VPS_PORT:-22}"
KEY_PATH="${KAGGLE_TUNNEL_KEY_PATH:-/tmp/kaggle_tunnel_key}"
LOCAL_PORT="${LOCAL_LLM_PORT:-8080}"
REMOTE_PORT="${VPS_TUNNEL_PORT:-8081}"
# Address the VPS side listens on. Default "localhost" keeps the v1 behaviour.
# The agent stack (docs/KAGGLE_QWEN38_AGENT.md) sets 172.17.0.1 (docker bridge) so
# containers can reach the tunnel; sshd must allow it (see vps/agent-stack/).
REMOTE_BIND="${VPS_TUNNEL_BIND:-localhost}"
# Optional host-key pinning: export VPS_HOST_KEY='<host> ssh-ed25519 AAAA...'
# (from `ssh-keyscan -t ed25519 <vps>` run on a trusted machine).
HOST_KEY="${VPS_HOST_KEY:-}"
KNOWN_HOSTS="/tmp/kaggle_known_hosts"
SSH_LOG="/tmp/tunnel_ssh.log"

echo "=== Opening reverse SSH tunnel ==="
echo "Local:   localhost:$LOCAL_PORT (Kaggle LLM)"
echo "Remote:  $VPS_HOST ($REMOTE_BIND:$REMOTE_PORT on the VPS)"
echo "User:    $VPS_USER  Port: $VPS_PORT"
echo "Key:     $KEY_PATH"
echo ""

if [[ ! -f "$KEY_PATH" ]]; then
    echo "ERROR: SSH key not found at $KEY_PATH"
    exit 1
fi
chmod 600 "$KEY_PATH"

# Fail fast on a passphrase-protected key: ssh cannot prompt here, so it would just
# drop every login and fail2ban on the VPS would ban this Kaggle IP.
if command -v ssh-keygen &>/dev/null && ! ssh-keygen -y -P "" -f "$KEY_PATH" >/dev/null 2>&1; then
    echo "ERROR: $KEY_PATH is passphrase-protected or invalid. Use a key made with: ssh-keygen -t ed25519 -N '' ..."
    exit 1
fi
MAX_FAILS="${TUNNEL_MAX_FAILS:-8}"   # consecutive failures before giving up (protects the VPS from ban loops)
FAILS=0

if [[ -n "$HOST_KEY" ]]; then
    printf '%s\n' "$HOST_KEY" > "$KNOWN_HOSTS"
    SSH_HOST_OPTS=(-o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$KNOWN_HOSTS")
    echo "Host key: pinned"
else
    SSH_HOST_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)
    echo "WARNING: VPS_HOST_KEY not set - host key is NOT verified (first-run convenience only)."
fi

# ─── Connectivity test ────────────────────────────────────────────────────────
echo "Testing TCP connectivity to $VPS_HOST:$VPS_PORT ..."
if command -v nc &>/dev/null; then
    if nc -z -w 5 "$VPS_HOST" "$VPS_PORT" 2>/dev/null; then
        echo "  TCP OK — port $VPS_PORT is reachable"
    else
        echo "  TCP FAILED on port $VPS_PORT — Kaggle may be blocking this port"
        # Try port 22 as fallback diagnostic
        if nc -z -w 5 "$VPS_HOST" 22 2>/dev/null; then
            echo "  Port 22 is reachable — try: export VPS_PORT=22"
        else
            echo "  Port 22 also blocked. Kaggle may be restricting outbound SSH entirely."
            echo "  Consider cloudflared tunnel as an alternative."
        fi
    fi
elif command -v python3 &>/dev/null; then
    python3 -c "
import socket, sys
host, port = '$VPS_HOST', $VPS_PORT
try:
    s = socket.create_connection((host, port), timeout=5)
    s.close()
    print(f'  TCP OK — port {port} is reachable')
except Exception as e:
    print(f'  TCP FAILED on port {port}: {e}')
    try:
        s = socket.create_connection((host, 22), timeout=5)
        s.close()
        print(f'  Port 22 IS reachable — try: export VPS_PORT=22')
    except:
        print(f'  Port 22 also blocked.')
"
fi
echo ""

# ─── Wait for LLM server ──────────────────────────────────────────────────────
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
    ATTEMPT_START=$SECONDS
    echo "[attempt $ATTEMPT] Connecting to $VPS_USER@$VPS_HOST:$VPS_PORT..."
    > "$SSH_LOG"

    ssh -N \
        -R "${REMOTE_BIND}:${REMOTE_PORT}:localhost:${LOCAL_PORT}" \
        -i "$KEY_PATH" \
        -p "$VPS_PORT" \
        "${SSH_HOST_OPTS[@]}" \
        -o ServerAliveInterval=30 \
        -o ServerAliveCountMax=3 \
        -o ConnectTimeout=15 \
        -o ExitOnForwardFailure=yes \
        -o LogLevel=VERBOSE \
        "${VPS_USER}@${VPS_HOST}" 2>>"$SSH_LOG" \
    && EXIT_CODE=0 || EXIT_CODE=$?

    echo "[attempt $ATTEMPT] Tunnel exited (code $EXIT_CODE). Last SSH log:"
    tail -10 "$SSH_LOG" | sed 's/^/  /'
    if (( SECONDS - ATTEMPT_START < 60 )); then FAILS=$((FAILS + 1)); else FAILS=0; fi
    if (( FAILS >= MAX_FAILS )); then
        echo "ERROR: $FAILS quick failures in a row - giving up so the VPS firewall does not ban this IP."
        exit 1
    fi
    DELAY=$(( 10 * (FAILS + 1) )); (( DELAY > 120 )) && DELAY=120
    echo "Reconnecting in ${DELAY} seconds..."
    sleep "$DELAY"
done
