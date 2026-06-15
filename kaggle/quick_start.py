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
import os, stat, subprocess, threading, time, sys, json
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

# ── Auto-select model based on GPU count ─────────────────────────────────────
try:
    _gpu_lines = subprocess.check_output(
        ["nvidia-smi", "--query-gpu=name", "--format=csv,noheader"],
        stderr=subprocess.DEVNULL, text=True
    ).strip().splitlines()
    _gpu_count = len(_gpu_lines)
except Exception:
    _gpu_count = 1

if _gpu_count >= 2 and not os.environ.get("MODEL_NAME"):
    MODEL_NAME = "qwen2.5-coder-32b-q4_k_m.gguf"
    MODEL_REPO = "Qwen/Qwen2.5-Coder-32B-Instruct-GGUF"
    print(f"Dual T4 detected — upgrading to 32B model across {_gpu_count} GPUs")

# ── Step 1: Write SSH key from Kaggle secret ──────────────────────────────────
step(1, "Loading SSH tunnel key from Kaggle secret")

key = ""
try:
    from kaggle_secrets import UserSecretsClient
    key = UserSecretsClient().get_secret("KAGGLE_TUNNEL_KEY")
except Exception:
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

def _find_model_file(model_dir):
    """Return path to the first Q4_K_M shard (or single file) on disk."""
    import glob
    gguf = sorted(f for f in glob.glob(f"{model_dir}/*.gguf") if 'q4_k_m' in f.lower())
    shards = [f for f in gguf if '-of-' in f]
    return (shards or gguf or [None])[0]

model_path = f"{MODEL_DIR}/{MODEL_NAME}"
existing = _find_model_file(MODEL_DIR)

if existing:
    size_gb = os.path.getsize(existing) / 1e9
    MODEL_NAME = os.path.basename(existing)
    os.environ["MODEL_NAME"] = MODEL_NAME
    print(f"  Model cached: {existing} ({size_gb:.1f} GB)")
else:
    print(f"  Model not found — running setup...")
    run(["bash", f"{WORKSPACE_DIR}/kaggle/setup_kaggle_gpu_worker.sh"])
    # Re-scan: setup may have downloaded split shards with different filenames
    existing = _find_model_file(MODEL_DIR)
    if existing:
        MODEL_NAME = os.path.basename(existing)
        os.environ["MODEL_NAME"] = MODEL_NAME
        print(f"  Model ready: {MODEL_NAME}")
    else:
        raise RuntimeError(f"Setup completed but no Q4_K_M .gguf found in {MODEL_DIR}")

# ── Step 4: Start LLM server in background ───────────────────────────────────
step(4, "Starting LLM inference server")

_SERVER_LOG = "/tmp/llm_server.log"
server_proc = [None]

def _run_server():
    with open(_SERVER_LOG, "w", buffering=1) as log:
        server_proc[0] = subprocess.Popen(
            ["bash", f"{WORKSPACE_DIR}/kaggle/start_llama_server.sh"],
            stdout=log, stderr=subprocess.STDOUT, text=True
        )
        server_proc[0].wait()

threading.Thread(target=_run_server, daemon=True).start()

# Poll until ready
print(f"  Waiting for server on localhost:{LOCAL_LLM_PORT}...")
print(f"  (server log: {_SERVER_LOG})")
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
    print("  WARNING: Server did not respond in 6 min.")
    try:
        with open(_SERVER_LOG) as _f:
            _tail = _f.readlines()[-30:]
        print("  --- Last server log lines ---")
        for _line in _tail:
            print(f"  {_line.rstrip()}")
        print("  --- End log ---")
    except Exception as _e:
        print(f"  (could not read server log: {_e})")
    print("  Opening tunnel anyway.")

# ── Step 5: Configure MiMo Code agent harness ────────────────────────────────
step(5, "Configuring MiMo Code")

mimo_config = {
    "agents": {
        "coder": {
            "model": f"local/{MODEL_NAME.replace('.gguf', '')}",
            "endpoint": f"http://127.0.0.1:{LOCAL_LLM_PORT}/v1",
            "reasoningEffort": "high"
        },
        "plan": {
            "model": f"local/{MODEL_NAME.replace('.gguf', '')}",
            "endpoint": f"http://127.0.0.1:{LOCAL_LLM_PORT}/v1",
            "reasoningEffort": "low"
        }
    },
    "tui": {"theme": "mimo-dark"}
}

mimo_dir = os.path.expanduser("~/.mimo")
os.makedirs(mimo_dir, exist_ok=True)
with open(f"{mimo_dir}/config.json", "w") as f:
    json.dump(mimo_config, f, indent=2)
print(f"  MiMo config written to {mimo_dir}/config.json")
print(f"  Endpoint: http://127.0.0.1:{LOCAL_LLM_PORT}/v1")
print(f"  Model: {MODEL_NAME}")

# Check if mimo CLI is available
try:
    v = subprocess.check_output(["mimo", "--version"], stderr=subprocess.DEVNULL, text=True).strip()
    print(f"  mimo CLI: {v}")
    print("  Launch agent: mimo  (in a tmate terminal — see next step)")
except FileNotFoundError:
    print("  mimo CLI not installed — run setup_kaggle_gpu_worker.sh to install it")

# ── Step 6: tmate SSH tunnel (optional — direct terminal access) ──────────────
step(6, "Starting tmate SSH tunnel")

try:
    tmate_dir = "/tmp/tmate-2.4.0-static-linux-amd64"
    tmate_bin = f"{tmate_dir}/tmate"
    tmate_sock = "/tmp/tmate.sock"

    if not os.path.exists(tmate_bin):
        tmate_url = "https://github.com/tmate-io/tmate/releases/download/2.4.0/tmate-2.4.0-static-linux-amd64.tar.xz"
        run(["bash", "-c", f"wget -qO- {tmate_url} | tar xJ -C /tmp/"])

    run([tmate_bin, "-S", tmate_sock, "new-session", "-d"])
    run([tmate_bin, "-S", tmate_sock, "wait", "tmate-ready"])
    ssh_str = subprocess.check_output(
        [tmate_bin, "-S", tmate_sock, "display", "-p", "#{tmate_ssh}"],
        text=True
    ).strip()
    print(f"  SSH into this Kaggle container:")
    print(f"  {ssh_str}")
    print("  Use this terminal to run: mimo")
    print("                         or: nvidia-smi  (live GPU stats)")
except Exception as e:
    print(f"  tmate unavailable ({e}) — skipping")

# ── Step 7: Start watchdog in background ─────────────────────────────────────
step(7, "Starting session watchdog (auto-saves before 12h timeout)")

threading.Thread(
    target=lambda: subprocess.run(
        ["python3", f"{WORKSPACE_DIR}/kaggle/session_watchdog.py"]
    ),
    daemon=True
).start()
print("  Watchdog running (SIGTERM handler active, saves at 30 min remaining)")

# ── Step 8: Open reverse tunnel — keeps cell alive ───────────────────────────
step(8, f"Opening reverse SSH tunnel → VPS port {VPS_TUNNEL_PORT}")

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
