# Progress Log

Session-by-session log of work completed on this workspace.

---

## 2026-06-15 — Initial implementation

**Session goal**: Create and fully implement the workspace repository from scratch.

**Completed**:
- Created complete directory structure
- Implemented all VPS provisioning scripts (`vps/`)
- Implemented all Kaggle GPU scripts (`kaggle/`)
- Implemented all utility scripts (`scripts/`)
- Created agent configuration guides (`agents/`)
- Created project template files (`templates/`)
- Wrote comprehensive documentation (README, ARCHITECTURE, SECURITY, RUNBOOK, MOBILE_WORKFLOW, MODEL_MATRIX, TROUBLESHOOTING, AGENTS)
- Configured `.env.example` and `.gitignore`
- Created systemd unit files and nginx/cloudflare config examples

**Decisions made**:
- code-server as primary IDE (OpenVSCode Server as alternative)
- Cloudflare Tunnel + Access for zero-trust mobile access
- BinaryLane Sydney VPS for AU-low-latency
- Kaggle T4 as free GPU inference option (not primary)
- Claude Sonnet 4.6 as default model

**Next steps**:
- Provision BinaryLane VPS
- Work through TASKS.md Phase 1

---

<!-- Add new sessions below in reverse chronological order -->

## Template for new entries

```
## YYYY-MM-DD — Session topic

**Session goal**: 

**Completed**:
- 

**Issues encountered**:
- 

**Next steps**:
- 
```

---

## 2026-11-02 - Self-hosted agent stack

**Completed**:
- Added Qwen3.8-27B/llama.cpp native build and launcher, `quick_start_v2.py` orchestrator and notebooks (`kaggle/`)
- Added VPS agent stack: LiteLLM gateway, SearXNG, OpenHands, hardened sshd drop-in, installer (`vps/agent-stack/`)
- Added research tools and skills (`research/`, `.agents/skills/`), status script, 18 pytest tests
- Patched `kaggle/reverse_tunnel_to_vps.sh` (`VPS_TUNNEL_BIND`, optional host-key pinning)
- Wrote `docs/KAGGLE_QWEN38_AGENT.md`, ADR-007, TASKS Phase 7

**Not verified (needs real hardware)**: CUDA build on Kaggle, llama-server flags, tok/s, sshd PermitListen behaviour, container image tags, OpenHands LLM settings.

**Next steps**: Phase 7 checklist in `TASKS.md`.
