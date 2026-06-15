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

# Auto-select model: upgrade 7B→32B on dual T4 even if env var carries the 7B default.
# Only honour MODEL_NAME if it's something other than the known 7B default.
_DEFAULT_7B="qwen2.5-coder-7b-instruct-q4_k_m.gguf"
if [[ -z "${MODEL_NAME:-}" || "${MODEL_NAME}" == "$_DEFAULT_7B" ]]; then
    if [[ "$GPU_COUNT" -ge 2 ]]; then
        MODEL_NAME="qwen2.5-coder-32b-q4_k_m.gguf"
        MODEL_REPO="Qwen/Qwen2.5-Coder-32B-Instruct-GGUF"
        echo "  Dual T4 (32 GB VRAM) → auto-upgrading to 32B model"
    else
        MODEL_NAME="$_DEFAULT_7B"
        MODEL_REPO="Qwen/Qwen2.5-Coder-7B-Instruct-GGUF"
        echo "  Single T4 (16 GB VRAM) → using 7B model"
    fi
else
    MODEL_REPO="${MODEL_REPO:-Qwen/Qwen2.5-Coder-7B-Instruct-GGUF}"
    echo "  User-specified model: $MODEL_NAME"
fi

export MODEL_NAME MODEL_REPO GPU_COUNT
echo "Model dir:  $MODEL_DIR"
echo "Model:      $MODEL_NAME"
echo ""

# ─── Install system dependencies ──────────────────────────────────────────────
echo "[2/6] Installing system dependencies..."
apt-get install -qq -y openssh-client cmake build-essential curl \
    libcurl4-openssl-dev 2>/dev/null || true

# @mimo-ai/cli requires Node.js 18+. Ubuntu 22.04's default is Node 12 — upgrade.
NODE_MAJOR=$(node --version 2>/dev/null | tr -d 'v' | cut -d. -f1 || echo "0")
if [[ "$NODE_MAJOR" -lt 18 ]]; then
    echo "  Node.js ${NODE_MAJOR} detected, upgrading to Node.js 20..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null 2>&1
    # libnode-dev from Ubuntu's old Node 12 blocks the upgrade — remove it first
    apt-get remove -y libnode-dev libnode72 2>/dev/null || true
    apt-get install -y -q nodejs 2>/dev/null || true
fi
echo "  Node.js $(node --version 2>/dev/null || echo 'unavailable')"
echo "Done."

# ─── Install Python dependencies ──────────────────────────────────────────────
echo "[3/6] Installing Python dependencies..."
pip install -q -r "${SCRIPT_DIR}/requirements.txt"

# Use pre-built CUDA wheel (avoids 5-min source compile that often fails).
# Falls back to source build targeting T4 (sm_75) if pre-built isn't available.
CUDA_FULL=$(nvcc --version 2>/dev/null | grep -oP 'V\K[\d.]+' | head -1 || echo "12.1")
CUDA_TAG="cu$(echo "$CUDA_FULL" | cut -d. -f1)$(echo "$CUDA_FULL" | cut -d. -f2)"
echo "  CUDA $CUDA_FULL — trying pre-built wheel (${CUDA_TAG})..."

if pip install -q "llama-cpp-python[server]" \
    --extra-index-url "https://abetlen.github.io/llama-cpp-python/whl/${CUDA_TAG}" \
    2>/dev/null; then
    echo "  Installed pre-built CUDA wheel (${CUDA_TAG})"
else
    echo "  Pre-built wheel not found, building from source for sm_75..."
    CMAKE_ARGS="-DGGML_CUDA=on -DCMAKE_CUDA_ARCHITECTURES=75" \
        pip install -q "llama-cpp-python[server]" --no-cache-dir
fi
echo "Done."

# ─── Install MiMo Code agent harness ─────────────────────────────────────────
echo "[4/6] Installing MiMo Code..."
npm install -g @mimo-ai/cli 2>/dev/null || \
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
    # huggingface-cli is deprecated in hub>=1.10 — use `hf` (already on Kaggle)
    HF_CMD=$(command -v hf 2>/dev/null || command -v huggingface-cli 2>/dev/null)
    "$HF_CMD" download "$MODEL_REPO" "$MODEL_NAME" \
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
