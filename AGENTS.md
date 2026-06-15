# Agents

Configuration and conventions for all agentic coding tools in this workspace.

## Active Agents

| Tool | Primary use | Provider | Status |
|------|------------|---------|--------|
| Claude Code | Architecture, reviews, complex tasks | Anthropic API | Primary |
| Aider | Pair-programming, file editing, commits | Anthropic / local | Primary |
| OpenCode | TUI-based sessions, exploration | Anthropic / OpenAI | Secondary |
| Codex CLI | Quick completions, shell assistance | OpenAI | Optional |

## Claude Code

See `agents/claude-code.md` for full setup guide.

### Quick config

```bash
# ~/.claude/settings.json
{
  "model": "claude-sonnet-4-6",
  "permissions": {
    "allow": ["Bash", "Read", "Write", "Edit", "Glob", "Grep"]
  }
}
```

### Usage patterns

```bash
# Interactive session (most common)
claude

# One-shot task
claude "write a pytest suite for src/api/auth.py"

# Review a diff before committing
git diff | claude "review this diff for bugs and security issues"

# Explain a file
claude "explain what src/worker.py does and identify potential issues"
```

## Aider

See `agents/aider.md` for full setup guide.

### Quick config

```yaml
# ~/.aider.conf.yml
model: claude/claude-sonnet-4-6
auto-commits: true
git: true
pretty: true
stream: true
```

### Usage patterns

```bash
# Edit a specific file
aider src/main.py

# Edit multiple related files
aider src/models/user.py src/api/auth.py

# With a task description
aider --message "add password reset endpoint" src/api/auth.py

# No auto-commit (manual review)
aider --no-auto-commits src/main.py
```

## OpenCode

See `agents/opencode.md` for full setup guide.

### Usage patterns

```bash
# Launch interactive TUI
opencode

# With a specific directory context
opencode --dir src/

# One-shot
opencode run "generate database migration for adding user roles"
```

## Codex CLI

See `agents/codex-cli.md` for full setup guide.

### Usage patterns

```bash
# Shell command suggestion
codex "list all Python files modified in the last 7 days"

# Code generation
codex "write a bash script that monitors disk usage and alerts when > 80%"

# With approval mode
codex --approval-mode suggest "refactor this function to be async"
```

## Agent Conventions

### Git integration

All agents are configured to:
- Work in the current git repository
- Auto-stage and commit changes (Aider)
- Leave commits for manual review (Claude Code, OpenCode)
- Never push automatically (always requires `git push` from you)

### File access

Agents have read/write access to:
- The current project directory and subdirectories
- `~/.env` (read-only, for environment variables)

Agents should NOT be given access to:
- SSH keys (`~/.ssh/`)
- System files outside the workspace
- Other users' home directories

### Context files

Place these files in your project root to guide agent behaviour:

- `AGENTS.md` — agent-specific instructions (copy from `templates/AGENTS.md`)
- `CLAUDE.md` — Claude-specific instructions (auto-loaded by Claude Code)
- `.aider.conf.yml` — Aider config (model, commit style, etc.)

### Token budget management

When working on large files or complex tasks, be mindful of context limits:

```bash
# Check current model context limit
claude "what is your context window size?"

# For very large files, use targeted prompts:
aider --message "focus only on the authentication functions" src/api/auth.py

# Split large refactors across multiple sessions:
# Session 1: database layer
# Session 2: API layer
# Session 3: tests
```

## Provider Configuration

All agent tools read provider settings from the environment:

```bash
# Anthropic (default)
ANTHROPIC_API_KEY=sk-ant-...
ANTHROPIC_MODEL=claude-sonnet-4-6

# OpenAI (optional)
OPENAI_API_KEY=sk-...

# Local Kaggle GPU
LLM_BASE_URL=http://localhost:8081/v1
LLM_API_KEY=local
LLM_MODEL=qwen2.5-coder-7b-instruct
```

Switch providers with:
```bash
bash scripts/switch_provider.sh [anthropic|openai|local]
```

## Session Management

### Starting a productive session

1. Pull latest code: `git pull`
2. Check GPU status: `bash scripts/check_gpu_backend.sh`
3. Start agent session: `bash scripts/start_agent_session.sh`
4. Set context: open the files you'll work on in the IDE before invoking the agent

### Ending a session

```bash
bash scripts/stop_agent_session.sh
git add -A
git commit -m "wip: [brief description]"
git push
```

### Resuming a session

```bash
git pull
# Review what was in progress:
git log --oneline -10
cat PROGRESS.md
# Resume:
aider --message "continue from where we left off" $(git diff HEAD~1 --name-only)
```
