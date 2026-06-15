# Architecture

## System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        CLIENT DEVICES                           │
│   iPhone/iPad   Android phone   Laptop browser   Desktop IDE   │
└────────────────────────────┬────────────────────────────────────┘
                             │ HTTPS (port 443)
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                    CLOUDFLARE EDGE                               │
│   DNS: coding.cairnscustomcomputers.cloud                       │
│   Cloudflare Access: email OTP authentication                   │
│   Cloudflare Tunnel: zero-trust egress to VPS                  │
└────────────────────────────┬────────────────────────────────────┘
                             │ Tunnel (outbound from VPS)
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                    BINARYLANE VPS (Ubuntu 24.04)                │
│                                                                  │
│   ┌─────────────────┐   ┌─────────────────────────────────┐   │
│   │  code-server    │   │  Agent Tools                    │   │
│   │  (port 8080)    │   │  claude-code (npm global)       │   │
│   │  OR             │   │  aider (pip)                    │   │
│   │  openvscode     │   │  opencode (npm global)          │   │
│   │  (port 3000)    │   │  codex-cli (npm global)         │   │
│   └─────────────────┘   └─────────────────────────────────┘   │
│                                                                  │
│   ┌─────────────────┐   ┌─────────────────────────────────┐   │
│   │  cloudflared    │   │  LLM Proxy (optional)           │   │
│   │  systemd unit   │   │  localhost:8081 → Kaggle GPU    │   │
│   └─────────────────┘   └─────────────────────────────────┘   │
│                                                                  │
│   /opt/coding-workspace/                                        │
│   ├── repos/          (git workspaces)                         │
│   ├── .env            (secrets)                                 │
│   └── backups/        (workspace snapshots)                    │
└────────────────────────────┬────────────────────────────────────┘
                             │ SSH reverse tunnel (ephemeral)
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                    KAGGLE NOTEBOOK (T4 GPU)                     │
│                                                                  │
│   ┌─────────────────────────────────────────────────────────┐  │
│   │  llama.cpp server (port 8080) or vLLM (port 8000)      │  │
│   │  Model: Qwen2.5-Coder-7B-Q4, DeepSeek-Coder-7B, etc.  │  │
│   └─────────────────────────────────────────────────────────┘  │
│                                                                  │
│   session_watchdog.py  (saves state before 12h timeout)        │
│   reverse_tunnel_to_vps.sh  (SSH -R to VPS port 8081)         │
└─────────────────────────────────────────────────────────────────┘
```

## Component Responsibilities

### BinaryLane VPS

The VPS is the persistent hub. It runs 24/7 and holds:
- The browser IDE (code-server or OpenVSCode Server)
- All agentic tools pre-installed
- The workspace git checkout
- Cloudflare tunnel daemon

The VPS does **not** run the LLM directly (it may only have 2 GB RAM). Instead it proxies requests to Kaggle when the tunnel is active, or routes to the Anthropic/OpenAI API otherwise.

### Cloudflare Tunnel + Access

Cloudflare terminates the TLS and enforces authentication before any traffic reaches the VPS. The tunnel is outbound-only from the VPS perspective — no inbound ports need to be opened on the VPS firewall.

Authentication: Cloudflare Access sends a one-time code to the configured email address. No passwords stored anywhere.

### Kaggle T4 GPU Worker

Kaggle notebooks are ephemeral (12-hour session limit). The setup pattern is:

1. Notebook starts → installs dependencies → downloads model weights
2. Starts LLM server on port 8080
3. Opens reverse SSH tunnel: `ssh -R 8081:localhost:8080 kaggle-gpu@VPS_IP`
4. Session watchdog monitors time remaining and saves checkpoint before expiry

The VPS then forwards local port 8081 traffic to the Kaggle GPU. Agents configured with `base_url=http://localhost:8081/v1` transparently use the GPU.

### GitHub as Source of Truth

All project code lives in GitHub. The VPS workspace is a checkout — it can be wiped and re-cloned without data loss. Secrets are the only thing not in GitHub (stored in VPS `.env` files and managed separately).

## Data Flows

### Coding session (API-backed)

```
Browser IDE → VPS shell → claude-code → Anthropic API → response
                                      ↕
                                    git push → GitHub
```

### Coding session (local GPU)

```
Browser IDE → VPS shell → aider/claude-code → localhost:8081 → Kaggle T4
                                                               ↕ (SSH tunnel)
                                                            vLLM / llama.cpp
```

### Workspace persistence

```
VPS /opt/coding-workspace/repos/ → git commit → git push → GitHub
                                 → backup_workspace.sh → /opt/coding-workspace/backups/
```

## Networking

| Port | Service | Exposure |
|------|---------|----------|
| 22 | SSH (VPS) | Public (key-only) |
| 8080 | code-server | Localhost only (proxied by cloudflared) |
| 3000 | openvscode-server | Localhost only (proxied by cloudflared) |
| 8081 | Kaggle LLM proxy | Localhost only |
| 443 | Cloudflare Tunnel | Cloudflare edge only |

The VPS firewall (ufw) blocks all inbound except port 22. Everything else reaches the VPS via the outbound Cloudflare tunnel.

## Failure Modes

| Failure | Impact | Recovery |
|---------|--------|----------|
| VPS reboots | IDE and agents unavailable | systemd units auto-start |
| Cloudflare tunnel drops | IDE unreachable | cloudflared auto-reconnects |
| Kaggle session expires | No local GPU | Switch to API provider |
| GitHub down | Can't push | Work locally, push later |
| API key exhausted | Agent tool fails | Switch provider with switch_provider.sh |

## Scalability

This architecture is designed for a single developer or small team. For scaling:
- Add more VPS nodes and load balance via Cloudflare
- Use a persistent GPU cloud (Lambda Labs, RunPod) instead of Kaggle
- Add a shared secret manager (Vault, 1Password Secrets Automation) instead of per-VPS `.env` files
