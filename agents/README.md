# Agent Tools

This directory contains setup guides and configuration for each agentic coding tool used in this workspace.

## Provider Strategy

```
Task complexity →  Simple    Medium    Complex
                     │          │         │
                     ▼          ▼         ▼
                  Haiku 4.5  Sonnet 4.6  Opus 4.8
                     │
                     ▼
              (or local GPU if Kaggle tunnel active)
```

Use the cheapest model that gets the job done. Most everyday coding tasks are well-served by Sonnet 4.6. Reserve Opus 4.8 for architecture reviews, complex debugging, and tasks where quality matters most.

## Agents in This Workspace

| File | Tool | When to use |
|------|------|------------|
| `claude-code.md` | Claude Code | Best overall tool — use by default |
| `aider.md` | Aider | Pair-programming, file-level edits, auto-commits |
| `opencode.md` | OpenCode | TUI alternative, exploration sessions |
| `codex-cli.md` | Codex CLI | Shell commands, quick one-liners |
| `local-kaggle-provider.example.json` | Local GPU | Config reference for local endpoint |

## Common Pattern

```bash
# 1. Check which provider is active
bash scripts/switch_provider.sh status

# 2. Start the right agent for your task
claude              # complex reasoning, long-context
aider file.py       # pair-programming with a specific file
opencode            # interactive TUI exploration

# 3. Switch provider if Kaggle GPU is available
bash scripts/switch_provider.sh local
aider --openai-api-base http://localhost:8081/v1 file.py
```

## Mobile Usage

All agents run in the code-server / OpenVSCode Server terminal. On mobile:
- Open the IDE in your browser
- Tap the terminal panel (or Ctrl+`)
- Type your agent command — the keyboard is responsive on iOS/Android
- Use voice dictation (iOS microphone key) for longer prompts
