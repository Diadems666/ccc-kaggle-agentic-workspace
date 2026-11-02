"""Persistent long-term memory (SQLite + FTS5) exposed as MCP tools."""
from __future__ import annotations

import os
import sqlite3
import time
from pathlib import Path
from typing import Any

from fastmcp import FastMCP

DB_PATH = Path(os.environ.get("MEMORY_DB", "/data/memory.db"))


def _db() -> sqlite3.Connection:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS memory(
            id INTEGER PRIMARY KEY, project TEXT NOT NULL DEFAULT 'general',
            kind TEXT NOT NULL DEFAULT 'note', content TEXT NOT NULL,
            tags TEXT NOT NULL DEFAULT '', created REAL NOT NULL);
        CREATE VIRTUAL TABLE IF NOT EXISTS memory_fts USING fts5(
            content, tags, project, content='memory', content_rowid='id');
        CREATE TRIGGER IF NOT EXISTS m_ai AFTER INSERT ON memory BEGIN
            INSERT INTO memory_fts(rowid, content, tags, project)
            VALUES (new.id, new.content, new.tags, new.project); END;
        CREATE TRIGGER IF NOT EXISTS m_ad AFTER DELETE ON memory BEGIN
            INSERT INTO memory_fts(memory_fts, rowid, content, tags, project)
            VALUES ('delete', old.id, old.content, old.tags, old.project); END;
        """
    )
    return conn


def _row(r: sqlite3.Row) -> dict[str, Any]:
    return {k: r[k] for k in ("id", "project", "kind", "content", "tags")} | {
        "created": time.strftime("%Y-%m-%d %H:%M", time.localtime(r["created"]))
    }


def register(mcp: FastMCP) -> None:
    """Attach memory tools to the server."""

    @mcp.tool
    def memory_save(content: str, project: str = "general", kind: str = "note", tags: str = "") -> int:
        """Save a durable fact. kind: preference | decision | lesson | project | todo | note.

        Write short, self-contained statements. Returns the memory id.
        """
        with _db() as c:
            return c.execute(
                "INSERT INTO memory(project, kind, content, tags, created) VALUES (?,?,?,?,?)",
                (project, kind, content, tags, time.time()),
            ).lastrowid

    @mcp.tool
    def memory_search(query: str, project: str = "", limit: int = 10) -> list[dict[str, Any]]:
        """Full-text search memories (optionally within one project)."""
        terms = " OR ".join(f'"{t}"' for t in query.replace('"', " ").split() if t)
        if not terms:
            return []
        sql = ("SELECT m.* FROM memory_fts f JOIN memory m ON m.id=f.rowid WHERE memory_fts MATCH ?"
               + (" AND m.project=?" if project else "") + " ORDER BY rank LIMIT ?")
        args: list[Any] = [terms] + ([project] if project else []) + [limit]
        with _db() as c:
            return [_row(r) for r in c.execute(sql, args)]

    @mcp.tool
    def memory_recent(project: str = "", limit: int = 15) -> list[dict[str, Any]]:
        """Most recent memories, newest first (optionally for one project)."""
        sql = "SELECT * FROM memory" + (" WHERE project=?" if project else "") + " ORDER BY created DESC LIMIT ?"
        args: list[Any] = ([project] if project else []) + [limit]
        with _db() as c:
            return [_row(r) for r in c.execute(sql, args)]

    @mcp.tool
    def memory_delete(memory_id: int) -> str:
        """Delete a memory by id (use when a fact is wrong or obsolete)."""
        with _db() as c:
            c.execute("DELETE FROM memory WHERE id=?", (memory_id,))
        return "deleted"
