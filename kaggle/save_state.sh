#!/usr/bin/env bash
set -euo pipefail

# Save workspace state before Kaggle session expires.
# Commits any uncommitted changes and pushes to GitHub.
# Called by session_watchdog.py automatically.

WORKSPACE_DIR="${WORKSPACE_DIR:-/tmp/ws}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
BRANCH="${SAVE_BRANCH:-kaggle-checkpoint}"

echo "=== Saving workspace state ==="
echo "Workspace: $WORKSPACE_DIR"
echo "Branch:    $BRANCH"
echo ""

if [[ ! -d "$WORKSPACE_DIR/.git" ]]; then
    echo "WARNING: $WORKSPACE_DIR is not a git repository. Nothing to save."
    exit 0
fi

cd "$WORKSPACE_DIR"

# Configure git if not already set
git config user.email "kaggle-worker@cairnscustomcomputers.cloud" 2>/dev/null || true
git config user.name "Kaggle Worker" 2>/dev/null || true

# Ensure we're on the right branch
CURRENT_BRANCH=$(git branch --show-current)
echo "Current branch: $CURRENT_BRANCH"

# Stage all changes
if git diff --quiet && git diff --staged --quiet; then
    echo "No changes to commit."
else
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    git add -A
    git commit -m "checkpoint: kaggle session save at $TIMESTAMP" || true
    echo "Changes committed."
fi

# Push to GitHub
echo "Pushing to GitHub..."
if [[ -n "$GITHUB_TOKEN" ]]; then
    # Use token-based auth
    REPO_URL=$(git remote get-url origin)
    REPO_URL_WITH_TOKEN=$(echo "$REPO_URL" | sed "s|https://|https://$GITHUB_TOKEN@|")
    git push "$REPO_URL_WITH_TOKEN" HEAD:"$CURRENT_BRANCH" || {
        echo "Push to $CURRENT_BRANCH failed. Trying $BRANCH..."
        git push "$REPO_URL_WITH_TOKEN" HEAD:"$BRANCH" || echo "Push failed."
    }
else
    git push origin HEAD:"$CURRENT_BRANCH" || {
        echo "Push failed (no GITHUB_TOKEN?). State saved locally only."
    }
fi

echo ""
echo "=== State save complete ==="
