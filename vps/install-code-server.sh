#!/usr/bin/env bash
set -euo pipefail

# Install code-server (VS Code in the browser).
# Runs on localhost:8080, proxied by Cloudflare Tunnel.

INSTALL_USER="${INSTALL_USER:-deploy}"
CODE_SERVER_VERSION="${CODE_SERVER_VERSION:-latest}"
PORT="${CODE_SERVER_PORT:-8080}"
WORKSPACE_DIR="/opt/coding-workspace"

echo "=== Installing code-server ==="
echo "User:    $INSTALL_USER"
echo "Port:    $PORT"
echo ""

# ─── Install code-server ──────────────────────────────────────────────────────
echo "[1/3] Installing code-server..."
curl -fsSL https://code-server.dev/install.sh | sh -s -- \
    --version "$CODE_SERVER_VERSION" 2>/dev/null
echo "Done. Version: $(code-server --version | head -1)"

# ─── Configure code-server ────────────────────────────────────────────────────
echo "[2/3] Configuring code-server..."
CONFIG_DIR="/home/${INSTALL_USER}/.config/code-server"
mkdir -p "$CONFIG_DIR"

# Generate a random password if not set
if [[ -f "${WORKSPACE_DIR}/.env" ]]; then
    # shellcheck disable=SC1090
    source "${WORKSPACE_DIR}/.env"
fi
CODE_SERVER_PASSWORD="${CODE_SERVER_PASSWORD:-$(openssl rand -base64 18)}"

cat > "${CONFIG_DIR}/config.yaml" << EOF
bind-addr: 127.0.0.1:${PORT}
auth: password
password: ${CODE_SERVER_PASSWORD}
cert: false
EOF
chown -R "${INSTALL_USER}:${INSTALL_USER}" "$CONFIG_DIR"

# Save password to .env if not already there
if [[ -f "${WORKSPACE_DIR}/.env" ]] && ! grep -q "CODE_SERVER_PASSWORD" "${WORKSPACE_DIR}/.env"; then
    echo "CODE_SERVER_PASSWORD=${CODE_SERVER_PASSWORD}" >> "${WORKSPACE_DIR}/.env"
fi

echo "Config written to ${CONFIG_DIR}/config.yaml"

# ─── Install systemd unit ─────────────────────────────────────────────────────
echo "[3/3] Installing systemd service..."
cp "$(dirname "$0")/systemd/code-server.service" /etc/systemd/system/code-server.service
sed -i "s/User=deploy/User=${INSTALL_USER}/" /etc/systemd/system/code-server.service

systemctl daemon-reload
systemctl enable code-server
systemctl start code-server
sleep 2

if systemctl is-active --quiet code-server; then
    echo "code-server is running."
else
    echo "ERROR: code-server failed to start."
    journalctl -u code-server --no-pager --lines 20
    exit 1
fi

echo ""
echo "=== code-server installed ==="
echo "Internal URL: http://127.0.0.1:${PORT}"
echo "Password:     ${CODE_SERVER_PASSWORD}"
echo ""
echo "This password is also in ${WORKSPACE_DIR}/.env"
echo ""
echo "Next: bash vps/install-cloudflared.sh"
