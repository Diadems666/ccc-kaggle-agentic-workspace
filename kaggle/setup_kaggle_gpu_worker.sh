#!/usr/bin/env bash
set -euo pipefail

# Setup Kaggle T4 notebook as LLM inference worker.
# Run this once at the start of each Kaggle session.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL_DIR="${MODEL_DIR:-/kaggle/working/models}"
MODEL_NAME="${MODEL_NAME:-qwen2.5-coder-7b-instruct-q4_k_m.gguf}"
MODEL_REPO="${MODEL_REPO:-Qwen/Qwen2.5-Coder-7B-Instruct-GGUF}"

echo "=== CCC Kaggle GPU Worker Setup ==="
echo "Model dir:  $MODEL_DIR"
echo "Model:      $MODEL_NAME"
echo ""

# ─── Verify GPU ───────────────────────────────────────────────────────────────
echo "[1/5] Checking GPU..."
if ! command -v nvidia-smi &>/dev/null; then
    echo "ERROR: nvidia-smi not found. Enable GPU accelerator in notebook settings."
    exit 1
fi
nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader
echo ""

# ─── Install system dependencies ──────────────────────────────────────────────
echo "[2/5] Installing system dependencies..."
apt-get install -qq -y openssh-client cmake build-essential curl \
    libcurl4-openssl-dev 2>/dev/null || true
echo "Done."

# ─── Install Python dependencies ──────────────────────────────────────────────
echo "[3/5] Installing Python dependencies..."
pip install -q -r "${SCRIPT_DIR}/requirements.txt"

# Install llama-cpp-python with CUDA support
CMAKE_ARGS="-DGGML_CUDA=on" pip install -q --force-reinstall \
    "llama-cpp-python[server]" --no-cache-dir

echo "Done."

# ─── Download model ───────────────────────────────────────────────────────────
echo "[4/5] Downloading model: $MODEL_NAME"
mkdir -p "$MODEL_DIR"

if [[ -f "$MODEL_DIR/$MODEL_NAME" ]]; then
    echo "Model already exists at $MODEL_DIR/$MODEL_NAME — skipping download."
else
    echo "Downloading from $MODEL_REPO..."
    huggingface-cli download "$MODEL_REPO" "$MODEL_NAME" \
        --local-dir "$MODEL_DIR" \
        --local-dir-use-symlinks False
    echo "Download complete."
fi

# ─── Write SSH config ─────────────────────────────────────────────────────────
echo "[5/5] Configuring SSH..."
mkdir -p ~/.ssh
chmod 700 ~/.ssh
cat > ~/.ssh/config << 'EOF'
Host vps-tunnel
    StrictHostKeyChecking no
    ServerAliveInterval 30
    ServerAliveCountMax 3
    ConnectTimeout 15
    IdentityFile /tmp/kaggle_tunnel_key
EOF
chmod 600 ~/.ssh/config

echo ""
echo "=== Setup complete ==="
echo "Next steps:"
echo "  1. Start LLM server:   bash kaggle/start_llama_server.sh"
echo "  2. Open tunnel:        bash kaggle/reverse_tunnel_to_vps.sh"
echo "  3. Start watchdog:     python3 kaggle/session_watchdog.py &"
echo ""
echo "Model path: $MODEL_DIR/$MODEL_NAME"
