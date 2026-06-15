#!/usr/bin/env bash
set -euo pipefail

# Start a new agentic coding session.
# Sources the workspace .env, prints status, and drops you into a project shell.

WORKSPACE_DIR="${WORKSPACE_DIR:-/opt/coding-workspace}"
ENV_FILE="${WORKSPACE_DIR}/.env"

echo "=== Starting Agent Session ==="
echo "$(date)"
echo ""

# Load environment
if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    set -a; source "$ENV_FILE"; set +a
    echo "[OK] Environment loaded from $ENV_FILE"
else
    echo "[WARN] .env not found at $ENV_FILE — using system environment"
fi

# Check active provider
PROVIDER="${ACTIVE_PROVIDER:-anthropic}"
MODEL="${ACTIVE_MODEL:-claude-sonnet-4-6}"
echo "[INFO] Active provider: $PROVIDER"
echo "[INFO] Active model:    $MODEL"

# Check Kaggle GPU
KAGGLE_PORT="${KAGGLE_TUNNEL_PORT:-8081}"
if ss -tlnp 2>/dev/null | grep -q ":${KAGGLE_PORT}" && \
   curl -sf --max-time 2 "http://localhost:${KAGGLE_PORT}/v1/models" &>/dev/null; then
    echo "[GPU]  Kaggle T4 tunnel active on :${KAGGLE_PORT}"
    echo "       To use: bash scripts/switch_provider.sh local"
fi

echo ""

# Check git status in repos
if [[ -d "${WORKSPACE_DIR}/repos" ]]; then
    for repo in "${WORKSPACE_DIR}"/repos/*/; do
        if [[ -d "$repo/.git" ]]; then
            REPO_NAME=$(basename "$repo")
            CHANGES=$(cd "$repo" && git status --short 2>/dev/null | wc -l)
            BRANCH=$(cd "$repo" && git branch --show-current 2>/dev/null || echo "unknown")
            if [[ "$CHANGES" -gt 0 ]]; then
                echo "[GIT]  $REPO_NAME ($BRANCH) — $CHANGES uncommitted changes"
            else
                echo "[GIT]  $REPO_NAME ($BRANCH) — clean"
            fi
        fi
    done
    echo ""
fi

echo "Ready. Available agents:"
echo "  claude     — Claude Code (default)"
echo "  aider      — AI pair programmer"
echo "  opencode   — TUI explorer"
echo "  codex      — Shell assistant"
echo ""
echo "Utility scripts:"
echo "  bash scripts/healthcheck.sh"
echo "  bash scripts/switch_provider.sh [anthropic|openai|local]"
echo "  bash scripts/check_gpu_backend.sh"
