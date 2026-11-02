# Architectural Decision Records

A log of significant decisions made in building this workspace.

---

## ADR-001: Cloudflare Tunnel over direct VPS access

**Date**: 2026-06-15  
**Status**: Accepted

**Context**: The IDE needs to be securely accessible from mobile devices without a VPN app or complex client setup.

**Decision**: Use Cloudflare Tunnel (cloudflared) + Cloudflare Access for zero-trust HTTPS access.

**Consequences**:
- ✅ No inbound firewall ports needed on VPS
- ✅ Email OTP authentication with no additional app
- ✅ Works on any mobile browser
- ✅ Free tier covers this use case
- ⚠️ All traffic passes through Cloudflare infrastructure (acceptable for coding workspace)
- ⚠️ Requires internet — no offline fallback for IDE

**Alternatives considered**:
- Tailscale: requires app install on all devices, more complex
- WireGuard: requires VPN client, complex for mobile
- Direct HTTPS with nginx + Let's Encrypt: inbound port 443 must be open

---

## ADR-002: code-server as primary IDE

**Date**: 2026-06-15  
**Status**: Accepted

**Context**: Need a full-featured coding IDE accessible in mobile browser.

**Decision**: Use code-server (VS Code in browser) as the primary IDE, with OpenVSCode Server as an alternative.

**Consequences**:
- ✅ Full VS Code extension ecosystem
- ✅ Familiar keyboard shortcuts
- ✅ Works in any modern browser
- ✅ Active development and community
- ⚠️ Some VS Code extensions don't work in code-server (proprietary extensions)
- ⚠️ Higher memory usage than simpler editors (~300 MB)

**Alternatives considered**:
- OpenVSCode Server: similar but upstream VS Code, slightly better extension compat
- Theia: heavier, less VS Code-compatible
- Jupyter Lab: great for notebooks but not general coding
- Zed: no browser version

---

## ADR-003: Kaggle T4 as optional inference worker

**Date**: 2026-06-15  
**Status**: Accepted

**Context**: Local LLM inference enables free, privacy-preserving code assistance without API costs.

**Decision**: Use Kaggle's free T4 GPU notebook as an ephemeral inference worker connected via SSH reverse tunnel.

**Consequences**:
- ✅ Free T4 GPU (16 GB VRAM) — no cost
- ✅ Runs 7B code models well
- ✅ Data stays within the tunnel (no third-party API)
- ⚠️ 12-hour session limit requires restarts
- ⚠️ 30 GPU-hours/week quota limits daily use
- ⚠️ Model download time (~5 min) on each session start
- ⚠️ Slower inference than cloud APIs

**Alternatives considered**:
- Lambda Labs A10 ($0.60/hr): better but costs money
- RunPod: similar to Lambda, costs money
- Local GPU on own hardware: not available for mobile scenario
- Colab: free tier doesn't allow SSH tunnels

---

## ADR-004: BinaryLane Sydney region

**Date**: 2026-06-15  
**Status**: Accepted

**Context**: VPS location affects latency for Australian users.

**Decision**: Use BinaryLane's Sydney region for the control plane VPS.

**Consequences**:
- ✅ Lowest latency from Australia (~10 ms from major AU cities)
- ✅ Australian company, AU data sovereignty
- ✅ Competitive pricing in AUD
- ⚠️ Less global than AWS/GCP/Azure — fewer regions if we need to expand

**Alternatives considered**:
- Vultr Sydney: similar latency, slightly higher cost
- AWS ap-southeast-2: higher cost at this scale
- DigitalOcean Sydney: similar, but BinaryLane has better AU pricing

---

## ADR-005: GitHub as primary source of truth

**Date**: 2026-06-15  
**Status**: Accepted

**Context**: Workspace state must survive VPS rebuilds and be accessible from any device.

**Decision**: All code and non-secret workspace state is stored in GitHub. VPS is stateless (scripts + secrets only).

**Consequences**:
- ✅ VPS can be rebuilt without data loss
- ✅ History, blame, and rollback via git
- ✅ GitHub mobile app for code review on phone
- ✅ Free private repos for individuals
- ⚠️ Requires internet to push/pull
- ⚠️ Secrets must be managed separately from code

**Alternatives considered**:
- GitLab self-hosted: possible, adds VPS complexity
- Gitea: same concern
- Direct disk backup: no history, harder to access remotely

---

## ADR-006: Claude Sonnet 4.6 as default model

**Date**: 2026-06-15  
**Status**: Accepted

**Context**: Need to choose a default LLM for all agent tools.

**Decision**: Default to Claude Sonnet 4.6 (`claude-sonnet-4-6`) across all tools.

**Rationale**:
- Best balance of quality vs cost for everyday coding tasks
- 200K context window handles large files
- Strong code generation and review capabilities
- Upgrade path to Opus 4.8 for complex tasks
- Downgrade path to Haiku 4.5 for simple/cheap tasks

**Review trigger**: Reassess when new Anthropic models are released, or if costs become significant.

---

## ADR-007: Self-hosted agent stack (Qwen3.8-27B on Kaggle, OpenHands UI, LiteLLM gateway)
**Date**: 2026-11-02  
**Status**: Accepted

**Context**: Want a self-hosted coding + deep-research agent that uses the free Kaggle GPU quota, with a web UI on the VPS.

**Decision**:
- Model: Qwen3.8-27B (Apache-2.0) as Unsloth GGUF, Q4_K_M, 64K context, q8_0 KV cache, served by a natively built `llama-server` (CUDA sm_75) on 2x T4. Thinking mode is off by default (`ccc-local`) and opt-in (`ccc-local-think`).
- Gateway: LiteLLM on the VPS with stable aliases (`ccc-local`, `ccc-local-think`, `ccc-client`, `ccc-fast`). Tools talk to aliases, never to Kaggle directly, so the backend can be swapped in one setting.
- UI: OpenHands behind Cloudflare Access; SearXNG for research (`research/searx.py`, `research/fetch.py`, `deep-research` skill).
- Network: outbound-only reverse SSH from Kaggle, restricted sshd user, bound to the docker bridge IP.

**Risk handling**: Kaggle ToS limits use to personal, non-commercial purposes and allows termination at Kaggle's discretion. Therefore: client work is routed to `ccc-client` (API, never Kaggle); no 24/7 keepalive or quota evasion; hard session cap (`SESSION_MAX_HOURS`, default 6); no auto-restart.

**Consequences**: Local generation is slow (estimated 10-15 tok/s, unmeasured). v1 `kaggle/quick_start.py` is superseded by `quick_start_v2.py`. See `docs/KAGGLE_QWEN38_AGENT.md`.
