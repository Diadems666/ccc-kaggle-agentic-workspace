# OpenCode

OpenCode is a terminal UI (TUI) agentic coding tool. It provides an interactive chat-like interface in the terminal with access to your codebase.

## Installation

```bash
# Install globally via npm
sudo npm install -g opencode-ai

# Verify
opencode --version
```

## Configuration

### `~/.config/opencode/config.json`

```json
{
  "provider": "anthropic",
  "model": "claude-sonnet-4-6",
  "theme": "dark",
  "autosave": true
}
```

### Provider options

```json
{
  "provider": "anthropic",
  "model": "claude-sonnet-4-6",
  "apiKey": "sk-ant-..."
}
```

```json
{
  "provider": "openai",
  "model": "gpt-4.1",
  "apiKey": "sk-..."
}
```

```json
{
  "provider": "openai",
  "model": "qwen2.5-coder-7b-instruct",
  "baseUrl": "http://localhost:8081/v1",
  "apiKey": "local"
}
```

## Usage

### Start interactive TUI session

```bash
cd /opt/coding-workspace/repos/my-project
opencode
```

The TUI shows:
- Left panel: conversation / chat
- Right panel: file tree / editor
- Bottom: input box

### Key bindings (in TUI)

| Key | Action |
|-----|--------|
| Tab | Switch focus between panels |
| Enter | Send message |
| Shift+Enter | New line in message |
| Ctrl+C | Exit |
| Ctrl+L | Clear conversation |
| `?` | Show help |

### One-shot (non-interactive)

```bash
opencode run "add docstrings to all public functions in src/"
opencode run "generate a database schema for a blog with posts, tags, and comments"
```

### With directory context

```bash
opencode --dir src/api/
```

OpenCode will include the directory tree in its context.

## When to use OpenCode vs Claude Code vs Aider

| Scenario | Best tool |
|----------|-----------|
| Quick interactive session | Claude Code |
| Pair-programming with auto-commits | Aider |
| Exploring an unfamiliar codebase | OpenCode TUI |
| One-shot code generation | Claude Code |
| Multiple file refactor | Aider |
| Shell integration / piping | Claude Code |

OpenCode's TUI is particularly good for exploration: you can navigate the file tree while chatting, making it easy to reference different parts of a large codebase.

## Updating

```bash
sudo npm update -g opencode-ai
opencode --version
```
