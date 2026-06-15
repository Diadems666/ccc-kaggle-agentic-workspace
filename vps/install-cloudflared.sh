#!/usr/bin/env bash
set -euo pipefail

# Install Cloudflare Tunnel daemon (cloudflared).
# The tunnel exposes code-server to https://coding.cairnscustomcomputers.cloud.

WORKSPACE_DIR="/opt/coding-workspace"
CONFIG_DIR="/etc/cloudflared"

echo "=== Installing cloudflared ==="

# ─── Install cloudflared ──────────────────────────────────────────────────────
echo "[1/3] Installing cloudflared..."
ARCH=$(dpkg --print-architecture)
CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}"
curl -fsSL "$CLOUDFLARED_URL" -o /usr/local/bin/cloudflared
chmod +x /usr/local/bin/cloudflared
echo "cloudflared version: $(cloudflared --version)"

# ─── Configure tunnel ─────────────────────────────────────────────────────────
echo "[2/3] Writing tunnel config..."
mkdir -p "$CONFIG_DIR"

# Load tunnel token from .env if available
CLOUDFLARE_TUNNEL_TOKEN=""
if [[ -f "${WORKSPACE_DIR}/.env" ]]; then
    # shellcheck disable=SC1090
    source "${WORKSPACE_DIR}/.env"
fi

if [[ -z "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]]; then
    echo ""
    echo "Paste your Cloudflare Tunnel token (from Zero Trust → Tunnels → Configure → Token):"
    read -r CLOUDFLARE_TUNNEL_TOKEN
fi

cat > "${CONFIG_DIR}/config.yml" << EOF
tunnel: ${CLOUDFLARE_TUNNEL_TOKEN}
credentials-file: /etc/cloudflared/.credentials.json

ingress:
  - hostname: coding.cairnscustomcomputers.cloud
    service: http://localhost:8080
  - service: http_status:404
EOF
chmod 600 "${CONFIG_DIR}/config.yml"
echo "Config written to ${CONFIG_DIR}/config.yml"

# ─── Install systemd service ──────────────────────────────────────────────────
echo "[3/3] Installing systemd service..."
cloudflared service install "$CLOUDFLARE_TUNNEL_TOKEN"
systemctl enable cloudflared
systemctl start cloudflared
sleep 3

if systemctl is-active --quiet cloudflared; then
    echo "cloudflared is running."
else
    echo "cloudflared may still be initialising. Check with:"
    echo "  sudo systemctl status cloudflared"
    echo "  journalctl -u cloudflared -f"
fi

echo ""
echo "=== cloudflared installed ==="
echo "Tunnel points to: http://localhost:8080 (code-server)"
echo ""
echo "Remember to:"
echo "  1. Add DNS CNAME: coding → YOUR_TUNNEL_ID.cfargotunnel.com"
echo "  2. Create Cloudflare Access Application for your domain"
echo "  3. Set Access policy to allow your email"
echo ""
echo "See vps/cloudflare/access-policy-notes.md for full instructions."
echo ""
echo "Next: bash vps/install-agent-tools.sh"
