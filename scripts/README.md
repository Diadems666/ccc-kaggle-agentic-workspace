# Scripts

VPS utility scripts for managing the agentic workspace.

## Scripts

| Script | Purpose |
|--------|---------|
| `healthcheck.sh` | Check all services and connectivity |
| `check_gpu_backend.sh` | Verify Kaggle GPU tunnel and LLM server |
| `start_agent_session.sh` | Start a new coding session |
| `stop_agent_session.sh` | End a session cleanly |
| `switch_provider.sh` | Switch LLM provider (anthropic/openai/local) |
| `sync_repo.sh` | Pull latest workspace scripts from GitHub |
| `backup_workspace.sh` | Create a timestamped backup of the workspace |

## Usage

All scripts are designed to be run from the VPS as the `deploy` user:

```bash
bash /opt/coding-workspace/scripts/healthcheck.sh
```

Or add to PATH for convenience:

```bash
export PATH="/opt/coding-workspace/scripts:$PATH"
```

## Environment

Scripts source `/opt/coding-workspace/.env` for configuration. Make sure this file exists and is populated before running scripts.
