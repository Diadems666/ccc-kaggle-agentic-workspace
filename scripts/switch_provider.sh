#!/usr/bin/env bash
set -euo pipefail

# Switch the active LLM provider for all agent tools.
# Updates ACTIVE_PROVIDER and related env vars in the workspace .env.

WORKSPACE_DIR="${WORKSPACE_DIR:-/opt/coding-workspace}"
ENV_FILE="${WORKSPACE_DIR}/.env"

PROVIDER="${1:-}"

usage() {
    echo "Usage: $0 [anthropic|openai|local|status]"
    echo ""
    echo "  anthropic  — Use Anthropic Claude API (default)"
    echo "  openai     — Use OpenAI API"
    echo "  local      — Use local Kaggle GPU via tunnel"
    echo "  status     — Show current provider"
    exit 1
}

if [[ -z "$PROVIDER" ]]; then
    usage
fi

# Load current env
if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
fi

# Show status
if [[ "$PROVIDER" == "status" ]]; then
    echo "Active provider: ${ACTIVE_PROVIDER:-anthropic}"
    echo "Active model:    ${ACTIVE_MODEL:-claude-sonnet-4-6}"
    if [[ "${ACTIVE_PROVIDER:-}" == "local" ]]; then
        echo "LLM base URL:    ${LLM_BASE_URL:-http://localhost:8081/v1}"
    fi
    exit 0
fi

# Update .env file helper
update_env() {
    local KEY="$1"
    local VALUE="$2"
    if [[ -f "$ENV_FILE" ]]; then
        if grep -q "^${KEY}=" "$ENV_FILE"; then
            sed -i "s|^${KEY}=.*|${KEY}=${VALUE}|" "$ENV_FILE"
        else
            echo "${KEY}=${VALUE}" >> "$ENV_FILE"
        fi
    fi
    export "${KEY}=${VALUE}"
}

case "$PROVIDER" in
    anthropic)
        echo "Switching to Anthropic Claude..."
        update_env "ACTIVE_PROVIDER" "anthropic"
        update_env "ACTIVE_MODEL" "${ANTHROPIC_MODEL:-claude-sonnet-4-6}"
        echo ""
        echo "Active provider: anthropic"
        echo "Active model:    ${ANTHROPIC_MODEL:-claude-sonnet-4-6}"
        echo ""
        echo "Aider config:   edit ~/.aider.conf.yml → model: claude/claude-sonnet-4-6"
        ;;

    openai)
        if [[ -z "${OPENAI_API_KEY:-}" ]]; then
            echo "WARNING: OPENAI_API_KEY not set in .env"
        fi
        echo "Switching to OpenAI..."
        update_env "ACTIVE_PROVIDER" "openai"
        update_env "ACTIVE_MODEL" "${OPENAI_MODEL:-gpt-4.1}"
        echo ""
        echo "Active provider: openai"
        echo "Active model:    ${OPENAI_MODEL:-gpt-4.1}"
        ;;

    local)
        KAGGLE_PORT="${KAGGLE_TUNNEL_PORT:-8081}"
        # Verify tunnel is active
        if ! ss -tlnp 2>/dev/null | grep -q ":${KAGGLE_PORT}"; then
            echo "WARNING: Kaggle tunnel not detected on port ${KAGGLE_PORT}"
            echo "Start the Kaggle GPU session and tunnel first, then switch provider."
            echo ""
            echo "Switching anyway (you can switch and start the tunnel later)..."
        else
            echo "Kaggle tunnel detected on port ${KAGGLE_PORT}."
        fi

        LLM_URL="http://localhost:${KAGGLE_PORT}/v1"
        LLM_MODEL_ID="${LLM_MODEL:-qwen2.5-coder-7b-instruct}"

        update_env "ACTIVE_PROVIDER" "local"
        update_env "ACTIVE_MODEL" "$LLM_MODEL_ID"
        update_env "LLM_BASE_URL" "$LLM_URL"
        update_env "LLM_API_KEY" "local"

        echo ""
        echo "Active provider: local (Kaggle GPU)"
        echo "LLM base URL:    $LLM_URL"
        echo "Model:           $LLM_MODEL_ID"
        echo ""
        echo "To use with aider:"
        echo "  aider --openai-api-base $LLM_URL --openai-api-key local --model openai/$LLM_MODEL_ID"
        ;;

    *)
        echo "Unknown provider: $PROVIDER"
        usage
        ;;
esac

echo ""
echo "Provider switch complete. Source .env to update current shell:"
echo "  source $ENV_FILE"
