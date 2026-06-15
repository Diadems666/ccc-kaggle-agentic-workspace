# VPS Setup Scripts

Scripts to provision and configure a BinaryLane VPS as the coding workspace control plane.

## Run Order

Run these as root on a fresh Ubuntu 24.04 VPS:

```bash
bash vps/install-vps.sh           # system packages, Node, Python
bash vps/create-users.sh          # deploy + kaggle-gpu users
bash vps/harden-ssh.sh            # disable root/password SSH login
bash vps/setup-workspace.sh       # /opt/coding-workspace/ structure
bash vps/install-code-server.sh   # code-server IDE
bash vps/install-cloudflared.sh   # Cloudflare Tunnel daemon
bash vps/install-agent-tools.sh   # Claude Code, Aider, OpenCode, Codex CLI
```

Optional:
```bash
bash vps/install-openvscode-server.sh   # alternative to code-server
```

## Files

| File | Purpose |
|------|---------|
| `install-vps.sh` | Base system setup |
| `create-users.sh` | Create deploy and kaggle-gpu system users |
| `harden-ssh.sh` | SSH hardening (run after adding your key) |
| `setup-workspace.sh` | Create workspace directory structure |
| `install-code-server.sh` | Install and configure code-server |
| `install-openvscode-server.sh` | Install OpenVSCode Server (alternative IDE) |
| `install-cloudflared.sh` | Install Cloudflare Tunnel daemon |
| `install-agent-tools.sh` | Install all AI agent tools |
| `docker-compose.yml` | Optional Docker services |
| `systemd/` | systemd unit files |
| `nginx/` | nginx config examples |
| `cloudflare/` | Cloudflare config examples |

## Prerequisites

- Ubuntu 24.04 LTS VPS (BinaryLane Sydney recommended)
- Root SSH access
- Your SSH public key ready to paste
- Cloudflare Tunnel token (from Cloudflare Zero Trust dashboard)
