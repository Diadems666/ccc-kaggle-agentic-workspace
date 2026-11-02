# Tasks

Project backlog for the CCC agentic workspace setup.

## Status Legend

- `[ ]` — Not started
- `[~]` — In progress
- `[x]` — Done
- `[!]` — Blocked

---

## Phase 1: VPS Provisioning

- [ ] Provision BinaryLane VPS (Ubuntu 24.04, Sydney region)
- [ ] Run `vps/install-vps.sh` as root
- [ ] Run `vps/create-users.sh` — create `deploy` and `kaggle-gpu` users
- [ ] Add your SSH public key to `deploy` user
- [ ] Run `vps/harden-ssh.sh` — disable root/password login
- [ ] Verify SSH still works after hardening
- [ ] Run `vps/setup-workspace.sh` — create `/opt/coding-workspace/`
- [ ] Clone this repo to `/opt/coding-workspace/`
- [ ] Copy `.env.example` to `.env` and fill in real values

## Phase 2: IDE Setup

- [ ] Run `vps/install-code-server.sh`
- [ ] Set `CODE_SERVER_PASSWORD` in `.env`
- [ ] Enable and start `code-server.service`
- [ ] Verify code-server accessible on `localhost:8080`
- [ ] (Optional) Run `vps/install-openvscode-server.sh` as alternative

## Phase 3: Cloudflare Tunnel

- [ ] Run `vps/install-cloudflared.sh`
- [ ] Create Cloudflare Tunnel in Zero Trust dashboard
- [ ] Copy tunnel token to `/etc/cloudflared/config.yml`
- [ ] Enable and start `cloudflared.service`
- [ ] Add DNS CNAME record: `coding` → tunnel hostname
- [ ] Create Cloudflare Access Application for `coding.cairnscustomcomputers.cloud`
- [ ] Set Access policy: Allow → your email
- [ ] Verify IDE loads at `https://coding.cairnscustomcomputers.cloud`
- [ ] Test authentication from mobile browser

## Phase 4: Agent Tools

- [ ] Run `vps/install-agent-tools.sh`
- [ ] Configure `ANTHROPIC_API_KEY` in `.env`
- [ ] Test Claude Code: `claude "hello world"`
- [ ] Configure Aider: create `~/.aider.conf.yml`
- [ ] Test Aider: `aider --version`
- [ ] (Optional) Configure OpenAI key for Codex CLI / OpenCode
- [ ] Run `scripts/healthcheck.sh` — all green

## Phase 5: Kaggle GPU

- [ ] Create Kaggle account (if not already)
- [ ] Generate Kaggle tunnel SSH keypair
- [ ] Add public key to `/home/kaggle-gpu/.ssh/authorized_keys` on VPS
- [ ] Create Kaggle notebook secret `KAGGLE_TUNNEL_KEY` with private key content
- [ ] Test Kaggle setup script on a notebook
- [ ] Test reverse tunnel connectivity
- [ ] Test local LLM via `curl http://localhost:8081/v1/models`
- [ ] Test `bash scripts/switch_provider.sh local`

## Phase 6: Mobile Workflow

- [ ] Test IDE from iPhone browser
- [ ] Add IDE to Home Screen (PWA)
- [ ] Test typing with Bluetooth keyboard
- [ ] Test Kaggle session start from mobile
- [ ] Configure ntfy.sh notifications (optional)

## Ongoing

- [ ] Set up weekly backup cron: `scripts/backup_workspace.sh`
- [ ] Enable unattended security upgrades on VPS
- [ ] Document any custom modifications in `IMPLEMENTATION_NOTES.md`
- [ ] Review and rotate API keys quarterly

## Phase 7: Agent Stack (Qwen3.8-27B + OpenHands)

- [ ] Run `kaggle/kaggle-build-llama.ipynb` once; save output as private Kaggle Dataset `llama-cpp-sm75`
- [ ] On VPS: `sudo bash vps/agent-stack/install-agent-stack.sh`
- [ ] Publish OpenHands gated at kaggle.tropicops.cloud: `sudo CF_API_TOKEN=... CF_ACCOUNT_ID=... bash vps/agent-stack/setup-gated-subdomain.sh`
- [ ] Push repo to GitHub (the Kaggle notebook clones it), then `bash scripts/kaggle_deploy.sh build`, `dataset`, `worker`
- [ ] First Kaggle shakedown with `SESSION_MAX_HOURS=1` using `kaggle/kaggle-quick-start-v2.ipynb`
- [ ] `bash scripts/agent_stack_status.sh --smoke` passes
- [ ] Measure real tok/s and update `MODEL_MATRIX.md` / the doc's estimates
- [ ] Verify sshd `PermitListen` restriction works (`sshd -T -C user=kaggle-gpu`)
- [ ] Confirm client work uses `ccc-client` only
