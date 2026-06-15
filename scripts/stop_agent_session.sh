#!/usr/bin/env bash
set -euo pipefail

# Stop active agent sessions gracefully.
# Kills running agent processes and optionally saves state.

echo "=== Stopping Agent Session ==="

# Kill running agent processes
KILLED=0
for AGENT in claude aider opencode codex; do
    PIDS=$(pgrep -f "^$AGENT" 2>/dev/null || true)
    if [[ -n "$PIDS" ]]; then
        echo "Stopping $AGENT (PIDs: $PIDS)..."
        kill $PIDS 2>/dev/null || true
        KILLED=$((KILLED+1))
    fi
done

if [[ $KILLED -eq 0 ]]; then
    echo "No active agent processes found."
fi

echo ""
echo "Remember to commit and push your work:"
echo "  git add -A && git commit -m 'wip: end of session' && git push"
