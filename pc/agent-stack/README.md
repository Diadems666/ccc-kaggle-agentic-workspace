
## Research tools + OpenHands pre-config

- `ccc-tools` (compose service, 127.0.0.1:8775) is an MCP server: `web_search` (SearXNG at host :8888), `fetch_url`, `search_and_read`.
- After `start-agent-stack.ps1` run `configure-openhands.ps1` to set the LLM (openai/ccc-local via LiteLLM) and register the MCP server in OpenHands (idempotent).

- Filesystem: `fs_list/read/write/edit/mkdir/move/search` tools are sandboxed to `C:\Users\spent\ccc-workspace` (override with WORKSPACE_DIR in .env). The same folder is mounted at /workspace in the OpenHands sandbox, which also has its built-in terminal and file editor.


## Agent capabilities

- `ccc-tools` MCP (127.0.0.1:8775): `run_command` (python, node, pytest, ruff, mypy, git, rg, gcc), `fs_*`, `memory_*` (SQLite FTS5, persistent volume `ccc-memory`), `web_search`/`fetch_url`/`search_and_read`. Context7 is registered for live library docs.
- `python configure_openhands.py` sets LLM, system prompt (`tools/system_prompt.md`), MCP servers, 250-iteration limit.
- `python setup_public_access.py --key-file <CF key> --email <you>` creates the tunnel + Access policy for https://agent.tropicops.cloud (`cloudflared` compose service uses CLOUDFLARE_TUNNEL_TOKEN from .env).
- llama-server now uses --cache-reuse 256, -b 2048 -ub 1024, --metrics (applies on the next worker start).

