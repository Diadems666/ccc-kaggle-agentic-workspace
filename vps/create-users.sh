#!/usr/bin/env bash
set -euo pipefail

# Create system users for the workspace.
# - deploy: main user for coding sessions and agent tools
# - kaggle-gpu: restricted user for SSH tunnel from Kaggle notebooks

echo "=== Creating VPS Users ==="

# ─── deploy user ──────────────────────────────────────────────────────────────
echo "[1/2] Creating deploy user..."
if id deploy &>/dev/null; then
    echo "  deploy user already exists."
else
    useradd -m -s /bin/bash -G sudo deploy
    echo "  deploy user created."
fi

# Set up SSH for deploy
mkdir -p /home/deploy/.ssh
chmod 700 /home/deploy/.ssh

echo ""
echo "Paste your SSH public key for the deploy user, then press Ctrl+D:"
cat >> /home/deploy/.ssh/authorized_keys
chmod 600 /home/deploy/.ssh/authorized_keys
chown -R deploy:deploy /home/deploy/.ssh
echo ""
echo "  SSH key added for deploy user."

# ─── kaggle-gpu user ──────────────────────────────────────────────────────────
echo "[2/2] Creating kaggle-gpu user (restricted tunnel user)..."
if id kaggle-gpu &>/dev/null; then
    echo "  kaggle-gpu user already exists."
else
    useradd -m -s /bin/false kaggle-gpu
    echo "  kaggle-gpu user created (no shell — tunnel only)."
fi

mkdir -p /home/kaggle-gpu/.ssh
chmod 700 /home/kaggle-gpu/.ssh

echo ""
echo "Paste your Kaggle TUNNEL public key (separate from your main SSH key) for the kaggle-gpu user."
echo "Format it with the restriction prefix:"
echo 'command="echo tunnel only",no-pty,no-agent-forwarding,no-X11-forwarding ssh-ed25519 AAAA...'
echo ""
echo "Paste now, then press Ctrl+D:"
cat >> /home/kaggle-gpu/.ssh/authorized_keys
chmod 600 /home/kaggle-gpu/.ssh/authorized_keys
chown -R kaggle-gpu:kaggle-gpu /home/kaggle-gpu/.ssh
echo ""
echo "  SSH key added for kaggle-gpu user."

# Update /etc/ssh/sshd_config to allow both users
if ! grep -q "AllowUsers" /etc/ssh/sshd_config; then
    echo "AllowUsers deploy kaggle-gpu" >> /etc/ssh/sshd_config
else
    # Add kaggle-gpu if not already there
    sed -i 's/^AllowUsers .*/& kaggle-gpu/' /etc/ssh/sshd_config
    sed -i 's/^AllowUsers .*/& deploy/' /etc/ssh/sshd_config
fi

# Allow reverse tunnels for kaggle-gpu
if ! grep -q "GatewayPorts" /etc/ssh/sshd_config; then
    echo "" >> /etc/ssh/sshd_config
    echo "# Allow reverse tunnel from Kaggle" >> /etc/ssh/sshd_config
    echo "GatewayPorts no" >> /etc/ssh/sshd_config
fi

systemctl reload sshd

echo ""
echo "=== Users created ==="
echo "  deploy    — coding sessions, agent tools, sudo access"
echo "  kaggle-gpu — SSH tunnel only, no shell"
echo ""
echo "Next: bash vps/harden-ssh.sh"
echo "NOTE: Make sure you can SSH as 'deploy' before running harden-ssh.sh!"
