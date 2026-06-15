# Model Matrix

Which LLM to use for each type of task in this workspace.

## Quick Decision Guide

```
Task type?
├── Complex reasoning / architecture → Claude Opus 4.8 (API)
├── Everyday coding / refactoring   → Claude Sonnet 4.6 (API) — default
├── Simple edits / quick questions  → Claude Haiku 4.5 (API) — fastest, cheapest
├── Kaggle GPU available?
│   ├── Code completion / small edits → Qwen2.5-Coder-7B (local, free)
│   └── Larger context / full files   → DeepSeek-Coder-7B (local, free)
└── OpenAI preference
    └── o4-mini (reasoning tasks) or gpt-4.1 (general)
```

## API Providers

### Anthropic (Primary)

| Model | ID | Best for | Relative cost |
|-------|-----|---------|--------------|
| Claude Opus 4.8 | `claude-opus-4-8` | Architecture, complex debugging, long-context analysis | $$$ |
| Claude Sonnet 4.6 | `claude-sonnet-4-6` | General coding, PRs, reviews — daily driver | $$ |
| Claude Haiku 4.5 | `claude-haiku-4-5-20251001` | Quick edits, completions, low-latency tasks | $ |

Configure in agent tools:
```bash
# Claude Code default model
export ANTHROPIC_MODEL=claude-sonnet-4-6

# Override for a specific run
claude --model claude-opus-4-8 "redesign the auth module"
```

### OpenAI (Secondary)

| Model | ID | Best for |
|-------|-----|---------|
| GPT-4.1 | `gpt-4.1` | Alternative perspective, tool-calling heavy tasks |
| o4-mini | `o4-mini` | Reasoning-heavy tasks (maths, algorithms) |

Configure in Aider:
```bash
aider --model gpt-4.1 src/main.py
```

## Local Models (Kaggle T4 GPU)

### Recommended Models by Task

| Task | Model | VRAM usage | Notes |
|------|-------|-----------|-------|
| Code completion | Qwen2.5-Coder-7B-Instruct-Q4_K_M | ~4.5 GB | Best code quality at 7B |
| General coding | DeepSeek-Coder-V2-Lite-Instruct-Q4 | ~4.5 GB | Strong on Python/JS |
| Chat / planning | Llama-3.2-3B-Instruct-Q8 | ~3.5 GB | Fast, good for planning |
| Long context | Mistral-Nemo-Instruct-Q4 | ~8 GB | 128K context window |

T4 has 16 GB VRAM. Q4 quantisation of 7B models uses ~4–5 GB, leaving room for overhead.
**Do not load 13B+ models in Q4 on a single T4** — they will OOM.

### Model Download Commands (on Kaggle)

```bash
# llama.cpp format (GGUF)
huggingface-cli download Qwen/Qwen2.5-Coder-7B-Instruct-GGUF \
  qwen2.5-coder-7b-instruct-q4_k_m.gguf \
  --local-dir /kaggle/working/models/

# vLLM format (HuggingFace)
huggingface-cli download Qwen/Qwen2.5-Coder-7B-Instruct \
  --local-dir /kaggle/working/models/qwen25-coder-7b/
```

### Context Length by Model

| Model | Context | Notes |
|-------|---------|-------|
| Qwen2.5-Coder-7B | 32K tokens | Plenty for most files |
| DeepSeek-Coder-7B | 16K tokens | Sufficient for most tasks |
| Mistral-Nemo | 128K tokens | Use for whole-repo analysis |
| Claude Sonnet 4.6 | 200K tokens | Best for large codebases |

## Provider Switching

Use `scripts/switch_provider.sh` to change the active provider for all agent tools:

```bash
# Switch to Kaggle local GPU
bash scripts/switch_provider.sh local

# Switch to Anthropic
bash scripts/switch_provider.sh anthropic

# Switch to OpenAI
bash scripts/switch_provider.sh openai

# Check current provider
bash scripts/switch_provider.sh status
```

This updates the `.env` file and exports new environment variables into the current shell session.

## Cost Management

### Estimating API costs

Claude Sonnet 4.6 pricing (approximate, verify at anthropic.com):
- Input: $3 / 1M tokens
- Output: $15 / 1M tokens

A typical Aider coding session on a medium file (500 lines):
- Input: ~10K tokens (file + conversation context)
- Output: ~2K tokens (code changes + explanation)
- Cost: ~$0.06 per exchange

### Cost-saving strategies

1. **Use local GPU for exploration**: Iterate freely with local models, only use API for final polish
2. **Use Haiku for simple tasks**: Asking Haiku to rename a variable costs ~10× less than Opus
3. **Set token budgets**: `claude --max-tokens 2000` for quick tasks
4. **Prefer streaming**: Catch bad responses early and Ctrl+C to stop billing
5. **Cache warmup**: Claude API caches prompt prefixes — keep system prompts consistent to benefit

## Agentic Tool Model Configuration

### Claude Code
```bash
# ~/.claude/settings.json (on VPS)
{
  "model": "claude-sonnet-4-6",
  "fallback_model": "claude-haiku-4-5-20251001"
}
```

### Aider
```bash
# ~/.aider.conf.yml (on VPS)
model: claude/claude-sonnet-4-6
# Local GPU override:
# openai-api-base: http://localhost:8081/v1
# openai-api-key: local
# model: openai/local-model
```

### OpenCode
```bash
# ~/.config/opencode/config.json
{
  "provider": "anthropic",
  "model": "claude-sonnet-4-6"
}
```
