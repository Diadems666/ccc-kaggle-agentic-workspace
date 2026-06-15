#!/usr/bin/env bash
set -euo pipefail

# Start vLLM server on Kaggle T4 GPU.
# Higher throughput than llama.cpp for concurrent requests.
# Uses HuggingFace model format (not GGUF).

MODEL_NAME="${VLLM_MODEL:-Qwen/Qwen2.5-Coder-7B-Instruct}"
PORT="${LOCAL_LLM_PORT:-8080}"
HOST="${LOCAL_LLM_HOST:-127.0.0.1}"
DTYPE="${DTYPE:-half}"          # half precision for T4
MAX_MODEL_LEN="${MAX_MODEL_LEN:-8192}"
GPU_MEMORY_UTILISATION="${GPU_UTIL:-0.85}"

echo "=== Starting vLLM server ==="
echo "Model:        $MODEL_NAME"
echo "Host:         $HOST:$PORT"
echo "Max length:   $MAX_MODEL_LEN tokens"
echo "GPU util:     ${GPU_MEMORY_UTILISATION}"
echo ""

# Install vLLM if not present
if ! python3 -c "import vllm" 2>/dev/null; then
    echo "Installing vLLM..."
    pip install -q vllm
fi

python3 -m vllm.entrypoints.openai.api_server \
    --model "$MODEL_NAME" \
    --host "$HOST" \
    --port "$PORT" \
    --dtype "$DTYPE" \
    --max-model-len "$MAX_MODEL_LEN" \
    --gpu-memory-utilization "$GPU_MEMORY_UTILISATION" \
    --trust-remote-code \
    --served-model-name "$(basename $MODEL_NAME | tr '[:upper:]' '[:lower:]')"
