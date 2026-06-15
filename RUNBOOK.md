# Runbook

Day-to-day operations for the CCC Kaggle agentic workspace.

## Daily Workflow

### Starting a session

```bash
# 1. Open browser to https://coding.cairnscustomcomputers.cloud
# 2. Authenticate with Cloudflare Access OTP
# 3. In the IDE terminal:
cd /opt/coding-workspace/repos/YOUR_PROJECT
bash /opt/coding-workspace/scripts/start_agent_session.sh
```

### Checking system health

```bash
bash /opt/coding-workspace/scripts/healthcheck.sh
```

Expected output:
```
[OK] code-server: running (PID 1234)
[OK] cloudflared: running (PID 5678)
[OK] GitHub connectivity: reachable
[OK] Anthropic API: reachable
[??] Kaggle tunnel: not active (normal if no GPU session)
[OK] Disk: 4.2G used / 20G total (21%)
[OK] Memory: 1.1G used / 2G total (55%)
```

### Ending a session

```bash
bash /opt/coding-workspace/scripts/stop_agent_session.sh
git add -A && git commit -m "wip: end of session $(date +%Y-%m-%d)" && git push
```

---

## Kaggle GPU Workflow

### Starting a Kaggle GPU session

1. Open [kaggle.com/notebooks](https://kaggle.com/notebooks) on your phone
2. Create new notebook → enable GPU (T4 × 1)
3. In the first code cell, paste:

```python
import subprocess, os

# Load tunnel key from Kaggle secret (set this up in Kaggle settings first)
# Settings → Secrets → Add Secret: KAGGLE_TUNNEL_KEY (paste private key content)
key_content = os.environ.get('KAGGLE_TUNNEL_KEY', '')
with open('/tmp/kaggle_tunnel_key', 'w') as f:
    f.write(key_content)
os.chmod('/tmp/kaggle_tunnel_key', 0o600)

subprocess.run(['bash', 'kaggle/setup_kaggle_gpu_worker.sh'], check=True)
subprocess.run(['bash', 'kaggle/start_llama_server.sh'], check=True)
subprocess.run(['bash', 'kaggle/reverse_tunnel_to_vps.sh'], check=True)
```

4. Run the cell and wait ~5 minutes for model download + server start

### Verifying the GPU tunnel is active

```bash
# On VPS:
curl http://localhost:8081/v1/models | python3 -m json.tool
```

You should see the loaded model listed.

### Switching agents to use Kaggle GPU

```bash
bash /opt/coding-workspace/scripts/switch_provider.sh local
```

This sets `LLM_BASE_URL=http://localhost:8081/v1` in the active environment.

Switch back to API:
```bash
bash /opt/coding-workspace/scripts/switch_provider.sh anthropic
```

### Kaggle session time management

Kaggle sessions expire after 12 hours. The `session_watchdog.py` script:
- Checks remaining time every 5 minutes
- At 30 minutes remaining: saves workspace state and pushes to GitHub
- At 10 minutes remaining: closes tunnel gracefully
- At 5 minutes remaining: sends a desktop notification (if webhook configured)

To manually save state:
```bash
# On Kaggle notebook:
!bash kaggle/save_state.sh
```

---

## VPS Management

### Restarting services

```bash
# Restart code-server
sudo systemctl restart code-server

# Restart Cloudflare tunnel
sudo systemctl restart cloudflared

# Restart OpenVSCode Server (if using that instead)
sudo systemctl restart openvscode-server

# Check all services
sudo systemctl status code-server cloudflared
```

### Updating agent tools

```bash
# Update Claude Code
sudo npm update -g @anthropic-ai/claude-code

# Update Aider
pip install --upgrade aider-chat

# Update OpenCode
sudo npm update -g opencode-ai

# Update all at once
bash /opt/coding-workspace/scripts/sync_repo.sh --update-tools
```

### Disk space management

```bash
# Check usage
df -h
du -sh /opt/coding-workspace/*/

# Clean npm cache
npm cache clean --force

# Clean pip cache
pip cache purge

# Remove old backups (keep last 7)
ls -t /opt/coding-workspace/backups/ | tail -n +8 | xargs -I{} rm -rf /opt/coding-workspace/backups/{}

# Remove unused Docker images (if Docker in use)
docker image prune -f
```

### Backup workspace

```bash
bash /opt/coding-workspace/scripts/backup_workspace.sh
```

Creates a timestamped tar.gz in `/opt/coding-workspace/backups/`.

### Sync latest repo changes

```bash
# Pull workspace scripts updates from GitHub
bash /opt/coding-workspace/scripts/sync_repo.sh

# Or manually:
cd /opt/coding-workspace
git pull origin main
```

---

## Cloudflare Tunnel Management

### Checking tunnel status

```bash
sudo systemctl status cloudflared
journalctl -u cloudflared -f --no-pager
```

### Reconnecting a dropped tunnel

```bash
sudo systemctl restart cloudflared
# Verify:
curl -I https://coding.cairnscustomcomputers.cloud
```

### Rotating the tunnel token

1. Cloudflare Zero Trust → Tunnels → Your Tunnel → Configure
2. Delete the current token → create new tunnel (or rotate token)
3. On VPS: `sudo nano /etc/cloudflared/config.yml` → update token
4. `sudo systemctl restart cloudflared`

---

## GitHub Workflow

### Daily git hygiene

```bash
# Start of session: pull latest
git pull --rebase origin main

# During session: stage and commit often
git add -p    # interactive patch staging
git commit -m "feat: describe what you built"

# End of session: push
git push origin main
```

### Working on a feature

```bash
git checkout -b feat/my-feature
# ... work ...
git push -u origin feat/my-feature
gh pr create --title "feat: my feature" --body "Description"
```

### Recovering from a broken state

```bash
# See what changed
git status
git diff

# Undo uncommitted changes to a file
git checkout -- path/to/file

# Undo last commit (keep changes staged)
git reset --soft HEAD~1

# Hard reset to remote (DESTRUCTIVE — loses local changes)
git fetch origin && git reset --hard origin/main
```

---

## Agent Tool Usage

### Claude Code

```bash
# Start interactive session
claude

# Run a one-shot task
claude "add unit tests for src/utils.py"

# Use with a specific model
claude --model claude-opus-4-8 "review this PR"
```

### Aider

```bash
# Start session with specific files
aider src/main.py src/utils.py

# Use local Kaggle GPU
aider --openai-api-base http://localhost:8081/v1 \
      --openai-api-key local \
      --model local-model \
      src/main.py
```

### Switching LLM providers

| Provider | Command |
|----------|---------|
| Anthropic (Claude) | `bash scripts/switch_provider.sh anthropic` |
| OpenAI | `bash scripts/switch_provider.sh openai` |
| Kaggle local GPU | `bash scripts/switch_provider.sh local` |

---

## Monitoring

### Watching logs in real-time

```bash
# code-server log
journalctl -u code-server -f

# Cloudflare tunnel log
journalctl -u cloudflared -f

# System log (CPU/memory spikes)
vmstat 5

# Watch running processes
htop
```

### Alerting (optional webhook setup)

Set `ALERT_WEBHOOK_URL` in `.env` to receive alerts from `session_watchdog.py`.
Supports Discord, Slack, or any webhook endpoint.

```bash
# Test the webhook
curl -X POST "$ALERT_WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d '{"text": "Test alert from CCC workspace"}'
```

---

## Troubleshooting Quick Reference

| Problem | First step |
|---------|-----------|
| IDE unreachable | `sudo systemctl status cloudflared` |
| Cloudflare 502 | `sudo systemctl restart code-server` |
| Kaggle tunnel not working | Check SSH key is in `~/.ssh/authorized_keys` on VPS |
| Agent tool rate limited | `bash scripts/switch_provider.sh` |
| Out of disk space | `df -h` then clean npm/pip cache |
| code-server password forgotten | Check VPS `.env` → `CODE_SERVER_PASSWORD` |

See `TROUBLESHOOTING.md` for detailed fixes.
