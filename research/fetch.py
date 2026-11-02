#!/usr/bin/env python3
"""Fetch a web page and print its readable text (title, headings, body).

Standard library only. Deliberately simple: it strips scripts, styles and page chrome,
keeps headings/paragraphs/list items/code, and truncates to ``--max-chars`` so a small
local model does not drown in a 200 KB page. PDFs and JavaScript-only pages are not
supported; the tool says so instead of returning garbage.

Usage:
    python research/fetch.py https://example.com/article --max-chars 6000
"""

from __future__ import annotations

import argparse
import re
import sys
import urllib.error
import urllib.request
from html.parser import HTMLParser
from typing import Optional

USER_AGENT = "Mozilla/5.0 (compatible; ccc-research/1.0; +self-hosted agent)"
MAX_BYTES = 2_000_000
SKIP_TAGS = {"script", "style", "noscript", "svg", "nav", "header", "footer", "aside", "form", "iframe"}
BLOCK_TAGS = {"p", "div", "section", "article", "li", "tr", "br", "pre", "blockquote", "table", "ul", "ol"}
HEADING_TAGS = {"h1", "h2", "h3", "h4"}


class TextExtractor(HTMLParser):
    """Collect readable text from HTML, skipping page chrome."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.title = ""
        self._in_title = False
        self._skip_depth = 0
        self._heading: Optional[str] = None
        self._parts: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, Optional[str]]]) -> None:
        if tag == "title":
            self._in_title = True
        if tag in SKIP_TAGS:
            self._skip_depth += 1
        elif tag in HEADING_TAGS:
            self._parts.append("\n\n" + "#" * int(tag[1]) + " ")
        elif tag == "li":
            self._parts.append("\n- ")
        elif tag in BLOCK_TAGS:
            self._parts.append("\n")

    def handle_endtag(self, tag: str) -> None:
        if tag == "title":
            self._in_title = False
        if tag in SKIP_TAGS and self._skip_depth:
            self._skip_depth -= 1
        elif tag in HEADING_TAGS or tag in BLOCK_TAGS:
            self._parts.append("\n")

    def handle_data(self, data: str) -> None:
        if self._in_title:
            self.title += data
        elif not self._skip_depth:
            self._parts.append(data)

    def text(self) -> str:
        """Return the extracted text with collapsed whitespace."""
        raw = "".join(self._parts)
        raw = re.sub(r"[ \t\r\f\v]+", " ", raw)
        raw = re.sub(r" ?\n ?", "\n", raw)
        raw = re.sub(r"\n{3,}", "\n\n", raw)
        return raw.strip()


def extract_text(html: str) -> tuple[str, str]:
    """Return ``(title, text)`` extracted from an HTML document."""
    parser = TextExtractor()
    parser.feed(html)
    return " ".join(parser.title.split()), parser.text()


def fetch(url: str, timeout: int = 25) -> tuple[str, str, str]:
    """Download ``url`` and return ``(content_type, charset, body_text)``.

    Raises:
        RuntimeError: On network errors or unsupported content.
    """
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "text/html,text/plain,*/*;q=0.5"})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:  # noqa: S310 - http(s) only, checked below
            content_type = response.headers.get_content_type()
            charset = response.headers.get_content_charset() or "utf-8"
            body = response.read(MAX_BYTES)
    except urllib.error.HTTPError as exc:
        raise RuntimeError(f"HTTP {exc.code} fetching {url}") from exc
    except (urllib.error.URLError, TimeoutError) as exc:
        raise RuntimeError(f"Could not fetch {url}: {exc}") from exc
    if content_type == "application/pdf":
        raise RuntimeError("PDF content is not supported by fetch.py; download it and use pdftotext.")
    return content_type, charset, body.decode(charset, errors="replace")


def render(url: str, max_chars: int) -> str:
    """Fetch ``url`` and return a trimmed, Markdown-ish rendering of its text."""
    if not re.match(r"^https?://", url, flags=re.IGNORECASE):
        raise RuntimeError("Only http(s) URLs are allowed.")
    content_type, _, body = fetch(url)
    if content_type in {"text/html", "application/xhtml+xml"}:
        title, text = extract_text(body)
    else:
        title, text = "", body.strip()
    if len(text) < 200 and content_type == "text/html":
        text += "\n\n[note: very little text extracted; the page may need JavaScript]"
    clipped = text[:max_chars]
    suffix = f"\n\n[truncated: showing {len(clipped)} of {len(text)} chars]" if len(text) > max_chars else ""
    header = f"# {title}\nSource: {url}\n\n" if title else f"Source: {url}\n\n"
    return header + clipped + suffix


def main(argv: Optional[list[str]] = None) -> int:
    """CLI entry point."""
    parser = argparse.ArgumentParser(description="Fetch a web page as readable text.")
    parser.add_argument("url")
    parser.add_argument("--max-chars", type=int, default=6000)
    args = parser.parse_args(argv)
    try:
        print(render(args.url, args.max_chars))
    except RuntimeError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
