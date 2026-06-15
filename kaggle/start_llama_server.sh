#!/usr/bin/env bash
set -euo pipefail

# Start llama.cpp HTTP server on Kaggle T4 GPU.
# Exposes OpenAI-compatible /v1 API on port 8080.

MODEL_DIR="${MODEL_DIR:-/kaggle/working/models}"
MODEL_NAME="${MODEL_NAME:-qwen2.5-coder-7b-instruct-q4_k_m.gguf}"
MODEL_PATH="${MODEL_DIR}/${MODEL_NAME}"
PORT="${LOCAL_LLM_PORT:-8080}"
HOST="${LOCAL_LLM_HOST:-127.0.0.1}"
CONTEXT_SIZE="${CONTEXT_SIZE:-8192}"
N_GPU_LAYERS="${N_GPU_LAYERS:--1}"    # -1 = all layers on GPU
PARALLEL="${PARALLEL:-4}"             # concurrent request slots
THREADS="${THREADS:-4}"

echo "=== Starting llama.cpp server ==="
echo "Model:    $MODEL_PATH"
echo "Host:     $HOST:$PORT"
echo "Context:  $CONTEXT_SIZE tokens"
echo "GPU:      all layers (-1)"
echo ""

if [[ ! -f "$MODEL_PATH" ]]; then
    echo "ERROR: Model not found at $MODEL_PATH"
    echo "Run setup_kaggle_gpu_worker.sh first."
    exit 1
fi

# Use llama-cpp-python's built-in server
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
    --verbose false
