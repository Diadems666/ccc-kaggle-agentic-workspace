
## Research tools + OpenHands pre-config

- `ccc-tools` (compose service, 127.0.0.1:8775) is an MCP server: `web_search` (SearXNG at host :8888), `fetch_url`, `search_and_read`.
- After `start-agent-stack.ps1` run `configure-openhands.ps1` to set the LLM (openai/ccc-local via LiteLLM) and register the MCP server in OpenHands (idempotent).

- Filesystem: `fs_list/read/write/edit/mkdir/move/search` tools are sandboxed to `C:\Users\spent\ccc-workspace` (override with WORKSPACE_DIR in .env). The same folder is mounted at /workspace in the OpenHands sandbox, which also has its built-in terminal and file editor.

