#!/usr/bin/env bash
set -euo pipefail

# Setup Kaggle T4 notebook as LLM inference worker.
# Auto-selects 32B model on dual T4 (32 GB VRAM), 7B on single T4.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL_DIR="${MODEL_DIR:-/kaggle/working/models}"

echo "=== CCC Kaggle GPU Worker Setup ==="

# ─── Verify GPU & auto-select model ──────────────────────────────────────────
echo "[1/6] Checking GPU..."
if ! command -v nvidia-smi &>/dev/null; then
    echo "ERROR: nvidia-smi not found. Enable GPU accelerator in notebook settings."
    exit 1
fi
nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader

GPU_COUNT=$(nvidia-smi --query-gpu=name --format=csv,noheader | wc -l)
echo "  GPUs detected: $GPU_COUNT"

# Auto-select model based on VRAM unless user explicitly set MODEL_NAME
if [[ -n "${MODEL_NAME:-}" ]]; then
    MODEL_REPO="${MODEL_REPO:-Qwen/Qwen2.5-Coder-7B-Instruct-GGUF}"
    echo "  Using user-specified model: $MODEL_NAME"
elif [[ "$GPU_COUNT" -ge 2 ]]; then
    MODEL_NAME="qwen2.5-coder-32b-q4_k_m.gguf"
    MODEL_REPO="Qwen/Qwen2.5-Coder-32B-Instruct-GGUF"
    echo "  Dual T4 (32 GB VRAM) — auto-selected: $MODEL_NAME"
else
    MODEL_NAME="qwen2.5-coder-7b-instruct-q4_k_m.gguf"
    MODEL_REPO="Qwen/Qwen2.5-Coder-7B-Instruct-GGUF"
    echo "  Single T4 (16 GB VRAM) — auto-selected: $MODEL_NAME"
fi

export MODEL_NAME MODEL_REPO GPU_COUNT
echo "Model dir:  $MODEL_DIR"
echo "Model:      $MODEL_NAME"
echo ""

# ─── Install system dependencies ──────────────────────────────────────────────
echo "[2/6] Installing system dependencies..."
apt-get install -qq -y openssh-client cmake build-essential curl \
    libcurl4-openssl-dev nodejs npm 2>/dev/null || true
echo "Done."

# ─── Install Python dependencies ──────────────────────────────────────────────
echo "[3/6] Installing Python dependencies..."
pip install -q -r "${SCRIPT_DIR}/requirements.txt"

CMAKE_ARGS="-DGGML_CUDA=on" pip install -q --force-reinstall \
    "llama-cpp-python[server]" --no-cache-dir

echo "Done."

# ─── Install MiMo Code agent harness ─────────────────────────────────────────
echo "[4/6] Installing MiMo Code..."
npm install -g @mimo-ai/cli --silent 2>/dev/null || \
    echo "  WARNING: MiMo Code install failed — continuing without it"
echo "  $(mimo --version 2>/dev/null || echo 'mimo not available')"

# ─── Download model ───────────────────────────────────────────────────────────
echo "[5/6] Downloading model: $MODEL_NAME"
mkdir -p "$MODEL_DIR"

if [[ -f "$MODEL_DIR/$MODEL_NAME" ]]; then
    SIZE_GB=$(du -sh "$MODEL_DIR/$MODEL_NAME" | cut -f1)
    echo "  Already cached: $MODEL_DIR/$MODEL_NAME ($SIZE_GB) — skipping."
else
    echo "  Downloading from $MODEL_REPO (~$([ "$GPU_COUNT" -ge 2 ] && echo "19 GB" || echo "4.5 GB"), may take 5-10 min)..."
    huggingface-cli download "$MODEL_REPO" "$MODEL_NAME" \
        --local-dir "$MODEL_DIR" \
        --local-dir-use-symlinks False
    echo "  Download complete."
fi

# ─── Write SSH config ─────────────────────────────────────────────────────────
echo "[6/6] Configuring SSH..."
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
echo "  GPUs:  $GPU_COUNT x T4"
echo "  Model: $MODEL_DIR/$MODEL_NAME"
