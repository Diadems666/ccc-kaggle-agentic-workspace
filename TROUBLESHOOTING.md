# Troubleshooting

## Cloudflare / IDE Access

### "526 Invalid SSL certificate" or "522 Connection timeout"

The VPS is not responding to Cloudflare's health checks.

```bash
# Check cloudflared is running
sudo systemctl status cloudflared
journalctl -u cloudflared --since "5 minutes ago" --no-pager

# If stopped, restart it
sudo systemctl restart cloudflared

# If it keeps crashing, check the config
sudo cat /etc/cloudflared/config.yml
# Verify the tunnel token matches your Cloudflare dashboard tunnel
```

### "1033 Argo Tunnel error"

Cloudflare can reach the VPS but the local service is down.

```bash
# Check code-server
sudo systemctl status code-server
sudo systemctl restart code-server

# Verify it's listening on the right port
ss -tlnp | grep 8080
```

### Cloudflare Access "Access denied" — valid email

1. Verify the email matches exactly what's in your Access policy
2. Check the policy in Cloudflare Zero Trust → Access → Applications → your app
3. The OTP may have expired (valid for 10 minutes) — request a new one

### code-server password rejected

```bash
# Find the password
grep CODE_SERVER_PASSWORD /opt/coding-workspace/.env

# If .env is missing, check the systemd unit
sudo systemctl cat code-server | grep -i password
```

---

## Kaggle GPU Tunnel

### Tunnel not connecting

```bash
# On VPS: check if port 8081 is listening
ss -tlnp | grep 8081
# Expected: nothing (tunnel not active)

# After running reverse_tunnel_to_vps.sh from Kaggle, check again:
ss -tlnp | grep 8081
# Expected: 0.0.0.0:8081 LISTEN (ssh process)
```

If still no tunnel:
1. Verify the kaggle-gpu user exists on VPS: `id kaggle-gpu`
2. Verify the SSH key is in `/home/kaggle-gpu/.ssh/authorized_keys`
3. Verify SSH AllowUsers includes kaggle-gpu: `grep AllowUsers /etc/ssh/sshd_config`
4. Check Kaggle notebook can reach VPS: `!nc -zv YOUR_VPS_IP 22`

### LLM server not responding after tunnel connects

```bash
# Test from VPS
curl http://localhost:8081/v1/models

# If connection refused: server didn't start yet
# Wait 2-3 minutes for model to load, then retry

# If connection reset: model OOM'd — check Kaggle notebook for error output
```

### Kaggle: "RuntimeError: CUDA out of memory"

The model is too large for T4's 16 GB VRAM.

Switch to a smaller/more quantised model:
```bash
# In start_llama_server.sh, change to a smaller GGUF:
MODEL_FILE="qwen2.5-coder-3b-instruct-q8_0.gguf"
# Or reduce context window:
CONTEXT_SIZE=4096  # was 8192
```

### Kaggle session expired unexpectedly

1. Check if watchdog was running: look for `session_watchdog.py` in the process list
2. Re-run the full setup in a new Kaggle session
3. Your state should be in GitHub if watchdog saved correctly

---

## Agent Tools

### Claude Code: "API key not found"

```bash
# Check the key is set
echo $ANTHROPIC_API_KEY

# If empty, source the env file
source /opt/coding-workspace/.env
export ANTHROPIC_API_KEY

# Or set directly:
export ANTHROPIC_API_KEY=sk-ant-...
```

### Claude Code: rate limited (429 error)

1. Wait 60 seconds and retry
2. Switch to a different model: `claude --model claude-haiku-4-5-20251001`
3. Or switch to local GPU: `bash scripts/switch_provider.sh local`

### Aider: "Model not found" with local provider

```bash
# Verify local server is responding
curl http://localhost:8081/v1/models

# Check what model name the server reports
curl http://localhost:8081/v1/models | python3 -m json.tool | grep id

# Use that exact name in aider:
aider --model openai/EXACT_MODEL_NAME_FROM_API \
      --openai-api-base http://localhost:8081/v1 \
      --openai-api-key local
```

