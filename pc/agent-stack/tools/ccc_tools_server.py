"""CCC research tools exposed as an MCP server (streamable HTTP).

Gives the OpenHands agent web search (via a local SearXNG), page fetching with
readable-text extraction, and a one-shot search-and-read helper for research.
"""
from __future__ import annotations

import asyncio
import os
from typing import Any

import httpx
import trafilatura
from fastmcp import FastMCP

import fs_tools

SEARXNG_URL: str = os.environ.get("SEARXNG_URL", "http://host.docker.internal:8888")
MAX_CHARS: int = int(os.environ.get("FETCH_MAX_CHARS", "12000"))
USER_AGENT: str = "Mozilla/5.0 (compatible; CCC-Agent/1.0)"

mcp = FastMCP("ccc-research-tools")
fs_tools.register(mcp)


async def _search(query: str, limit: int, categories: str, time_range: str) -> list[dict[str, Any]]:
    """Query SearXNG and return trimmed result dicts."""
    params = {"q": query, "format": "json", "categories": categories}
    if time_range:
        params["time_range"] = time_range
    async with httpx.AsyncClient(timeout=25) as client:
        resp = await client.get(f"{SEARXNG_URL}/search", params=params)
        resp.raise_for_status()
    results = resp.json().get("results", [])[:limit]
    return [
        {"title": r.get("title", ""), "url": r.get("url", ""), "snippet": r.get("content", "")}
        for r in results
    ]


async def _fetch(url: str, max_chars: int) -> str:
    """Download a URL and return readable text, truncated to max_chars."""
    async with httpx.AsyncClient(
        timeout=25, follow_redirects=True, headers={"User-Agent": USER_AGENT}
    ) as client:
        resp = await client.get(url)
        resp.raise_for_status()
    text = trafilatura.extract(resp.text, include_links=False, include_tables=True) or resp.text
    return text[:max_chars]


@mcp.tool
async def web_search(
    query: str, limit: int = 8, categories: str = "general", time_range: str = ""
) -> list[dict[str, Any]]:
    """Search the web via SearXNG.

    Args:
        query: Search query.
        limit: Max results (1-20).
        categories: SearXNG categories, e.g. general, it, science, news.
        time_range: Optional day, week, month or year.
    """
    return await _search(query, max(1, min(limit, 20)), categories, time_range)


@mcp.tool
async def fetch_url(url: str, max_chars: int = MAX_CHARS) -> str:
    """Fetch a web page and return its readable text (truncated)."""
    try:
        return await _fetch(url, max_chars)
    except Exception as exc:  # noqa: BLE001 - report to the agent, not crash
        return f"ERROR fetching {url}: {exc}"


@mcp.tool
async def search_and_read(query: str, pages: int = 3, chars_per_page: int = 5000) -> str:
    """Search, then fetch the top pages in parallel and return their text.

    Use for research: one call gives sourced material to synthesise from.
    """
    hits = await _search(query, max(1, min(pages, 5)), "general", "")
    texts = await asyncio.gather(
        *(_fetch(h["url"], chars_per_page) for h in hits), return_exceptions=True
    )
    parts = []
    for hit, text in zip(hits, texts):
        body = f"(fetch failed: {text})" if isinstance(text, Exception) else text
        parts.append(f"## {hit['title']}\n{hit['url']}\n\n{body}")
    return "\n\n---\n\n".join(parts) or "No results."


if __name__ == "__main__":
    mcp.run(transport="http", host="0.0.0.0", port=int(os.environ.get("PORT", "8765")), path="/mcp")
