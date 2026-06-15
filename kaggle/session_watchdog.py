#!/usr/bin/env python3
"""
Kaggle session watchdog.

Monitors remaining Kaggle session time and saves workspace state
before the 12-hour session limit expires.

Usage:
    python3 session_watchdog.py [--check-interval 300] [--save-at 30] [--close-at 10]
"""

import argparse
import datetime
import json
import os
import subprocess
import sys
import time
import urllib.request
from pathlib import Path


def parse_args():
    p = argparse.ArgumentParser(description="Kaggle session watchdog")
    p.add_argument("--check-interval", type=int, default=300,
                   help="Seconds between checks (default: 300)")
    p.add_argument("--save-at", type=int, default=30,
                   help="Save state when N minutes remaining (default: 30)")
    p.add_argument("--close-at", type=int, default=10,
                   help="Close tunnel when N minutes remaining (default: 10)")
    return p.parse_args()


def get_remaining_minutes() -> float:
    """
    Estimate remaining Kaggle session time.
    Kaggle sessions last 12 hours from start. We estimate based on process uptime.
    Returns minutes remaining.
    """
    session_limit_hours = 12
    try:
        # Get uptime of the current process's parent (the notebook kernel)
        uptime_output = subprocess.check_output(
            ["ps", "-o", "etimes=", "-p", str(os.getppid())],
            stderr=subprocess.DEVNULL, text=True
        ).strip()
        elapsed_seconds = int(uptime_output)
    except Exception:
        # Fallback: use system uptime
        with open("/proc/uptime") as f:
            elapsed_seconds = float(f.read().split()[0])

    elapsed_minutes = elapsed_seconds / 60
    remaining_minutes = (session_limit_hours * 60) - elapsed_minutes
    return max(0, remaining_minutes)


def send_alert(message: str):
    """Send alert via webhook if configured."""
    webhook_url = os.environ.get("ALERT_WEBHOOK_URL", "")
    ntfy_topic = os.environ.get("NTFY_TOPIC", "")

    if ntfy_topic:
        webhook_url = f"https://ntfy.sh/{ntfy_topic}"

    if not webhook_url:
        return

    payload = json.dumps({"text": message, "message": message}).encode()
    try:
        req = urllib.request.Request(
            webhook_url,
            data=payload,
            headers={"Content-Type": "application/json"},
            method="POST"
        )
        with urllib.request.urlopen(req, timeout=10):
            pass
        print(f"  [alert] Sent to {webhook_url}")
    except Exception as e:
        print(f"  [alert] Failed to send alert: {e}")


def save_state():
    """Save workspace state to GitHub."""
    print("  [watchdog] Saving state...")
    ws_dir = os.environ.get("WORKSPACE_DIR", "/tmp/ws")
    script = Path(ws_dir) / "kaggle" / "save_state.sh"
    if script.exists():
        result = subprocess.run(["bash", str(script)], capture_output=True, text=True)
        if result.returncode == 0:
            print("  [watchdog] State saved successfully.")
        else:
            print(f"  [watchdog] Save failed: {result.stderr}")
    else:
        print(f"  [watchdog] save_state.sh not found at {script}")


def close_tunnel():
    """Gracefully close the SSH reverse tunnel."""
    print("  [watchdog] Closing SSH tunnel...")
    result = subprocess.run(
        ["pkill", "-f", "ssh.*-R.*8081"],
        capture_output=True
    )
    if result.returncode == 0:
        print("  [watchdog] Tunnel closed.")
    else:
        print("  [watchdog] No tunnel process found (already closed?).")


def main():
    args = parse_args()
    session_start = datetime.datetime.now()
    saved = False
    closed = False

    print("=== Kaggle Session Watchdog ===")
    print(f"Session start:      {session_start.strftime('%H:%M:%S')}")
    print(f"Check interval:     {args.check_interval}s")
    print(f"Save state at:      {args.save_at} minutes remaining")
    print(f"Close tunnel at:    {args.close_at} minutes remaining")
    print(f"Alert webhook:      {os.environ.get('ALERT_WEBHOOK_URL') or os.environ.get('NTFY_TOPIC') or 'not configured'}")
    print("")

    while True:
        remaining = get_remaining_minutes()
        now = datetime.datetime.now().strftime("%H:%M:%S")
        print(f"[{now}] Session time remaining: {remaining:.0f} minutes")

        if not saved and remaining <= args.save_at:
            msg = f"Kaggle GPU session: {remaining:.0f} min remaining — saving state"
            print(f"  [watchdog] {msg}")
            send_alert(msg)
            save_state()
            saved = True

        if not closed and remaining <= args.close_at:
            msg = f"Kaggle GPU session: {remaining:.0f} min remaining — closing tunnel"
            print(f"  [watchdog] {msg}")
            send_alert(msg)
            close_tunnel()
            closed = True

        if remaining <= 1:
            print("[watchdog] Session ending. Exiting watchdog.")
            break

        time.sleep(args.check_interval)


if __name__ == "__main__":
    main()
