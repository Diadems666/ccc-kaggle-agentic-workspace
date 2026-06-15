#!/usr/bin/env bash
set -euo pipefail

# Start llama.cpp HTTP server on Kaggle T4 GPU(s).
# Auto-configures for dual T4 (32 GB) with larger context and tensor split.
# Exposes OpenAI-compatible /v1 API on port 8080.

MODEL_DIR="${MODEL_DIR:-/kaggle/working/models}"
MODEL_NAME="${MODEL_NAME:-qwen2.5-coder-7b-instruct-q4_k_m.gguf}"
MODEL_PATH="${MODEL_DIR}/${MODEL_NAME}"
PORT="${LOCAL_LLM_PORT:-8080}"
HOST="${LOCAL_LLM_HOST:-127.0.0.1}"
N_GPU_LAYERS="${N_GPU_LAYERS:--1}"
PARALLEL="${PARALLEL:-4}"
THREADS="${THREADS:-4}"

# ─── Detect GPU count and configure accordingly ───────────────────────────────
GPU_COUNT=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | wc -l || echo 1)

if [[ "$GPU_COUNT" -ge 2 ]]; then
    CONTEXT_SIZE="${CONTEXT_SIZE:-8192}"
    echo "=== Starting llama.cpp server (dual T4 — CUDA auto-distributes) ==="
else
    CONTEXT_SIZE="${CONTEXT_SIZE:-8192}"
    echo "=== Starting llama.cpp server (single T4) ==="
fi

echo "Model:    $MODEL_PATH"
echo "Host:     $HOST:$PORT"
echo "Context:  $CONTEXT_SIZE tokens"
echo "GPUs:     $GPU_COUNT (n_gpu_layers=${N_GPU_LAYERS})"
echo ""

if [[ ! -f "$MODEL_PATH" ]]; then
    echo "ERROR: Model not found at $MODEL_PATH"
    echo "Run setup_kaggle_gpu_worker.sh first."
    exit 1
fi

# n_gpu_layers=-1 offloads all layers; CUDA backend distributes across
# all visible GPUs automatically without explicit tensor_split.
python3 -m llama_cpp.server \
    --model "$MODEL_PATH" \
    --host "$HOST" \
    --port "$PORT" \
    --n_ctx "$CONTEXT_SIZE" \
    --n_gpu_layers "$N_GPU_LAYERS" \
    --n_threads "$THREADS" \
    --n_batch 512 \
    --parallel "$PARALLEL" \
    --chat_format chatml \
    --verbose true
