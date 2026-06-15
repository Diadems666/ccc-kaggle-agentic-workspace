#!/usr/bin/env bash
set -euo pipefail

# Check health of all workspace services.
# Prints OK/WARN/ERROR for each component.

WORKSPACE_DIR="${WORKSPACE_DIR:-/opt/coding-workspace}"
ENV_FILE="${WORKSPACE_DIR}/.env"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[OK]${NC}   $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERR]${NC}  $1"; }

echo "=== CCC Workspace Health Check ==="
echo "$(date)"
echo ""

# ─── Load env ─────────────────────────────────────────────────────────────────
if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    ok ".env file found"
else
    warn ".env file not found at $ENV_FILE"
fi

# ─── code-server ──────────────────────────────────────────────────────────────
if systemctl is-active --quiet code-server 2>/dev/null; then
    ok "code-server: running"
elif systemctl is-active --quiet openvscode-server 2>/dev/null; then
    ok "openvscode-server: running"
else
    err "code-server / openvscode-server: not running"
    echo "       Fix: sudo systemctl start code-server"
fi

# ─── Cloudflare tunnel ────────────────────────────────────────────────────────
if systemctl is-active --quiet cloudflared 2>/dev/null; then
    ok "cloudflared: running"
else
    err "cloudflared: not running"
    echo "       Fix: sudo systemctl start cloudflared"
fi

# ─── GitHub connectivity ──────────────────────────────────────────────────────
if curl -sf --max-time 5 https://github.com &>/dev/null; then
    ok "GitHub: reachable"
else
    err "GitHub: unreachable (check DNS / internet)"
fi

# ─── Anthropic API ────────────────────────────────────────────────────────────
if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    if curl -sf --max-time 5 https://api.anthropic.com &>/dev/null; then
        ok "Anthropic API: reachable"
    else
        warn "Anthropic API: endpoint unreachable"
    fi
else
    warn "Anthropic API: ANTHROPIC_API_KEY not set"
fi

# ─── Kaggle tunnel ────────────────────────────────────────────────────────────
KAGGLE_PORT="${KAGGLE_TUNNEL_PORT:-8081}"
if ss -tlnp 2>/dev/null | grep -q ":${KAGGLE_PORT}"; then
    # Verify LLM actually responds
    if curl -sf --max-time 3 "http://localhost:${KAGGLE_PORT}/v1/models" &>/dev/null; then
        ok "Kaggle tunnel: active (LLM responding on :${KAGGLE_PORT})"
    else
        warn "Kaggle tunnel: port open but LLM not responding yet"
    fi
else
    echo -e "${YELLOW}[??]${NC}  Kaggle tunnel: not active (normal if no GPU session)"
fi

# ─── Disk ─────────────────────────────────────────────────────────────────────
DISK_USAGE=$(df -h / | awk 'NR==2 {print $3"/"$2" ("$5")"}')
DISK_PCT=$(df / | awk 'NR==2 {print int($5)}')
if [[ $DISK_PCT -lt 80 ]]; then
    ok "Disk: $DISK_USAGE"
elif [[ $DISK_PCT -lt 90 ]]; then
    warn "Disk: $DISK_USAGE — consider cleaning up"
else
    err "Disk: $DISK_USAGE — CRITICAL, cleanup needed"
fi

# ─── Memory ───────────────────────────────────────────────────────────────────
MEM_TOTAL=$(free -m | awk 'NR==2{print $2}')
MEM_USED=$(free -m | awk 'NR==2{print $3}')
MEM_PCT=$(( MEM_USED * 100 / MEM_TOTAL ))
ok "Memory: ${MEM_USED}MB / ${MEM_TOTAL}MB (${MEM_PCT}%)"

# ─── Load ─────────────────────────────────────────────────────────────────────
LOAD=$(uptime | awk -F'load average:' '{print $2}' | tr -d ' ')
ok "Load avg: $LOAD"

echo ""
echo "=== Check complete ==="
