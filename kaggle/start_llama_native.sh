#!/usr/bin/env bash
set -euo pipefail

# Launch the native llama.cpp `llama-server` for Qwen3.8-27B on Kaggle T4 GPUs.
# Exposes an OpenAI-compatible API on 127.0.0.1:$LOCAL_LLM_PORT (never public;
# the reverse SSH tunnel is the only way in).
#
# Required env:
#   LLAMA_SERVER_BIN   path to the llama-server executable
#   MODEL_PATH         path to the .gguf file
#
# Optional env:
#   LOCAL_LLM_PORT     default 8080
#   CONTEXT_SIZE       default 65536 (Qwen3.8 hybrid attention keeps KV small)
#   KV_TYPE            default q8_0  (f16 doubles KV memory)
#   MODEL_ALIAS        default qwen3.8-27b (name clients send as "model")
#   LLM_API_KEY        if set, llama-server requires "Authorization: Bearer <key>"
#   THINKING           off (default) | on  — server-side default; clients can override
#   TEMP / TOP_P / TOP_K / MIN_P   sampling defaults (Qwen-recommended values)
#   PARALLEL           concurrent slots, default 1 (each slot needs its own KV)
#   LLAMA_EXTRA_ARGS   extra raw args appended verbatim (e.g. MTP/speculative flags)

BIN="${LLAMA_SERVER_BIN:?LLAMA_SERVER_BIN not set}"
MODEL_PATH="${MODEL_PATH:?MODEL_PATH not set}"
PORT="${LOCAL_LLM_PORT:-8080}"
CTX="${CONTEXT_SIZE:-65536}"
KV="${KV_TYPE:-q8_0}"
ALIAS="${MODEL_ALIAS:-qwen3.8-27b}"
THINKING="${THINKING:-off}"
PARALLEL="${PARALLEL:-1}"

if [[ "$THINKING" == "on" ]]; then
    TEMP="${TEMP:-1.0}"; TOP_P="${TOP_P:-0.95}"
    THINK_JSON='{"enable_thinking":true}'
else
    TEMP="${TEMP:-0.7}"; TOP_P="${TOP_P:-0.8}"
    THINK_JSON='{"enable_thinking":false}'
fi
TOP_K="${TOP_K:-20}"
MIN_P="${MIN_P:-0.0}"

[[ -x "$BIN" ]] || { echo "ERROR: $BIN is not executable" >&2; exit 1; }
[[ -f "$MODEL_PATH" ]] || { echo "ERROR: model not found: $MODEL_PATH" >&2; exit 1; }

# Flag names drift between llama.cpp versions, so probe --help instead of guessing.
HELP_TEXT="$("$BIN" --help 2>&1 || true)"
has_flag() { grep -q -- "$1" <<<"$HELP_TEXT"; }

ARGS=(
    -m "$MODEL_PATH"
    --host 127.0.0.1
    --port "$PORT"
    -c "$CTX"
    -ngl 99
    --split-mode layer
    -ctk "$KV" -ctv "$KV"
    --alias "$ALIAS"
    --parallel "$PARALLEL"
    --temp "$TEMP" --top-p "$TOP_P" --top-k "$TOP_K" --min-p "$MIN_P"
)

# Flash attention: newer builds take a value (on|off|auto), older ones are a bare switch.
if has_flag '--flash-attn'; then
    if grep -qE -- '(--flash-attn|-fa).*(on\|off|\[on)' <<<"$HELP_TEXT"; then
        ARGS+=(-fa on)
    else
        ARGS+=(-fa)
    fi
fi
has_flag '--jinja'            && ARGS+=(--jinja)
has_flag '--reasoning-format' && ARGS+=(--reasoning-format deepseek)
has_flag '--chat-template-kwargs' && ARGS+=(--chat-template-kwargs "$THINK_JSON")
has_flag '--no-webui'         && ARGS+=(--no-webui)

if [[ -n "${LLM_API_KEY:-}" ]]; then
    ARGS+=(--api-key "$LLM_API_KEY")
fi

# shellcheck disable=SC2206  # intentional word splitting of user-supplied extras
[[ -n "${LLAMA_EXTRA_ARGS:-}" ]] && ARGS+=(${LLAMA_EXTRA_ARGS})

echo "=== llama-server ==="
echo "Model:    $MODEL_PATH"
echo "Alias:    $ALIAS"
echo "Listen:   127.0.0.1:$PORT"
echo "Context:  $CTX (KV $KV, parallel $PARALLEL)"
echo "Thinking: $THINKING (temp=$TEMP top_p=$TOP_P top_k=$TOP_K)"
echo "API key:  $([[ -n "${LLM_API_KEY:-}" ]] && echo set || echo 'NOT set')"
echo ""

exec "$BIN" "${ARGS[@]}"