### Aider: git conflicts during session

```bash
# Aider creates commits automatically. If there's a conflict:
git status
git diff

# Accept aider's version:
git checkout --theirs path/to/file
git add path/to/file
git rebase --continue

# Or abort and start fresh:
git rebase --abort
```

### OpenCode: authentication error

```bash
# Check config
cat ~/.config/opencode/config.json

# Re-run auth
opencode auth login
```

---

## VPS / SSH

### SSH connection refused

1. Check VPS is running in BinaryLane console
2. Check your IP isn't blocked by fail2ban:
   ```bash
   # On VPS console (not SSH):
   sudo fail2ban-client status sshd
   sudo fail2ban-client set sshd unbanip YOUR_IP
   ```
3. Verify SSH is listening: `ss -tlnp | grep :22`

### SSH "Permission denied (publickey)"

```bash
# Check which key your SSH client is using
ssh -v deploy@YOUR_VPS_IP 2>&1 | grep "Offering"

# If wrong key, specify explicitly:
ssh -i ~/.ssh/vps_ed25519 deploy@YOUR_VPS_IP

# If key not accepted, check VPS authorized_keys:
# (via BinaryLane console root access)
cat /home/deploy/.ssh/authorized_keys
```

### VPS out of disk space

```bash
# Find largest directories
du -sh /opt/coding-workspace/*/
du -sh /home/*/
du -sh /var/log/

# Clean up
# Old backups:
ls -lt /opt/coding-workspace/backups/ | tail -n +8 | awk '{print $NF}' | xargs rm -rf

# npm cache:
npm cache clean --force

# pip cache:
pip cache purge

# Docker (if in use):
docker system prune -f

# Old logs:
sudo journalctl --vacuum-time=7d
```

### VPS high memory usage

```bash
# See what's using memory
free -h
ps aux --sort=-%mem | head -20

# If code-server is leaking, restart it
sudo systemctl restart code-server

# Check for runaway agent processes
ps aux | grep -E 'aider|claude|opencode'
```

---

## Git / GitHub

### Push rejected "non-fast-forward"

```bash
# Pull and rebase first
git pull --rebase origin main
# Resolve any conflicts, then:
git push origin main
```

### Large file accidentally staged

```bash
# Remove from staging without deleting
git rm --cached path/to/large-file

# Add to .gitignore
echo "path/to/large-file" >> .gitignore

# Commit the removal
git commit -m "remove large file from tracking"
```

### Secret accidentally committed

1. **Immediately revoke the secret** in the relevant service
2. Remove from git history:
   ```bash
   # Install git-filter-repo
   pip install git-filter-repo
   git filter-repo --path path/to/secret-file --invert-paths
   # Force push (coordinate with team if shared repo)
   git push origin --force --all
   ```
3. Generate a new secret and update `.env`

---

## Network / Connectivity

### VPS unreachable (all services)

1. Ping the VPS IP: `ping YOUR_VPS_IP`
2. If no ping response: check BinaryLane console → is the VPS running?
3. If VPS running but unreachable: check ufw rules haven't blocked everything
   - Via BinaryLane console → connect via VNC/serial
   - `sudo ufw status`
   - `sudo ufw allow 22/tcp` if SSH was accidentally blocked

### Slow IDE performance

1. Check VPS load: `uptime` (should be < 2 for a 2-core VPS)
2. Check memory: `free -h`
3. Reduce code-server extensions: disable ones you don't use
4. Use a lighter theme (avoid heavy icon packs)
5. Close unused browser tabs / editor tabs

### Cloudflare slow response times

1. Check [Cloudflare status](https://www.cloudflarestatus.com)
2. BinaryLane Sydney is closest to Australian users — if your VPS is in another region, latency will be higher
3. Try switching Cloudflare to "Performance" routing mode (Zero Trust → Tunnels → settings)
