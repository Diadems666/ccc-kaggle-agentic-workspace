#!/usr/bin/env bash
set -euo pipefail

# Pull latest workspace scripts from GitHub.
# Optionally updates all agent tools.

WORKSPACE_DIR="${WORKSPACE_DIR:-/opt/coding-workspace}"
REPO_DIR="${WORKSPACE_DIR}"
UPDATE_TOOLS="${1:-}"

echo "=== Syncing workspace repository ==="

if [[ ! -d "$REPO_DIR/.git" ]]; then
    echo "ERROR: $REPO_DIR is not a git repository."
    echo "Clone the repo first: git clone https://github.com/YOUR_ORG/ccc-kaggle-agentic-workspace $REPO_DIR"
    exit 1
fi

cd "$REPO_DIR"

echo "Current branch: $(git branch --show-current)"
echo "Pulling latest changes..."
git pull --rebase origin "$(git branch --show-current)"

echo "Done."
echo ""

if [[ "$UPDATE_TOOLS" == "--update-tools" ]]; then
    echo "=== Updating agent tools ==="

    if command -v npm &>/dev/null; then
        echo "Updating Claude Code..."
        sudo npm update -g @anthropic-ai/claude-code || echo "  (skipped — may need root)"

        echo "Updating OpenCode..."
        sudo npm update -g opencode-ai || echo "  (skipped — may need root)"

        echo "Updating Codex CLI..."
        sudo npm update -g @openai/codex || echo "  (skipped — may need root)"
    fi

    if command -v pip &>/dev/null || command -v pip3 &>/dev/null; then
        PIP="${PIP:-pip3}"
        echo "Updating Aider..."
        $PIP install --upgrade aider-chat --quiet
    fi

    echo "Tool update complete."
fi
