#!/usr/bin/env python3
"""Query the self-hosted SearXNG instance and print compact, de-duplicated results.

Standard library only, so it runs unchanged inside OpenHands sandbox containers.

Usage:
    python research/searx.py "rust async runtime comparison" -n 8
    python research/searx.py "openhands release notes" --time-range month --json

Environment:
    SEARXNG_URL   Base URL of SearXNG (default http://host.docker.internal:8888)
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from typing import Any, Optional

DEFAULT_URL = "http://host.docker.internal:8888"
USER_AGENT = "ccc-research/1.0 (+self-hosted agent)"


def build_url(base: str, query: str, categories: str, time_range: Optional[str], page: int) -> str:
    """Build the SearXNG JSON search URL.

    Args:
        base: SearXNG base URL, with or without a trailing slash.
        query: Search query text.
        categories: Comma-separated SearXNG categories (e.g. ``general,science``).
        time_range: Optional ``day``, ``week``, ``month`` or ``year``.
        page: 1-based result page.

    Returns:
        A fully encoded URL.
    """
    params: dict[str, Any] = {"q": query, "format": "json", "categories": categories, "pageno": page}
    if time_range:
        params["time_range"] = time_range
    return f"{base.rstrip('/')}/search?{urllib.parse.urlencode(params)}"


def normalise_url(url: str) -> str:
    """Return a canonical form of ``url`` used to detect duplicates."""
    parts = urllib.parse.urlsplit(url)
    host = parts.netloc.lower().removeprefix("www.")
    return f"{host}{parts.path.rstrip('/')}"


def dedupe_results(results: list[dict[str, Any]], limit: int) -> list[dict[str, Any]]:
    """Drop duplicate URLs and trim to ``limit`` results with only useful fields.

    Args:
        results: Raw SearXNG ``results`` list.
        limit: Maximum number of results to keep.

    Returns:
        Dicts with ``title``, ``url``, ``snippet``, ``engines`` and ``date``.
    """
    seen: set[str] = set()
    cleaned: list[dict[str, Any]] = []
    for item in results:
        url = item.get("url") or ""
        if not url:
            continue
        key = normalise_url(url)
        if key in seen:
            continue
        seen.add(key)
        cleaned.append(
            {
                "title": (item.get("title") or "").strip(),
                "url": url,
                "snippet": " ".join((item.get("content") or "").split()),
                "engines": item.get("engines") or [],
                "date": item.get("publishedDate") or "",
            }
        )
        if len(cleaned) >= limit:
            break
    return cleaned


def search(
    query: str,
    base: str = DEFAULT_URL,
    limit: int = 8,
    categories: str = "general",
    time_range: Optional[str] = None,
    page: int = 1,
    timeout: int = 20,
) -> list[dict[str, Any]]:
    """Run a search and return cleaned results.

    Raises:
        RuntimeError: If SearXNG is unreachable or returns something that is not JSON.
    """
    url = build_url(base, query, categories, time_range, page)
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:  # noqa: S310 - internal URL
            payload = json.loads(response.read().decode("utf-8", errors="replace"))
    except urllib.error.HTTPError as exc:
        hint = " (is `json` listed under search.formats in SearXNG settings?)" if exc.code == 403 else ""
        raise RuntimeError(f"SearXNG returned HTTP {exc.code}{hint}") from exc
    except (urllib.error.URLError, TimeoutError, ValueError) as exc:
        raise RuntimeError(f"SearXNG request failed: {exc}") from exc
    return dedupe_results(payload.get("results", []), limit)


def format_markdown(results: list[dict[str, Any]]) -> str:
    """Render results as a numbered Markdown list."""
    if not results:
        return "(no results)"
    lines = []
    for index, item in enumerate(results, start=1):
        date = f" ({item['date'][:10]})" if item["date"] else ""
        lines.append(f"{index}. {item['title']}{date}\n   {item['url']}\n   {item['snippet']}")
    return "\n".join(lines)


def main(argv: Optional[list[str]] = None) -> int:
    """CLI entry point."""
    parser = argparse.ArgumentParser(description="Search the self-hosted SearXNG instance.")
    parser.add_argument("query")
    parser.add_argument("-n", "--limit", type=int, default=8)
    parser.add_argument("-c", "--categories", default="general")
    parser.add_argument("-t", "--time-range", choices=["day", "week", "month", "year"])
    parser.add_argument("-p", "--page", type=int, default=1)
    parser.add_argument("--json", action="store_true", help="emit JSON instead of Markdown")
    args = parser.parse_args(argv)

    base = os.environ.get("SEARXNG_URL", DEFAULT_URL)
    try:
        results = search(args.query, base, args.limit, args.categories, args.time_range, args.page)
    except RuntimeError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(results, indent=2) if args.json else format_markdown(results))
    return 0


if __name__ == "__main__":
    sys.exit(main())
