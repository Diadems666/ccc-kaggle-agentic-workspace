#!/usr/bin/env python3
"""Configure OpenHands via its settings API: LLM, system prompt, MCP servers, limits.

Idempotent. Reads LITELLM_MASTER_KEY from .env next to this file.
Usage: python configure_openhands.py [--model ccc-local] [--base http://127.0.0.1:3100]
"""
from __future__ import annotations

import argparse
import json
import re
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent


def master_key() -> str:
    """Return LITELLM_MASTER_KEY from .env."""
    m = re.search(r"^LITELLM_MASTER_KEY=(\S+)", (HERE / ".env").read_text(), re.M)
    if not m:
        raise SystemExit("LITELLM_MASTER_KEY missing in .env")
    return m.group(1)


def call(url: str, body: dict | None = None) -> dict:
    """GET (no body) or POST JSON and return the decoded response."""
    req = urllib.request.Request(
        url, data=json.dumps(body).encode() if body is not None else None,
        headers={"Content-Type": "application/json"}, method="POST" if body is not None else "GET")
    with urllib.request.urlopen(req, timeout=30) as resp:
        raw = resp.read()
    return json.loads(raw) if raw else {}


def main() -> None:
    """Apply the settings and print a summary."""
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="ccc-local")
    ap.add_argument("--base", default="http://127.0.0.1:3100")
    args = ap.parse_args()
    prompt = (HERE / "tools" / "system_prompt.md").read_text(encoding="utf-8")
    payload = {
        "agent_settings_diff": {
            "llm": {
                "model": f"openai/{args.model}",
                "base_url": "http://host.docker.internal:4000",
                "api_key": master_key(),
                "temperature": 0.6,
                "top_p": 0.8,
                "max_input_tokens": 60000,
                "max_output_tokens": 8192,
                "timeout": 900,
                "num_retries": 3,
                "native_tool_calling": True,
                "drop_params": True,
            },
            "agent_context": {"system_message_suffix": prompt},
            "enable_sub_agents": True,
            "tool_concurrency_limit": 3,
            "mcp_config": {"mcpServers": {
                "ccc-tools": {"url": "http://host.docker.internal:8775/mcp", "transport": "streamable-http"},
                "context7": {"url": "https://mcp.context7.com/mcp", "transport": "streamable-http"},
            }},
        },
        "conversation_settings_diff": {"max_iterations": 250, "confirmation_mode": False},
    }
    call(f"{args.base}/api/v1/settings", payload)
    s = call(f"{args.base}/api/v1/settings")["agent_settings"]
    print("model:", s["llm"]["model"], "| max_out:", s["llm"].get("max_output_tokens"))
    print("mcp:", ", ".join(s["mcp_config"]["mcpServers"]))
    print("prompt chars:", len(s["agent_context"].get("system_message_suffix") or ""))


if __name__ == "__main__":
    main()
