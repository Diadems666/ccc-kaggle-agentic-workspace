# ccc-kaggle-agentic-workspace

Mobile-first agentic coding workspace for Cairns Custom Computers: BinaryLane VPS control plane, Cloudflare-secured coding subdomain, GitHub-first development workflow, and optional Kaggle free T4 GPU inference workers.

## Overview

This workspace enables a complete AI-assisted development environment accessible from any device — phone, tablet, or laptop — using:

- **BinaryLane VPS** as the persistent control plane (Sydney region, low-latency AU)
- **Cloudflare Tunnel + Access** for zero-trust HTTPS access to your coding IDE
- **code-server or OpenVSCode Server** as the browser-based IDE
- **GitHub** as the source of truth for all code and workspace state
- **Kaggle free T4 GPU** as an optional on-demand inference worker (reverse SSH tunnel)
- **Agentic coding tools** — Claude Code, Codex CLI, OpenCode, Aider — running on the VPS

## Architecture Summary

```
Phone/Tablet
    │
    ▼
https://coding.cairnscustomcomputers.cloud   (Cloudflare Access — email auth)
    │
    ▼
Cloudflare Tunnel (cloudflared on VPS)
    │
    ▼
BinaryLane VPS  ──── code-server / OpenVSCode Server
    │                ──── Claude Code / Aider / OpenCode
    │                ──── Local LLM endpoint (when Kaggle tunnel active)
    │
    ▼ (SSH reverse tunnel, ephemeral)
Kaggle Notebook (T4 GPU)
    ──── llama.cpp server or vLLM
    ──── session watchdog (auto-save before timeout)
```

## Quick Start

### 1. Provision the VPS

```bash
# SSH into your BinaryLane VPS as root
ssh root@YOUR_VPS_IP

# Clone this repo
git clone https://github.com/YOUR_ORG/ccc-kaggle-agentic-workspace.git /opt/workspace
cd /opt/workspace

# Run setup scripts in order
bash vps/install-vps.sh
bash vps/create-users.sh
bash vps/harden-ssh.sh
bash vps/setup-workspace.sh
bash vps/install-code-server.sh
bash vps/install-cloudflared.sh
bash vps/install-agent-tools.sh
```

### 2. Configure Cloudflare

1. Create a Cloudflare Tunnel (zero-trust dashboard → Tunnels)
2. Copy the tunnel token into `/etc/cloudflared/config.yml`
3. Add DNS CNAME: `coding` → your tunnel hostname
4. Create an Access Application for `https://coding.cairnscustomcomputers.cloud`
5. Set policy: Allow → your email address

See `vps/cloudflare/access-policy-notes.md` for full instructions.

### 3. Access your IDE

Navigate to `https://coding.cairnscustomcomputers.cloud` from any device. Authenticate with your Cloudflare Access email OTP.

### 4. Optional: Kaggle GPU inference

```bash
# On Kaggle notebook (paste into a code cell)
!bash kaggle/setup_kaggle_gpu_worker.sh
!bash kaggle/reverse_tunnel_to_vps.sh
```

On your VPS, the local LLM will now be reachable at `http://localhost:8080`.

## Directory Structure

```
ccc-kaggle-agentic-workspace/
├── README.md                    ← this file
├── ARCHITECTURE.md              ← detailed system design
├── SECURITY.md                  ← hardening checklist and threat model
├── RUNBOOK.md                   ← day-to-day operations
├── MOBILE_WORKFLOW.md           ← phone/tablet usage guide
├── MODEL_MATRIX.md              ← LLM selection guide
├── TROUBLESHOOTING.md           ← common issues and fixes
├── AGENTS.md                    ← agentic tool configuration
├── TASKS.md                     ← project backlog
├── PROGRESS.md                  ← session log
├── DECISIONS.md                 ← architectural decision records
├── IMPLEMENTATION_NOTES.md      ← technical implementation notes
├── .env.example                 ← environment variable template
├── .gitignore
├── agents/                      ← per-agent setup guides
│   ├── README.md
│   ├── claude-code.md
│   ├── codex-cli.md
│   ├── opencode.md
│   ├── aider.md
│   └── local-kaggle-provider.example.json
├── kaggle/                      ← Kaggle notebook scripts
│   ├── README.md
│   ├── KAGGLE_NOTEBOOK_SETUP.md
│   ├── setup_kaggle_gpu_worker.sh
│   ├── start_llama_server.sh
│   ├── start_vllm_server.sh
│   ├── reverse_tunnel_to_vps.sh
│   ├── session_watchdog.py
│   ├── save_state.sh
│   └── requirements.txt
├── scripts/                     ← VPS utility scripts
│   ├── README.md
│   ├── healthcheck.sh
│   ├── check_gpu_backend.sh
│   ├── start_agent_session.sh
│   ├── stop_agent_session.sh
│   ├── switch_provider.sh
│   ├── sync_repo.sh
│   └── backup_workspace.sh
├── templates/                   ← per-project template files
│   ├── README.md
│   ├── AGENTS.md
│   ├── PROMPT.md
│   ├── TASKS.md
│   ├── PROGRESS.md
│   ├── DECISIONS.md
│   ├── IMPLEMENTATION_NOTES.md
│   └── PROJECT_RUNBOOK.md
└── vps/                         ← VPS provisioning scripts
    ├── README.md
    ├── install-vps.sh
    ├── harden-ssh.sh
    ├── create-users.sh
    ├── install-agent-tools.sh
    ├── install-code-server.sh
    ├── install-openvscode-server.sh
    ├── install-cloudflared.sh
    ├── setup-workspace.sh
    ├── docker-compose.yml
    ├── systemd/
    │   ├── code-server.service
    │   ├── openvscode-server.service
    │   └── cloudflared.service.example
    ├── nginx/
    │   └── coding.conf.example
    └── cloudflare/
        ├── tunnel-config.yml.example
        └── access-policy-notes.md
```

## Environment Variables

Copy `.env.example` to `.env` and fill in your values. **Never commit `.env` to git.**

Key variables:
- `ANTHROPIC_API_KEY` — Claude API key for Claude Code
- `OPENAI_API_KEY` — OpenAI key for Codex CLI (optional)
- `VPS_HOST` — your BinaryLane VPS IP or hostname
- `KAGGLE_TUNNEL_KEY_PATH` — path to SSH private key for Kaggle tunnel
- `CLOUDFLARE_TUNNEL_TOKEN` — from Cloudflare zero-trust dashboard

## Cost Model

| Component | Cost |
|-----------|------|
| BinaryLane VPS (2 vCPU / 2 GB) | ~AUD $10–15/month |
| Cloudflare Tunnel | Free |
| Cloudflare Access | Free (up to 50 users) |
| Kaggle GPU (T4 × 1) | Free (30 GPU-hours/week) |
| Claude API | Pay per token |
| OpenAI API | Pay per token (optional) |

## Security Model

- All IDE traffic is routed through Cloudflare Access (email OTP)
- SSH is key-only, root login disabled after hardening
- Secrets are in `.env` files, never in Git
- Kaggle tunnel uses a dedicated restricted keypair
- See `SECURITY.md` for full hardening checklist

## Contributing

This is a private workspace for Cairns Custom Computers. Keep all credentials out of Git.
