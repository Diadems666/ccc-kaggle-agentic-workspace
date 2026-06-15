# Security

## Threat Model

| Threat | Mitigation |
|--------|------------|
| Unauthorised IDE access | Cloudflare Access email OTP on all traffic |
| SSH brute force | Key-only auth, fail2ban, ufw whitelist |
| API key leakage | Keys in `.env` only, `.gitignore` enforced |
| Kaggle tunnel abuse | Restricted keypair, VPS firewall blocks external access to port 8081 |
| Secrets in git history | Pre-commit hook scans for keys (see below) |
| VPS compromise | Minimal attack surface, no inbound ports except SSH |
| Session hijacking | Cloudflare JWT validates every request |

## VPS Hardening Checklist

Run `vps/harden-ssh.sh` to apply these automatically, then verify:

- [ ] `PasswordAuthentication no` in `/etc/ssh/sshd_config`
- [ ] `PermitRootLogin no` (after creating deploy user)
- [ ] `PubkeyAuthentication yes`
- [ ] `AllowUsers deploy` (restrict SSH to named users)
- [ ] `MaxAuthTries 3`
- [ ] `ClientAliveInterval 300`
- [ ] fail2ban installed and monitoring SSH
- [ ] ufw enabled: allow 22/tcp, deny everything else inbound
- [ ] Unattended upgrades enabled for security patches
- [ ] `/etc/motd` cleared (don't advertise OS version)

## Cloudflare Access Configuration

1. Go to: Cloudflare Zero Trust → Access → Applications
2. Create application:
   - Type: Self-hosted
   - App domain: `coding.cairnscustomcomputers.cloud`
   - Session duration: 24h (adjust to taste)
3. Create policy:
   - Action: Allow
   - Rule: Emails → `joe.venner@hotmail.com` (your address)
4. Disable public access (do NOT add a Bypass rule)

The Cloudflare JWT is validated on every request. Even if someone guesses your tunnel hostname, they cannot access the IDE without completing the email OTP.

## SSH Key Management

### VPS access key
```bash
# Generate on your local machine (not on VPS)
ssh-keygen -t ed25519 -C "vps-access-$(date +%Y%m)" -f ~/.ssh/vps_ed25519
# Copy to VPS
ssh-copy-id -i ~/.ssh/vps_ed25519.pub deploy@YOUR_VPS_IP
```

### Kaggle tunnel key (restricted)
```bash
# Generate a dedicated keypair for Kaggle → VPS tunnel only
ssh-keygen -t ed25519 -C "kaggle-tunnel-$(date +%Y%m)" -f ~/.ssh/kaggle_tunnel_ed25519 -N ""

# On VPS: add to kaggle-gpu user with command restriction
# In /home/kaggle-gpu/.ssh/authorized_keys:
# command="echo 'port forwarding only'",no-pty,no-agent-forwarding,no-X11-forwarding ssh-ed25519 AAAA...

# Store private key as Kaggle notebook secret (never in Git)
```

## Secret Management

### What goes where

| Secret | Storage | How accessed |
|--------|---------|--------------|
| `ANTHROPIC_API_KEY` | VPS `.env` | Read by agent tools at runtime |
| `OPENAI_API_KEY` | VPS `.env` | Read by agent tools at runtime |
| VPS SSH private key | Local `~/.ssh/` | SSH client |
| Kaggle tunnel private key | Kaggle notebook secret | Notebook environment variable |
| Cloudflare tunnel token | VPS `/etc/cloudflared/config.yml` | cloudflared daemon |
| code-server password | VPS `.env` | Browser login |

### Rotation schedule

- API keys: rotate every 90 days or immediately if suspected compromise
- SSH keys: rotate on personnel change or annually
- code-server password: rotate on device loss or annually
- Cloudflare tunnel token: rotate on VPS rebuild

## Git Security

### `.gitignore` (enforced)
```
.env
*.env
.env.*
!.env.example
*.pem
*.key
*_rsa
*_ed25519
!*_ed25519.pub
*.p12
*.pfx
kaggle-tunnel-*
!kaggle-tunnel-*.pub
```

### Pre-commit secret scanning

Install `gitleaks` on the VPS to scan before every commit:

```bash
# Install
curl -sSL https://github.com/gitleaks/gitleaks/releases/latest/download/gitleaks_linux_amd64.tar.gz | tar xz -C /usr/local/bin/

# Add pre-commit hook (in your git repo)
cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash
gitleaks protect --staged --redact
EOF
chmod +x .git/hooks/pre-commit
```

## Network Security

### VPS firewall rules (ufw)
```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH'
ufw enable
```

**No other inbound ports are opened.** The browser IDE is accessed via Cloudflare Tunnel (outbound connection from VPS), so port 8080/3000 never needs to be open publicly.

### Cloudflare Tunnel security

- Tunnel connection is outbound-only from VPS
- Tunnel token is specific to one account and tunnel
- Even if the VPS IP leaks, direct port access is blocked by ufw
- Cloudflare validates the JWT before proxying any request

## Incident Response

### Suspected API key compromise
1. Immediately revoke the key in the provider's dashboard
2. Generate a new key
3. Update VPS `.env`: `nano /opt/coding-workspace/.env`
4. Restart any running agent sessions: `scripts/stop_agent_session.sh && scripts/start_agent_session.sh`
5. Review API usage logs for unauthorised charges

### Suspected VPS compromise
1. Immediately revoke all SSH keys in BinaryLane console
2. Snapshot the disk for forensics
3. Rebuild from scratch using this repo's VPS scripts
4. Rotate all secrets that were stored on the VPS

### Suspected Cloudflare tunnel token compromise
1. Delete the tunnel in Cloudflare Zero Trust dashboard (invalidates the token)
2. Create a new tunnel and update `/etc/cloudflared/config.yml` on VPS
3. Restart cloudflared: `systemctl restart cloudflared`
