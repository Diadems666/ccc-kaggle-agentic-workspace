#!/usr/bin/env bash
set -uo pipefail

# One-glance status of the agent stack on the VPS:
# Kaggle tunnel -> llama-server -> LiteLLM -> SearXNG -> OpenHands.
#
# Usage: bash scripts/agent_stack_status.sh [--smoke]
#   --smoke   also send a tiny chat completion through the gateway (needs LiteLLM key)

STACK_DIR="${STACK_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../vps/agent-stack" 2>/dev/null && pwd || echo /opt/coding-workspace/vps/agent-stack)}"
ENV_FILE="${STACK_DIR}/.env"
if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
fi

BRIDGE_IP="${BRIDGE_IP:-172.17.0.1}"
TUNNEL_PORT="${KAGGLE_TUNNEL_PORT:-8081}"
KEY="${KAGGLE_LLM_API_KEY:-local}"

GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; RED=$'\033[0;31m'; NC=$'\033[0m'
ok()   { echo "${GREEN}[OK]${NC}   $*"; }
warn() { echo "${YELLOW}[WARN]${NC} $*"; }
err()  { echo "${RED}[ERR]${NC}  $*"; }

echo "=== CCC agent stack status ($(date '+%F %T')) ==="

# 1. Kaggle tunnel + model
if ss -ltn 2>/dev/null | grep -q "${BRIDGE_IP}:${TUNNEL_PORT}"; then
    ok "Tunnel listening on ${BRIDGE_IP}:${TUNNEL_PORT}"
    HEALTH="$(curl -s --max-time 4 "http://${BRIDGE_IP}:${TUNNEL_PORT}/health" || true)"
    if grep -q '"ok"' <<<"$HEALTH"; then
        MODELS="$(curl -s --max-time 4 -H "Authorization: Bearer ${KEY}" "http://${BRIDGE_IP}:${TUNNEL_PORT}/v1/models" || true)"
        MODEL_ID="$(grep -oE '"id":"[^"]+"' <<<"$MODELS" | head -n 1 | cut -d'"' -f4)"
        ok "Kaggle llama-server healthy${MODEL_ID:+ (model: ${MODEL_ID})}"
    else
        warn "Tunnel is up but llama-server is not ready: ${HEALTH:-no response}"
    fi
elif ss -ltn 2>/dev/null | grep -q "127.0.0.1:${TUNNEL_PORT}"; then
    err "Tunnel is bound to 127.0.0.1, not ${BRIDGE_IP}: containers cannot reach it."
    echo "       Fix: sshd needs 'GatewayPorts clientspecified' for kaggle-gpu (rerun install-agent-stack.sh)"
    echo "            and the notebook must use VPS_TUNNEL_BIND=${BRIDGE_IP}."
else
    echo "[--]   Kaggle GPU: not connected (normal when no session is running)"
fi

# 2. Containers
if command -v docker >/dev/null 2>&1; then
    for svc in litellm searxng openhands; do
        state="$(docker inspect -f '{{.State.Status}}{{if .State.Health}}/{{.State.Health.Status}}{{end}}' "ccc-agent-${svc}-1" 2>/dev/null || echo missing)"
        case "$state" in
            running|running/healthy) ok "${svc}: ${state}" ;;
            missing)                 err "${svc}: container not found (docker compose up -d in ${STACK_DIR})" ;;
            *)                       warn "${svc}: ${state}" ;;
        esac
    done
else
    err "docker not installed"
fi

# 3. Endpoints
curl -fs --max-time 4 "http://127.0.0.1:4000/health/liveliness" >/dev/null 2>&1 \
    && ok "LiteLLM answering on 127.0.0.1:4000" || err "LiteLLM not answering on 127.0.0.1:4000"
curl -fs --max-time 6 "http://127.0.0.1:8888/search?q=test&format=json" >/dev/null 2>&1 \
    && ok "SearXNG JSON API answering on 127.0.0.1:8888" || warn "SearXNG JSON API not answering on 127.0.0.1:8888"
curl -fs --max-time 4 -o /dev/null "http://127.0.0.1:3000" \
    && ok "OpenHands UI answering on 127.0.0.1:3000" || warn "OpenHands UI not answering on 127.0.0.1:3000"

# 4. Optional end-to-end smoke test through the gateway
if [[ "${1:-}" == "--smoke" ]]; then
    if [[ -z "${LITELLM_MASTER_KEY:-}" ]]; then
        err "LITELLM_MASTER_KEY not found in ${ENV_FILE}"
    else
        RESP="$(curl -s --max-time 120 http://127.0.0.1:4000/v1/chat/completions \
            -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" -H 'Content-Type: application/json' \
            -d '{"model":"ccc-local","messages":[{"role":"user","content":"Reply with: ready"}],"max_tokens":32}' || true)"
        if grep -q '"choices"' <<<"$RESP"; then
            ok "ccc-local end-to-end completion works"
        else
            err "ccc-local smoke test failed: ${RESP:-no response}"
        fi
    fi
fi
