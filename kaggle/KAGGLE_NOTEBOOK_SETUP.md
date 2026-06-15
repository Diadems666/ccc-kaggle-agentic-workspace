# Kaggle Notebook Setup Guide

Step-by-step guide to setting up a Kaggle T4 GPU as an LLM inference worker.

## Prerequisites

1. Kaggle account (free) — [kaggle.com/account/login](https://kaggle.com/account/login)
2. Phone number verified (required for GPU access)
3. VPS running with `kaggle-gpu` user created
4. Kaggle tunnel SSH keypair generated

## Step 1: Generate the Tunnel SSH Keypair

On your local machine (not on Kaggle or VPS):

```bash
ssh-keygen -t ed25519 -C "kaggle-tunnel" -f ~/.ssh/kaggle_tunnel_ed25519 -N ""
```

This creates:
- `~/.ssh/kaggle_tunnel_ed25519` — private key (goes to Kaggle)
- `~/.ssh/kaggle_tunnel_ed25519.pub` — public key (goes to VPS)

## Step 2: Add Public Key to VPS

```bash
# On VPS, as root or with sudo
cat >> /home/kaggle-gpu/.ssh/authorized_keys << 'EOF'
command="echo 'tunnel only'",no-pty,no-agent-forwarding,no-X11-forwarding ssh-ed25519 AAAA... kaggle-tunnel
EOF
chmod 600 /home/kaggle-gpu/.ssh/authorized_keys
chown kaggle-gpu:kaggle-gpu /home/kaggle-gpu/.ssh/authorized_keys
```

Replace `AAAA...` with the actual content of `kaggle_tunnel_ed25519.pub`.

## Step 3: Add Private Key to Kaggle Secrets

1. Go to [kaggle.com/settings](https://kaggle.com/settings)
2. Scroll to "API" section → Kaggle Secrets (or go via a notebook → Add-ons → Secrets)
3. Create secret:
   - Name: `KAGGLE_TUNNEL_KEY`
   - Value: paste the entire content of `~/.ssh/kaggle_tunnel_ed25519` (including the header/footer lines)
4. Save

## Step 4: Create a New Kaggle Notebook

1. Go to [kaggle.com/code](https://kaggle.com/code) → "New Notebook"
2. Click "+" next to "Add-ons" → Secrets → enable `KAGGLE_TUNNEL_KEY`
3. Click settings (gear icon) → Accelerator → **GPU T4 x 1**
4. Language: Python

## Step 5: Add Setup Cells

Paste these cells into the notebook:

### Cell 1: Load tunnel key from secret

```python
import os, stat

key_content = os.environ.get('KAGGLE_TUNNEL_KEY', '')
if not key_content:
    raise ValueError("KAGGLE_TUNNEL_KEY secret not found. Add it via Add-ons → Secrets")

key_path = '/tmp/kaggle_tunnel_key'
with open(key_path, 'w') as f:
    f.write(key_content)
    if not key_content.endswith('\n'):
        f.write('\n')
os.chmod(key_path, stat.S_IRUSR | stat.S_IWUSR)  # 600
print(f"Key written to {key_path}")
```

### Cell 2: Clone workspace

```python
import subprocess

result = subprocess.run(
    ['git', 'clone', 'https://github.com/YOUR_ORG/ccc-kaggle-agentic-workspace', '/tmp/ws'],
    capture_output=True, text=True
)
print(result.stdout)
print(result.stderr)
```

### Cell 3: Set VPS host

```python
os.environ['VPS_HOST'] = 'YOUR_VPS_IP'
os.environ['VPS_USER'] = 'kaggle-gpu'
os.environ['VPS_PORT'] = '22'
os.environ['KAGGLE_TUNNEL_KEY_PATH'] = '/tmp/kaggle_tunnel_key'
os.environ['LOCAL_LLM_PORT'] = '8080'
os.environ['VPS_TUNNEL_PORT'] = '8081'
print("Environment configured")
```

### Cell 4: Install dependencies and download model

```python
result = subprocess.run(
    ['bash', '/tmp/ws/kaggle/setup_kaggle_gpu_worker.sh'],
    capture_output=False  # show output
)
print(f"Exit code: {result.returncode}")
```

This takes ~5-10 minutes (downloads ~4 GB model).

### Cell 5: Start LLM server (in background thread)

```python
import threading

def run_server():
    subprocess.run(['bash', '/tmp/ws/kaggle/start_llama_server.sh'])

server_thread = threading.Thread(target=run_server, daemon=True)
server_thread.start()

# Wait for server to come up
import time, urllib.request
for i in range(60):
    try:
        urllib.request.urlopen('http://localhost:8080/v1/models', timeout=2)
        print(f"LLM server ready after {i*5} seconds")
        break
    except:
        time.sleep(5)
        print(f"Waiting... ({i*5}s)")
else:
    print("Server did not start in 5 minutes — check logs")
```

### Cell 6: Open reverse SSH tunnel (keep this running)

```python
tunnel = subprocess.Popen(
    ['bash', '/tmp/ws/kaggle/reverse_tunnel_to_vps.sh'],
    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True
)
print("Tunnel process started, reading output:")
for line in iter(tunnel.stdout.readline, ''):
    print(line, end='')
```

**Keep this cell running** — the tunnel stays alive while this cell executes. If Kaggle stops the cell, the tunnel drops.

### Cell 7: Start watchdog (optional, in background)

```python
watchdog = subprocess.Popen(
    ['python3', '/tmp/ws/kaggle/session_watchdog.py'],
    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True
)
print("Watchdog started")
```

## Step 6: Verify from VPS

On your VPS:

```bash
# Check tunnel is active
ss -tlnp | grep 8081

# Test LLM server
curl http://localhost:8081/v1/models | python3 -m json.tool

# Test completion
curl http://localhost:8081/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen2.5-coder-7b-instruct","messages":[{"role":"user","content":"Hello"}]}'
```

## Step 7: Use the GPU from your agents

```bash
bash scripts/switch_provider.sh local
aider src/main.py
```

## Tips

- Save the notebook after setup so you can re-run it next session quickly
- The notebook URL stays constant — bookmark it on your phone
- Enable "Save versions" to preserve your setup cells
- Run Cell 4 (model download) first — it takes the longest, can run while you set up other things
