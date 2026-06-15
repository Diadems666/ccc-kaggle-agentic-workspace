#!/usr/bin/env bash
set -euo pipefail

# Create a timestamped backup of the workspace.
# Excludes node_modules, .git, model files, and secrets.

WORKSPACE_DIR="${WORKSPACE_DIR:-/opt/coding-workspace}"
BACKUP_DIR="${BACKUP_DIR:-${WORKSPACE_DIR}/backups}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="${BACKUP_DIR}/workspace_${TIMESTAMP}.tar.gz"

echo "=== Workspace Backup ==="
echo "Source:  $WORKSPACE_DIR"
echo "Dest:    $BACKUP_FILE"
echo ""

mkdir -p "$BACKUP_DIR"

tar -czf "$BACKUP_FILE" \
    --exclude="${WORKSPACE_DIR}/backups" \
    --exclude="*/.git" \
    --exclude="*/node_modules" \
    --exclude="*/__pycache__" \
    --exclude="*.gguf" \
    --exclude="*.bin" \
    --exclude="*.safetensors" \
    --exclude="*/.env" \
    --exclude="*/models" \
    -C "$(dirname "$WORKSPACE_DIR")" \
    "$(basename "$WORKSPACE_DIR")"

SIZE=$(du -sh "$BACKUP_FILE" | awk '{print $1}')
echo "Backup created: $BACKUP_FILE ($SIZE)"
echo ""

# Clean up old backups (keep last 7)
BACKUP_COUNT=$(ls -1 "${BACKUP_DIR}"/workspace_*.tar.gz 2>/dev/null | wc -l)
if [[ $BACKUP_COUNT -gt 7 ]]; then
    echo "Removing old backups (keeping last 7)..."
    ls -1t "${BACKUP_DIR}"/workspace_*.tar.gz | tail -n +8 | xargs rm -f
    echo "Done."
fi

echo ""
echo "=== Backup complete ==="
echo "Note: .env secrets are excluded from backups. Store them separately."
