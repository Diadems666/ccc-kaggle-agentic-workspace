# Claude Code

Claude Code is Anthropic's official agentic coding CLI. It's the primary tool in this workspace.

## Installation

```bash
# Install globally (run as root or with sudo on VPS)
sudo npm install -g @anthropic-ai/claude-code

# Verify
claude --version
```

## Configuration

### API key

```bash
export ANTHROPIC_API_KEY=sk-ant-YOUR_KEY

# Or add to ~/.bashrc / VPS .env:
echo 'export ANTHROPIC_API_KEY=sk-ant-YOUR_KEY' >> ~/.bashrc
```

### Settings file

`~/.claude/settings.json`:

```json
{
  "model": "claude-sonnet-4-6",
  "permissions": {
    "allow": [
      "Bash(git:*)",
      "Bash(npm:*)",
      "Bash(python3:*)",
      "Read",
      "Write",
      "Edit",
      "Glob",
      "Grep"
    ],
    "deny": []
  },
  "theme": "dark"
}
```

### Project-level config

Add `CLAUDE.md` to your project root to give Claude persistent context:

```markdown
# Project Context

This is a Python FastAPI project. Key conventions:
- Use async/await throughout
- Follow PEP 8 and type hint everything
- Tests use pytest with httpx for async test client
- Database: PostgreSQL via SQLAlchemy 2.0 async
```

## Usage

### Interactive session (most common)

```bash
cd /opt/coding-workspace/repos/my-project
claude
```

Claude will load `CLAUDE.md` if present and enter an interactive session. Type tasks in plain English.

### One-shot tasks

```bash
# Generate code
claude "add a rate limiting middleware to src/api/middleware.py"

# Review
git diff origin/main | claude "review this diff for bugs"

# Explain
claude "explain the data flow in src/worker/pipeline.py"

# Tests
claude "write comprehensive tests for src/utils/validators.py"
```

### Piping and shell integration

```bash
# Feed a file
cat src/broken.py | claude "fix the bug in this code"

# Feed command output
mycommand 2>&1 | claude "interpret this error and suggest a fix"

# Chain with git
git log --oneline -20 | claude "summarise these commits for a release note"
```

### Model selection

```bash
# Default (Sonnet 4.6)
claude "task"

# Upgrade to Opus for hard tasks
claude --model claude-opus-4-8 "redesign the authentication system"

# Downgrade to Haiku for cheap tasks
claude --model claude-haiku-4-5-20251001 "rename variable foo to user_count"

# Fast mode (Opus with faster output)
claude --fast "review this PR quickly"
```

## Mobile Workflow

On your phone via the browser IDE:

1. Open terminal in code-server
2. Navigate to your project
3. Type `claude` to start an interactive session
4. Use iOS voice dictation (tap microphone on keyboard) to dictate longer prompts
5. Claude reads your code files directly — no need to paste them

### Tip: slash commands

In an interactive `claude` session, use slash commands:

- `/help` — show available commands
- `/clear` — clear conversation context
- `/compact` — summarise context to save tokens
- `/model claude-opus-4-8` — switch model mid-session
- `/review` — review current diff

## Updating

```bash
sudo npm update -g @anthropic-ai/claude-code
claude --version
```
