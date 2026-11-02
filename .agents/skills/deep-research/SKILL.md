---
name: deep-research
description: Multi-source web research with citations using the self-hosted SearXNG instance. Use when asked to research, compare, investigate, find out, or write a sourced report on any topic that needs current information.
triggers:
  - deep research
  - research this
  - sourced report
---

# Deep research protocol

You are running on a modest local model. Compensate with discipline: write down what you
learn as you go, keep each step small, and never cite a page you did not actually read.

## Tools

Search (SearXNG, no API key, no rate limit worth worrying about):

```bash
python research/searx.py "query" -n 8                # Markdown list
python research/searx.py "query" -t month --json     # recent results, JSON
```

Read a page as plain text (truncated so it fits your context):

```bash
python research/fetch.py "https://example.com/page" --max-chars 6000
```

If `research/` is not in the current repo, use the raw API instead:

```bash
curl -s "http://host.docker.internal:8888/search?q=URL_ENCODED_QUERY&format=json" | head -c 6000
```

## Procedure

1. **Plan.** Write `research/<topic-slug>/plan.md` with the question, 3-6 sub-questions,
   and what a good answer must contain. Keep it under 30 lines.
2. **Search each sub-question.** Run 1-3 differently-worded queries per sub-question.
   Prefer primary sources (official docs, standards, filings, papers, vendor pages) over
   blog summaries. Use `-t month` or `-t year` when recency matters.
3. **Read, don't skim.** Fetch the 2-4 best URLs per sub-question. After EACH page,
   append to `research/<topic-slug>/notes.md`:
   `- [claim in your own words] (source: URL, date if shown)`
   If a page is empty, paywalled, or needs JavaScript, note it and move on.
4. **Cross-check.** Any number, date, price, or "X is the best" claim needs two independent
   sources, or must be labelled "single source". Note disagreements explicitly.
5. **Write the report** to `research/<topic-slug>/report.md`:
   - Short answer first (3-5 sentences).
   - Findings grouped by sub-question, every factual sentence followed by `[n]`.
   - A "Confidence and gaps" section: what is uncertain, what you could not verify.
   - A numbered Sources list (title, URL, date accessed).
6. **Check yourself.** Re-read the report against `notes.md`. Delete or soften any claim
   that is not in your notes. Then summarise the result in chat in under 150 words and
   point to the report file.

## Rules

- Never invent a URL, quote, statistic, or version number. If you did not read it, you do
  not know it.
- Today's date matters: say "as of <date>" for anything that changes (prices, versions, laws).
- Do not paste whole pages into notes; extract only what you need.
- If SearXNG returns errors or nothing, say so and stop rather than answering from memory.
