"""Tests for the Kaggle profile logic and the research tools (no network, no GPU)."""

from __future__ import annotations

import importlib.util
import json
import sys
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]


def load(name: str, relative: str):
    """Import a script by path (the repo directories are not Python packages)."""
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


qs = load("quick_start_v2", "kaggle/quick_start_v2.py")
searx = load("searx", "research/searx.py")
fetch = load("fetch_page", "research/fetch.py")

T4 = qs.Gpu("Tesla T4", 15360)


# ─── choose_profile ───────────────────────────────────────────────────────────


def test_dual_t4_defaults_to_q4km_at_64k():
    profile = qs.choose_profile([T4, T4])
    assert profile.quant == "Q4_K_M"
    assert profile.context == 65536
    assert profile.filename == "Qwen3.8-27B-UD-Q4_K_M.gguf"
    assert profile.est_vram_gb < 27


def test_dual_t4_can_take_q5_when_requested():
    profile = qs.choose_profile([T4, T4], quant="Q5_K_M")
    assert profile.quant == "Q5_K_M"


def test_oversized_context_steps_down_instead_of_failing():
    profile = qs.choose_profile([T4, T4], quant="Q6_K", context=131072, kv_type="f16")
    assert profile.context < 131072


def test_forced_quant_that_cannot_fit_raises():
    with pytest.raises(ValueError, match="Nothing fits"):
        qs.choose_profile([T4], quant="Q6_K")


def test_single_t4_falls_back_to_small_quant():
    profile = qs.choose_profile([T4])
    assert profile.quant in {"IQ3_XXS", "IQ2_S"}
    assert profile.context <= 32768


def test_no_gpu_is_an_error():
    with pytest.raises(ValueError, match="No GPU"):
        qs.choose_profile([])


def test_unknown_quant_is_an_error():
    with pytest.raises(ValueError, match="Unknown quant"):
        qs.choose_profile([T4, T4], quant="Q9_Z")


def test_kv_estimate_matches_architecture():
    # 16 attention layers x K+V x 4 heads x 256 dim x 2 bytes (f16)
    assert qs.KV_BYTES_PER_TOKEN["f16"] == 65536
    assert qs.KV_BYTES_PER_TOKEN["q8_0"] < qs.KV_BYTES_PER_TOKEN["f16"]


# ─── tunnel key handling ──────────────────────────────────────────────────────


def test_decode_key_accepts_crlf_and_base64():
    pem = "-----BEGIN OPENSSH PRIVATE KEY-----\r\nabc\r\n-----END OPENSSH PRIVATE KEY-----\r\n"
    import base64

    assert qs.decode_tunnel_key(pem) == "-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n-----END OPENSSH PRIVATE KEY-----\n"
    assert qs.decode_tunnel_key(base64.b64encode(pem.encode()).decode()).startswith("-----BEGIN")


def test_decode_key_rejects_garbage():
    import base64

    with pytest.raises(ValueError):
        qs.decode_tunnel_key(base64.b64encode(b"hello world").decode())


# ─── research tools ───────────────────────────────────────────────────────────


def test_dedupe_merges_same_page_variants():
    results = [
        {"title": "A", "url": "https://www.example.com/post/", "content": "x  y"},
        {"title": "A dup", "url": "https://example.com/post", "content": "z"},
        {"title": "B", "url": "https://other.org/", "content": ""},
        {"title": "no url", "url": ""},
    ]
    cleaned = searx.dedupe_results(results, limit=10)
    assert [r["title"] for r in cleaned] == ["A", "B"]
    assert cleaned[0]["snippet"] == "x y"


def test_build_url_encodes_query():
    url = searx.build_url("http://h:8888/", "a b&c", "general", "week", 2)
    assert url.startswith("http://h:8888/search?")
    assert "q=a+b%26c" in url and "time_range=week" in url and "pageno=2" in url


def test_extract_text_strips_chrome():
    html = (
        "<html><head><title> My  Page </title><style>x{}</style></head><body>"
        "<nav>MENU</nav><h1>Heading</h1><p>Hello <b>world</b>.</p><ul><li>one</li><li>two</li></ul>"
        "<script>evil()</script><footer>FOOT</footer></body></html>"
    )
    title, text = fetch.extract_text(html)
    assert title == "My Page"
    assert "# Heading" in text and "Hello world." in text and "- one" in text
    assert "MENU" not in text and "evil" not in text and "FOOT" not in text


class _Handler(BaseHTTPRequestHandler):
    def do_GET(self):  # noqa: N802 - http.server API
        if self.path.startswith("/search"):
            body = json.dumps({"results": [{"title": "T", "url": "https://e.com/1", "content": "c"}]}).encode()
            ctype = "application/json"
        elif self.path == "/page":
            body = ("<html><title>P</title><body><p>" + "word " * 100 + "</p></body></html>").encode()
            ctype = "text/html; charset=utf-8"
        else:
            self.send_response(404)
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):  # silence test output
        pass


@pytest.fixture()
def server():
    httpd = HTTPServer(("127.0.0.1", 0), _Handler)
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    yield f"http://127.0.0.1:{httpd.server_port}"
    httpd.shutdown()


def test_search_against_mock_searxng(server):
    results = searx.search("anything", base=server, limit=5)
    assert results[0]["url"] == "https://e.com/1"


def test_search_unreachable_raises_runtime_error():
    with pytest.raises(RuntimeError):
        searx.search("x", base="http://127.0.0.1:9", timeout=1)


def test_render_truncates_and_labels(server):
    out = fetch.render(f"{server}/page", max_chars=50)
    assert out.startswith("# P\nSource:")
    assert "[truncated:" in out


def test_render_rejects_non_http():
    with pytest.raises(RuntimeError, match="http"):
        fetch.render("file:///etc/passwd", 100)


def test_http_404_is_reported(server):
    with pytest.raises(RuntimeError, match="404"):
        fetch.render(f"{server}/missing", 100)
