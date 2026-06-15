# Aider

Aider is an AI pair-programming tool that integrates deeply with git. It edits files, runs tests, and makes commits automatically.

## Installation

```bash
# Install via pip (Python 3.10+)
pip install aider-chat

# Verify
aider --version
```

## Configuration

### `~/.aider.conf.yml` (on VPS)

```yaml
# Default model
model: claude/claude-sonnet-4-6

# Git integration
auto-commits: true
git: true
commit-prompt: "Summarise the change in one line, imperative tense, no period"

# Output
pretty: true
stream: true
dark-mode: true

# Behaviour
auto-test: false       # set to true and configure test-cmd to auto-run tests
suggest-shell-commands: true
```

### `.aider.conf.yml` per project (in project root)

```yaml
# Override model for this project
model: claude/claude-opus-4-8

# Project-specific test command
auto-test: true
test-cmd: pytest tests/ -x -q

# Files to always include in context
read:
  - AGENTS.md
  - src/types.py
```

## Basic Usage

### Start a pair-programming session

```bash
# Single file
aider src/main.py

# Multiple files
aider src/api/auth.py src/models/user.py tests/test_auth.py

# All Python files in a directory
aider src/api/*.py

# With an initial message
aider --message "add input validation to all POST endpoints" src/api/
```

### Inside an Aider session

```
> /help                  — show commands
> /add src/utils.py      — add a file to the session
> /drop src/old.py       — remove a file
> /diff                  — show current diff
> /commit                — commit changes manually
> /undo                  — undo last commit
> /run pytest tests/     — run a shell command
> /exit                  — end session
```

Type plain English to describe what you want:

```
> Add a retry mechanism to the API client with exponential backoff. Max 3 retries.
> Write tests for the new retry logic.
> Refactor the error handling to use custom exception classes.
```

## Local GPU (Kaggle)

When the Kaggle tunnel is active:

```bash
aider \
  --openai-api-base http://localhost:8081/v1 \
  --openai-api-key local \
  --model openai/qwen2.5-coder-7b-instruct \
  src/main.py
```

Or use the provider switcher:
```bash
bash scripts/switch_provider.sh local
source /opt/coding-workspace/.env
aider src/main.py  # reads LLM_BASE_URL and LLM_MODEL from env
```

## Git Integration

Aider auto-commits after each successful change. Commits look like:

```
aider: Add input validation to registration endpoint

Applied by aider with claude-sonnet-4-6
```

### Squashing aider commits

Before merging a feature branch:

```bash
# Interactive rebase to squash aider commits
git rebase -i origin/main

# Change "pick" to "squash" for each aider commit you want to fold in
# Edit the final commit message
```

### Undoing an aider change

```bash
aider --undo      # undo last aider commit
# or
git revert HEAD   # create a revert commit
```

## Mobile Usage

In the code-server terminal on your phone:

```bash
aider src/main.py
```

For longer prompts on mobile, use a multi-line input:

```
> Add a function that:
> 1. Takes a list of user IDs
> 2. Fetches each user from the database
> 3. Returns them as a list of UserResponse objects
> 4. Handles the case where a user doesn't exist
```

## Common Patterns

### Test-driven development

```bash
aider --message "write failing tests first, then implement" tests/test_feature.py src/feature.py
```

### Refactoring

```bash
# Show aider the files involved in the refactor
aider src/old_module.py src/new_module.py

# Inside session:
> Migrate all the functionality from old_module to new_module, updating all import references
```

### Code review as edits

```bash
# Let aider apply review feedback directly
git diff main..feature | aider --message "apply these review comments as code fixes" src/
```

## Updating

```bash
pip install --upgrade aider-chat
aider --version
```
