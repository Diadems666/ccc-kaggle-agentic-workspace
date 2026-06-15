#!/usr/bin/env bash
set -euo pipefail

# Harden SSH configuration.
# Run ONLY after verifying you can SSH as the deploy user with your key.
# This script disables root login and password auth.

echo "=== SSH Hardening ==="
echo ""
echo "WARNING: This will disable root login and password authentication."
echo "Ensure you can SSH as 'deploy' with your key BEFORE running this."
echo ""
read -rp "Have you verified SSH access as deploy? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
    echo "Aborting. Run this script again after verifying deploy SSH access."
    exit 1
fi

SSHD_CONFIG="/etc/ssh/sshd_config"

# Backup original
cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak.$(date +%Y%m%d_%H%M%S)"
echo "Backed up sshd_config."

# Apply hardening settings
apply_setting() {
    local KEY="$1"
    local VALUE="$2"
    if grep -q "^${KEY}" "$SSHD_CONFIG"; then
        sed -i "s/^${KEY}.*/${KEY} ${VALUE}/" "$SSHD_CONFIG"
    elif grep -q "^#${KEY}" "$SSHD_CONFIG"; then
        sed -i "s/^#${KEY}.*/${KEY} ${VALUE}/" "$SSHD_CONFIG"
    else
        echo "${KEY} ${VALUE}" >> "$SSHD_CONFIG"
    fi
}

apply_setting "PermitRootLogin" "no"
apply_setting "PasswordAuthentication" "no"
apply_setting "PubkeyAuthentication" "yes"
apply_setting "AuthorizedKeysFile" ".ssh/authorized_keys"
apply_setting "MaxAuthTries" "3"
apply_setting "ClientAliveInterval" "300"
apply_setting "ClientAliveCountMax" "2"
apply_setting "X11Forwarding" "no"
apply_setting "PrintMotd" "no"

echo "SSH settings applied."

# Test config before reloading
if sshd -t; then
    systemctl reload sshd
    echo ""
    echo "=== SSH hardened ==="
    echo "  Root login:     disabled"
    echo "  Password auth:  disabled"
    echo "  Key auth:       enabled"
    echo ""
    echo "From now on, SSH access requires a private key."
else
    echo "ERROR: sshd config test failed. Restoring backup..."
    cp "${SSHD_CONFIG}.bak."* "$SSHD_CONFIG"
    echo "Restored. SSH config unchanged."
    exit 1
fi
