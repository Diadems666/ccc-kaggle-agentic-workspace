#!/usr/bin/env bash
# Wait for the Kaggle GPU tunnel to come up, then auto-switch all agents to it.
# Run this in your IDE terminal while you're setting up the Kaggle notebook.

KAGGLE_PORT="${KAGGLE_TUNNEL_PORT:-8081}"
POLL_INTERVAL="${POLL_INTERVAL:-10}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "Waiting for Kaggle GPU tunnel on localhost:${KAGGLE_PORT}..."
echo "(Start your Kaggle notebook now, then come back here)"
echo ""

while true; do
    if curl -sf --max-time 2 "http://localhost:${KAGGLE_PORT}/v1/models" &>/dev/null; then
        echo -e "${GREEN}GPU tunnel detected!${NC}"
        echo ""

        MODEL=$(curl -sf "http://localhost:${KAGGLE_PORT}/v1/models" \
            | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data'][0]['id'])" 2>/dev/null \
            || echo "local-model")
        echo "Model: $MODEL"
        echo ""

        bash "${SCRIPT_DIR}/switch_provider.sh" local
        echo ""
        echo -e "${GREEN}Done. Your agents are now using the Kaggle GPU.${NC}"
        echo "Test: curl http://localhost:${KAGGLE_PORT}/v1/models"
        exit 0
    fi

    printf "${YELLOW}.${NC}"
    sleep "$POLL_INTERVAL"
done
