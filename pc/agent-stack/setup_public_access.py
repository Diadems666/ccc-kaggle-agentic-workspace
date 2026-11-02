#!/usr/bin/env python3
"""Expose OpenHands at https://<host> via a Cloudflare Tunnel gated by Cloudflare Access.

Creates/updates (idempotent): named tunnel, tunnel ingress, proxied CNAME, Access app
with an email-allow policy. Writes CLOUDFLARE_TUNNEL_TOKEN into .env (never printed).

Usage:
  python setup_public_access.py --key-file <file with global API key> \
      --email joe.venner@hotmail.com [--host agent.tropicops.cloud]
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import re
import urllib.request
from pathlib import Path

ACCOUNT = "b1999cffc7b9c0a1e68a31b9d71462a1"
ZONE = "aa8be6541f477fbba8210770da402e4e"
API = "https://api.cloudflare.com/client/v4"
HERE = Path(__file__).resolve().parent


class CF:
    """Minimal Cloudflare API client (global key auth)."""

    def __init__(self, email: str, key: str) -> None:
        self.h = {"X-Auth-Email": email, "X-Auth-Key": key, "Content-Type": "application/json"}

    def call(self, method: str, path: str, body: dict | None = None) -> dict:
        req = urllib.request.Request(
            API + path, method=method, headers=self.h,
            data=json.dumps(body).encode() if body is not None else None)
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                out = json.load(r)
        except urllib.error.HTTPError as exc:
            raise SystemExit(f"{method} {path} -> {exc.code}: {exc.read().decode()[:300]}")
        if not out.get("success"):
            raise SystemExit(f"{method} {path} failed: {out.get('errors')}")
        return out


def main() -> None:
    """Create tunnel, DNS and Access policy."""
    ap = argparse.ArgumentParser()
    ap.add_argument("--key-file", required=True)
    ap.add_argument("--cf-email", default="joe.venner@hotmail.com")
    ap.add_argument("--email", required=True, help="address allowed through Access")
    ap.add_argument("--host", default="agent.tropicops.cloud")
    ap.add_argument("--name", default="ccc-agent")
    ap.add_argument("--origin", default="http://openhands:3000")
    a = ap.parse_args()
    key = re.search(r"[0-9a-f]{37}", Path(a.key_file).read_text()).group(0)
    cf = CF(a.cf_email, key)

    tunnels = cf.call("GET", f"/accounts/{ACCOUNT}/cfd_tunnel?name={a.name}&is_deleted=false")["result"]
    if tunnels:
        tid = tunnels[0]["id"]
    else:
        secret = base64.b64encode(os.urandom(32)).decode()
        tid = cf.call("POST", f"/accounts/{ACCOUNT}/cfd_tunnel",
                      {"name": a.name, "tunnel_secret": secret, "config_src": "cloudflare"})["result"]["id"]
    cf.call("PUT", f"/accounts/{ACCOUNT}/cfd_tunnel/{tid}/configurations", {"config": {"ingress": [
        {"hostname": a.host, "service": a.origin, "originRequest": {"noTLSVerify": True}},
        {"service": "http_status:404"}]}})

    target = f"{tid}.cfargotunnel.com"
    recs = cf.call("GET", f"/zones/{ZONE}/dns_records?name={a.host}")["result"]
    rec = {"type": "CNAME", "name": a.host, "content": target, "proxied": True}
    if recs:
        cf.call("PUT", f"/zones/{ZONE}/dns_records/{recs[0]['id']}", rec)
    else:
        cf.call("POST", f"/zones/{ZONE}/dns_records", rec)

    apps = cf.call("GET", f"/accounts/{ACCOUNT}/access/apps")["result"]
    app = next((x for x in apps if x.get("domain") == a.host), None)
    app_body = {"name": "CCC Agent (OpenHands)", "domain": a.host, "type": "self_hosted",
                "session_duration": "24h", "app_launcher_visible": True}
    if app:
        app_id = app["id"]
        cf.call("PUT", f"/accounts/{ACCOUNT}/access/apps/{app_id}", app_body)
    else:
        app_id = cf.call("POST", f"/accounts/{ACCOUNT}/access/apps", app_body)["result"]["id"]
    pol = {"name": "owner only", "decision": "allow", "include": [{"email": {"email": a.email}}]}
    pols = cf.call("GET", f"/accounts/{ACCOUNT}/access/apps/{app_id}/policies")["result"]
    if pols:
        cf.call("PUT", f"/accounts/{ACCOUNT}/access/apps/{app_id}/policies/{pols[0]['id']}", pol)
    else:
        cf.call("POST", f"/accounts/{ACCOUNT}/access/apps/{app_id}/policies", pol)

    token = cf.call("GET", f"/accounts/{ACCOUNT}/cfd_tunnel/{tid}/token")["result"]
    env = HERE / ".env"
    text = env.read_text() if env.exists() else ""
    line = f"CLOUDFLARE_TUNNEL_TOKEN={token}"
    text = re.sub(r"^CLOUDFLARE_TUNNEL_TOKEN=.*$", line, text, flags=re.M) if "CLOUDFLARE_TUNNEL_TOKEN=" in text else text.rstrip("\n") + "\n" + line + "\n"
    env.write_text(text)
    print(f"tunnel {tid} | https://{a.host} -> {a.origin} | Access: {a.email} only | token saved to .env")


if __name__ == "__main__":
    main()
