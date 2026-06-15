# Templates

Copy these files into new projects to set up consistent structure and agent context.

## Usage

```bash
# Start a new project
mkdir /opt/coding-workspace/repos/my-project
cd /opt/coding-workspace/repos/my-project
git init

# Copy templates
cp /opt/coding-workspace/templates/AGENTS.md .
cp /opt/coding-workspace/templates/TASKS.md .
cp /opt/coding-workspace/templates/PROGRESS.md .
cp /opt/coding-workspace/templates/DECISIONS.md .
cp /opt/coding-workspace/templates/IMPLEMENTATION_NOTES.md .

# Rename AGENTS.md to CLAUDE.md for Claude Code auto-loading
cp /opt/coding-workspace/templates/AGENTS.md CLAUDE.md
```

## Files

| Template | Purpose |
|----------|---------|
| `AGENTS.md` | Per-project agent instructions (copy as `CLAUDE.md` for Claude Code) |
| `PROMPT.md` | Session-level prompt template |
| `TASKS.md` | Task backlog template |
| `PROGRESS.md` | Session log template |
| `DECISIONS.md` | Architectural decision record template |
| `IMPLEMENTATION_NOTES.md` | Technical notes template |
| `PROJECT_RUNBOOK.md` | Operational runbook template |

## Customisation

Edit the templates to suit each project. The key file is `AGENTS.md` / `CLAUDE.md` — this gives the agent context about:
- What the project does
- Tech stack and conventions
- File structure
- What to avoid (destructive commands, certain patterns)
