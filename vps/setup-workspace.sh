#!/usr/bin/env bash
set -euo pipefail

# Create the /opt/coding-workspace/ directory structure.
# Run as root.

WORKSPACE_DIR="/opt/coding-workspace"
DEPLOY_USER="deploy"

echo "=== Setting up workspace: $WORKSPACE_DIR ==="

mkdir -p "${WORKSPACE_DIR}"/{repos,backups,logs}
mkdir -p "${WORKSPACE_DIR}/.config"

# Copy .env.example as a starting point
if [[ ! -f "${WORKSPACE_DIR}/.env" ]] && [[ -f "$(dirname "$0")/../.env.example" ]]; then
    cp "$(dirname "$0")/../.env.example" "${WORKSPACE_DIR}/.env"
    echo "Copied .env.example to ${WORKSPACE_DIR}/.env — fill in your values."
else
    echo ".env already exists or template not found."
fi

# Set ownership
chown -R "${DEPLOY_USER}:${DEPLOY_USER}" "${WORKSPACE_DIR}"
chmod 750 "${WORKSPACE_DIR}"
chmod 600 "${WORKSPACE_DIR}/.env" 2>/dev/null || true

echo ""
echo "=== Workspace structure created ==="
echo "${WORKSPACE_DIR}/"
echo "├── repos/      — git checkouts"
echo "├── backups/    — workspace snapshots"
echo "├── logs/       — agent session logs"
echo "├── .config/    — tool configs"
echo "└── .env        — secrets (fill this in!)"
echo ""
echo "Next: bash vps/install-code-server.sh"
