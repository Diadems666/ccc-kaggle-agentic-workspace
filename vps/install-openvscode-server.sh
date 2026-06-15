#!/usr/bin/env bash
set -euo pipefail

# Install OpenVSCode Server as an alternative to code-server.
# Runs on localhost:3000. Auth is handled entirely by Cloudflare Access.

INSTALL_USER="${INSTALL_USER:-deploy}"
OVSC_VERSION="${OVSC_VERSION:-1.93.1}"
PORT="${OPENVSCODE_PORT:-3000}"
INSTALL_DIR="/opt/openvscode-server"

echo "=== Installing OpenVSCode Server ==="
echo "Version: $OVSC_VERSION"
echo "Port:    $PORT"
echo ""

ARCH=$(dpkg --print-architecture)
case "$ARCH" in
    amd64) ARCH_SUFFIX="x64" ;;
    arm64) ARCH_SUFFIX="arm64" ;;
    *) echo "Unsupported arch: $ARCH"; exit 1 ;;
esac

TARBALL="openvscode-server-v${OVSC_VERSION}-linux-${ARCH_SUFFIX}.tar.gz"
DOWNLOAD_URL="https://github.com/gitpod-io/openvscode-server/releases/download/openvscode-server-v${OVSC_VERSION}/${TARBALL}"

echo "[1/3] Downloading OpenVSCode Server..."
mkdir -p "$INSTALL_DIR"
curl -fsSL "$DOWNLOAD_URL" | tar -xz --strip-components=1 -C "$INSTALL_DIR"
chown -R "${INSTALL_USER}:${INSTALL_USER}" "$INSTALL_DIR"
echo "Installed to $INSTALL_DIR"

echo "[2/3] Installing systemd service..."
cp "$(dirname "$0")/systemd/openvscode-server.service" /etc/systemd/system/openvscode-server.service
sed -i "s/User=deploy/User=${INSTALL_USER}/" /etc/systemd/system/openvscode-server.service
sed -i "s|/opt/openvscode-server|${INSTALL_DIR}|g" /etc/systemd/system/openvscode-server.service
sed -i "s/3000/${PORT}/g" /etc/systemd/system/openvscode-server.service

systemctl daemon-reload
systemctl enable openvscode-server
systemctl start openvscode-server
sleep 2

if systemctl is-active --quiet openvscode-server; then
    echo "[3/3] openvscode-server is running on port ${PORT}."
else
    echo "ERROR: openvscode-server failed to start."
    journalctl -u openvscode-server --no-pager --lines 20
    exit 1
fi

echo ""
echo "=== OpenVSCode Server installed ==="
echo "Internal URL: http://127.0.0.1:${PORT}"
echo "Auth:         via Cloudflare Access (no password needed)"
echo ""
echo "To use instead of code-server, update Cloudflare Tunnel config:"
echo "  service: http://localhost:${PORT}"
