#!/usr/bin/env bash
set -euo pipefail

# Check Kaggle GPU tunnel and LLM backend status.

KAGGLE_PORT="${KAGGLE_TUNNEL_PORT:-8081}"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "=== GPU Backend Check ==="
echo ""

# Check if tunnel port is open
if ! ss -tlnp 2>/dev/null | grep -q ":${KAGGLE_PORT}"; then
    echo -e "${YELLOW}Kaggle tunnel not active.${NC}"
    echo ""
    echo "To start a Kaggle GPU session:"
    echo "  1. Open kaggle.com → New Notebook → Enable GPU T4"
    echo "  2. Paste and run the setup cells from kaggle/KAGGLE_NOTEBOOK_SETUP.md"
    echo "  3. Run this script again to verify connectivity"
    exit 0
fi

echo -e "${GREEN}Tunnel port ${KAGGLE_PORT} is open.${NC}"
echo ""

# Check LLM server
echo "Querying LLM server..."
RESPONSE=$(curl -sf --max-time 5 "http://localhost:${KAGGLE_PORT}/v1/models" || echo "")

if [[ -z "$RESPONSE" ]]; then
    echo -e "${YELLOW}Tunnel is open but LLM server not responding.${NC}"
    echo "The model may still be loading. Wait 2-3 minutes and retry."
    exit 1
fi

echo -e "${GREEN}LLM server is responding.${NC}"
echo ""
echo "Available models:"
echo "$RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$RESPONSE"
echo ""

# Quick inference test
echo "Running quick inference test..."
TEST_RESPONSE=$(curl -sf --max-time 30 \
    "http://localhost:${KAGGLE_PORT}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{"model":"'"$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data'][0]['id'])" 2>/dev/null || echo "local-model")"'","messages":[{"role":"user","content":"Say OK"}],"max_tokens":5}' \
    || echo "")

if [[ -n "$TEST_RESPONSE" ]]; then
    echo -e "${GREEN}Inference test passed.${NC}"
    echo ""
    echo "Switch agents to use Kaggle GPU:"
    echo "  bash scripts/switch_provider.sh local"
else
    echo -e "${YELLOW}Inference test timed out.${NC} Server may be under load."
fi
