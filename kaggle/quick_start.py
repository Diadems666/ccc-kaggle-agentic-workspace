"""
CCC Kaggle GPU Quick Start
--------------------------
Paste the content of this file into a single Kaggle notebook cell and run it.
It handles everything: SSH key, model download, LLM server, reverse tunnel, watchdog.

Prerequisites (one-time):
  1. Add-ons → Secrets → enable KAGGLE_TUNNEL_KEY
  2. Settings → Accelerator → GPU T4 x 1

Config — only change these if your VPS details differ:
"""

VPS_HOST            = os.environ.get("VPS_HOST", "112.213.38.79")
VPS_USER            = os.environ.get("VPS_USER", "kaggle-gpu")
VPS_PORT            = int(os.environ.get("VPS_PORT", "22"))
VPS_TUNNEL_PORT     = int(os.environ.get("VPS_TUNNEL_PORT", "8081"))
LOCAL_LLM_PORT      = int(os.environ.get("LOCAL_LLM_PORT", "8080"))
MODEL_NAME          = os.environ.get("MODEL_NAME", "qwen2.5-coder-7b-instruct-q4_k_m.gguf")
MODEL_REPO          = os.environ.get("MODEL_REPO", "Qwen/Qwen2.5-Coder-7B-Instruct-GGUF")
KEY_PATH            = "/tmp/kaggle_tunnel_key"
MODEL_DIR           = "/kaggle/working/models"
WORKSPACE_DIR       = "/tmp/ws"
ALERT_WEBHOOK_URL   = os.environ.get("ALERT_WEBHOOK_URL", "")

# ── imports ───────────────────────────────────────────────────────────────────
import os, stat, subprocess, threading, time, sys
try:
    import urllib.request
except ImportError:
    pass

def step(n, msg):
    print(f"\n{'='*50}")
    print(f"[{n}] {msg}")
    print('='*50)

def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, **kwargs)

# ── Step 1: Write SSH key from Kaggle secret ──────────────────────────────────
step(1, "Loading SSH tunnel key from Kaggle secret")

key = os.environ.get("KAGGLE_TUNNEL_KEY", "")
if not key:
    raise RuntimeError(
        "KAGGLE_TUNNEL_KEY secret not found.\n"
        "Fix: Add-ons → Secrets → toggle KAGGLE_TUNNEL_KEY to ON, then re-run."
    )

with open(KEY_PATH, "w") as f:
    f.write(key if key.endswith("\n") else key + "\n")
os.chmod(KEY_PATH, stat.S_IRUSR | stat.S_IWUSR)

# Basic sanity check
with open(KEY_PATH) as f:
    first = f.readline().strip()
if "PRIVATE" not in first and "openssh" not in first.lower():
    raise RuntimeError(f"Key file looks wrong (first line: {first!r}). Check the Kaggle secret value.")

print(f"  SSH key written to {KEY_PATH}")

# ── Step 2: Clone / update workspace repo ─────────────────────────────────────
step(2, "Syncing workspace repository")

if os.path.exists(f"{WORKSPACE_DIR}/.git"):
    run(["git", "-C", WORKSPACE_DIR, "pull", "--rebase"], capture_output=True)
    print(f"  Updated existing clone at {WORKSPACE_DIR}")
else:
    run(["git", "clone",
         "https://github.com/Diadems666/ccc-kaggle-agentic-workspace",
         WORKSPACE_DIR])
    print(f"  Cloned to {WORKSPACE_DIR}")

# Set env vars for child scripts
os.environ.update({
    "VPS_HOST": VPS_HOST,
    "VPS_USER": VPS_USER,
    "VPS_PORT": str(VPS_PORT),
    "KAGGLE_TUNNEL_KEY_PATH": KEY_PATH,
    "LOCAL_LLM_PORT": str(LOCAL_LLM_PORT),
    "VPS_TUNNEL_PORT": str(VPS_TUNNEL_PORT),
    "MODEL_NAME": MODEL_NAME,
    "MODEL_REPO": MODEL_REPO,
    "MODEL_DIR": MODEL_DIR,
    "WORKSPACE_DIR": WORKSPACE_DIR,
    "ALERT_WEBHOOK_URL": ALERT_WEBHOOK_URL,
})

# ── Step 3: Install deps + download model ────────────────────────────────────
step(3, "Checking model cache and installing dependencies")

model_path = f"{MODEL_DIR}/{MODEL_NAME}"
if os.path.exists(model_path):
    size_gb = os.path.getsize(model_path) / 1e9
    print(f"  Model already cached: {model_path} ({size_gb:.1f} GB) — skipping download")
else:
    print(f"  Model not found — running setup (downloads ~4 GB, takes ~5 min)...")
    run(["bash", f"{WORKSPACE_DIR}/kaggle/setup_kaggle_gpu_worker.sh"])

# ── Step 4: Start LLM server in background ───────────────────────────────────
step(4, "Starting LLM inference server")

server_proc = [None]

def _run_server():
    server_proc[0] = subprocess.Popen(
        ["bash", f"{WORKSPACE_DIR}/kaggle/start_llama_server.sh"],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True
    )
    for line in iter(server_proc[0].stdout.readline, ""):
        pass  # absorb output silently

threading.Thread(target=_run_server, daemon=True).start()

# Poll until ready
print(f"  Waiting for server on localhost:{LOCAL_LLM_PORT}...")
ready = False
for i in range(72):  # up to 6 minutes
    time.sleep(5)
    try:
        with urllib.request.urlopen(
            f"http://localhost:{LOCAL_LLM_PORT}/v1/models", timeout=2
        ) as r:
            if r.status == 200:
                ready = True
                print(f"  Server ready after {(i+1)*5}s")
                break
    except Exception:
        if i % 6 == 5:
            print(f"  Still loading... {(i+1)*5}s elapsed")

if not ready:
    print("  WARNING: Server did not respond in 6 min. Opening tunnel anyway.")

# ── Step 5: Start watchdog in background ─────────────────────────────────────
step(5, "Starting session watchdog (auto-saves before 12h timeout)")

threading.Thread(
    target=lambda: subprocess.run(
        ["python3", f"{WORKSPACE_DIR}/kaggle/session_watchdog.py"]
    ),
    daemon=True
).start()
print("  Watchdog running (saves to GitHub at 30 min remaining, closes tunnel at 10 min)")

# ── Step 6: Open reverse tunnel — keeps cell alive ───────────────────────────
step(6, f"Opening reverse SSH tunnel → VPS port {VPS_TUNNEL_PORT}")

print(f"""
  Kaggle GPU  localhost:{LOCAL_LLM_PORT}
       ↑ reverse tunnel
  VPS  localhost:{VPS_TUNNEL_PORT}

  Test from your VPS terminal:
    curl http://localhost:{VPS_TUNNEL_PORT}/v1/models

  Switch agents to GPU:
    bash /opt/coding-workspace/scripts/switch_provider.sh local

  ⚠  Keep this cell running — tunnel closes when cell stops.
""")

tunnel = subprocess.Popen(
    ["bash", f"{WORKSPACE_DIR}/kaggle/reverse_tunnel_to_vps.sh"],
    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True
)
try:
    for line in iter(tunnel.stdout.readline, ""):
        sys.stdout.write(line)
        sys.stdout.flush()
except KeyboardInterrupt:
    tunnel.terminate()
    print("\nTunnel closed.")
