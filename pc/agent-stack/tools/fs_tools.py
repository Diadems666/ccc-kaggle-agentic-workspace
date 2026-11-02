"""Sandboxed filesystem tools for the CCC MCP server (rooted at WORKSPACE_ROOT)."""
from __future__ import annotations

import fnmatch
import os
import re
from pathlib import Path
from typing import Any

from fastmcp import FastMCP

ROOT = Path(os.environ.get("WORKSPACE_ROOT", "/workspace")).resolve()
MAX_READ = int(os.environ.get("FS_MAX_READ", "60000"))
SKIP_DIRS = {".git", "node_modules", "__pycache__", ".venv", "venv", "dist", ".next"}


def _safe(rel: str) -> Path:
    """Resolve rel inside ROOT or raise ValueError."""
    p = (ROOT / rel.lstrip("/\\")).resolve()
    if p != ROOT and ROOT not in p.parents:
        raise ValueError(f"path escapes workspace: {rel}")
    return p


def register(mcp: FastMCP) -> None:
    """Attach filesystem tools to the given server."""

    @mcp.tool
    def fs_list(path: str = ".", recursive: bool = False, max_entries: int = 300) -> list[str]:
        """List files/dirs under a workspace path (dirs end with /)."""
        base = _safe(path)
        out: list[str] = []
        for dirpath, dirs, files in os.walk(base):
            dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)
            rel = Path(dirpath).relative_to(ROOT).as_posix()
            prefix = "" if rel == "." else rel + "/"
            out += [f"{prefix}{d}/" for d in dirs] + [f"{prefix}{f}" for f in sorted(files)]
            if len(out) >= max_entries:
                return out[:max_entries] + ["...truncated"]
            if not recursive:
                break
        return out

    @mcp.tool
    def fs_read(path: str, start_line: int = 1, end_line: int = 0) -> str:
        """Read a text file (optionally a 1-based line range) with line numbers."""
        lines = _safe(path).read_text(encoding="utf-8", errors="replace").splitlines()
        end = end_line or len(lines)
        text = "\n".join(f"{i}\t{l}" for i, l in enumerate(lines[start_line - 1:end], start_line))
        return text[:MAX_READ] + ("\n...truncated" if len(text) > MAX_READ else "")

    @mcp.tool
    def fs_write(path: str, content: str) -> str:
        """Create or overwrite a file (parent dirs are created)."""
        p = _safe(path)
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content, encoding="utf-8")
        return f"wrote {len(content)} chars to {path}"

    @mcp.tool
    def fs_edit(path: str, old: str, new: str) -> str:
        """Replace exactly one occurrence of `old` with `new` in a file."""
        p = _safe(path)
        text = p.read_text(encoding="utf-8")
        n = text.count(old)
        if n != 1:
            return f"ERROR: expected 1 match, found {n}"
        p.write_text(text.replace(old, new), encoding="utf-8")
        return "edited"

    @mcp.tool
    def fs_mkdir(path: str) -> str:
        """Create a directory (and parents)."""
        _safe(path).mkdir(parents=True, exist_ok=True)
        return "ok"

    @mcp.tool
    def fs_move(src: str, dst: str) -> str:
        """Move/rename a file or directory inside the workspace (no overwrite)."""
        s, d = _safe(src), _safe(dst)
        if d.exists():
            return "ERROR: destination exists"
        d.parent.mkdir(parents=True, exist_ok=True)
        s.rename(d)
        return "moved"

    @mcp.tool
    def fs_search(pattern: str, path: str = ".", glob: str = "*", max_results: int = 100) -> list[dict[str, Any]]:
        """Regex-search file contents under path, filtering filenames by glob."""
        rx = re.compile(pattern)
        hits: list[dict[str, Any]] = []
        for dirpath, dirs, files in os.walk(_safe(path)):
            dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
            for f in files:
                if not fnmatch.fnmatch(f, glob):
                    continue
                fp = Path(dirpath) / f
                try:
                    for i, line in enumerate(fp.read_text(encoding="utf-8").splitlines(), 1):
                        if rx.search(line):
                            hits.append({"file": str(fp.relative_to(ROOT)).replace("\\", "/"), "line": i, "text": line[:200]})
                            if len(hits) >= max_results:
                                return hits
                except (UnicodeDecodeError, OSError):
                    continue
        return hits
