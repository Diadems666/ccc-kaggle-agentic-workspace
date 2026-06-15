#!/usr/bin/env bash
set -euo pipefail

# Base VPS setup for Ubuntu 24.04.
# Install system packages, Node.js 20, Python 3, and essential tools.
# Run as root on a fresh VPS.

echo "=== CCC VPS Base Setup ==="
echo "Ubuntu version: $(lsb_release -rs)"
echo ""

# ─── Update system ────────────────────────────────────────────────────────────
echo "[1/5] Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq \
    curl wget git vim htop tmux \
    build-essential cmake \
    python3 python3-pip python3-venv \
    ufw fail2ban \
    unzip jq tree \
    openssh-server \
    ca-certificates gnupg lsb-release \
    software-properties-common apt-transport-https

echo "Done."

# ─── Install Node.js 20 ───────────────────────────────────────────────────────
echo "[2/5] Installing Node.js 20 LTS..."
if ! command -v node &>/dev/null || [[ "$(node --version | cut -d. -f1 | tr -d 'v')" -lt 20 ]]; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y -qq nodejs
fi
echo "Node: $(node --version)"
echo "npm:  $(npm --version)"

# ─── Configure firewall ───────────────────────────────────────────────────────
echo "[3/5] Configuring ufw firewall..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH'
ufw --force enable
echo "ufw status:"
ufw status

# ─── Configure fail2ban ───────────────────────────────────────────────────────
echo "[4/5] Configuring fail2ban..."
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port    = 22
EOF
systemctl enable fail2ban
systemctl restart fail2ban
echo "Done."

# ─── Configure unattended upgrades ────────────────────────────────────────────
echo "[5/5] Enabling unattended security upgrades..."
apt-get install -y -qq unattended-upgrades
cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
echo "Done."

echo ""
echo "=== Base setup complete ==="
echo "Next: bash vps/create-users.sh"
