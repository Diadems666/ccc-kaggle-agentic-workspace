"""Command execution inside the workspace (build, run, test, lint, git)."""
from __future__ import annotations

import os
import subprocess

from fastmcp import FastMCP

from fs_tools import ROOT

MAX_OUT = int(os.environ.get("EXEC_MAX_OUT", "20000"))


def register(mcp: FastMCP) -> None:
    """Attach execution tools to the server."""

    @mcp.tool
    def run_command(command: str, cwd: str = ".", timeout: int = 120) -> str:
        """Run a shell command in the workspace and return exit code + output.

        Available: python3, pip, pytest, ruff, mypy, node, npm, git, rg, make, gcc.
        Output is truncated (head and tail kept). Max timeout 600s.
        """
        work = (ROOT / cwd.lstrip("/\\")).resolve()
        if work != ROOT and ROOT not in work.parents:
            return "ERROR: cwd escapes workspace"
        try:
            p = subprocess.run(
                command, shell=True, cwd=work, capture_output=True, text=True,
                timeout=min(timeout, 600), env={**os.environ, "PYTHONUNBUFFERED": "1"},
            )
            out = (p.stdout or "") + (("\n[stderr]\n" + p.stderr) if p.stderr else "")
            code = p.returncode
        except subprocess.TimeoutExpired as exc:
            out = ((exc.stdout or b"").decode(errors="replace") if isinstance(exc.stdout, bytes) else (exc.stdout or ""))
            out += f"\n[timed out after {timeout}s]"
            code = 124
        if len(out) > MAX_OUT:
            half = MAX_OUT // 2
            out = out[:half] + f"\n...[{len(out) - MAX_OUT} chars cut]...\n" + out[-half:]
        return f"exit={code}\n{out}"
