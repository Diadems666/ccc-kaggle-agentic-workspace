# Codex CLI

Codex CLI is OpenAI's command-line coding agent. It's useful for shell-integrated tasks and quick code generation.

## Installation

```bash
# Install globally via npm
sudo npm install -g @openai/codex

# Verify
codex --version
```

## Configuration

```bash
# Set OpenAI API key
export OPENAI_API_KEY=sk-YOUR_KEY

# Or add to .env
echo 'OPENAI_API_KEY=sk-YOUR_KEY' >> /opt/coding-workspace/.env
```

### Local endpoint configuration

To use with Kaggle GPU or another local LLM server:

```bash
export OPENAI_BASE_URL=http://localhost:8081/v1
export OPENAI_API_KEY=local
```

## Usage

### Interactive mode (default)

```bash
codex
```

### Approval modes

```bash
# Suggest only — shows what it would do, requires confirmation
codex --approval-mode suggest "list all TODO comments in the codebase"

# Auto-edit — edits files but asks before running shell commands
codex --approval-mode auto-edit "rename variable oldName to newName across all files"

# Full auto — runs everything without asking (use with caution)
codex --approval-mode full-auto "run the test suite and fix any failures"
```

### Common use cases

```bash
# Shell command generation
codex "find all Python files larger than 10KB and show their line counts"

# Quick code task
codex "create a script that backs up the database daily"

# Explain and fix
codex "explain what this error means and fix it: $(cat error.log)"

# Documentation
codex "generate API documentation for all public endpoints in src/api/"
```

## When to use Codex CLI

- Shell command generation (its original strength)
- Quick file manipulation tasks
- When you have an OpenAI key and no Anthropic key
- As a fallback when Claude Code rate-limits

For complex coding tasks, Claude Code is generally better. Codex CLI shines for shell-centric workflows.

## Updating

```bash
sudo npm update -g @openai/codex
codex --version
```
