"""CCC Kaggle GPU worker v2: Qwen3.8-27B on dual T4 behind a reverse SSH tunnel.

Run it from a Kaggle notebook cell::

    import os, subprocess
    os.environ["VPS_HOST"] = "your.vps.ip"
    if not os.path.exists("/tmp/ws/.git"):
        subprocess.run(["git", "clone", "https://github.com/Diadems666/ccc-kaggle-agentic-workspace", "/tmp/ws"], check=True)
    exec(open("/tmp/ws/kaggle/quick_start_v2.py").read())

Prerequisites (one-time):
  * Notebook secret ``KAGGLE_TUNNEL_KEY`` (restricted tunnel private key; base64 allowed).
  * Optional secret ``LLM_API_KEY`` (shared with the VPS gateway as KAGGLE_LLM_API_KEY).
  * Settings -> Accelerator -> GPU T4 x2, Internet on.
  * Optional: attach the private ``llama-cpp-sm75`` dataset (built by build_llama_cpp.sh)
    and a dataset containing the GGUF to skip the downloads.

Operating rules baked in (see docs/KAGGLE_QWEN38_AGENT.md):
  * Personal / R&D use only. Client work routes to a paid backend via the VPS gateway.
  * The server only listens on 127.0.0.1; the sole way in is the authenticated SSH tunnel.
  * No auto-restart loops and no keep-alive tricks. The worker stops itself after
    SESSION_MAX_HOURS (default 6) so it never runs unattended or burns the weekly quota.
  * Run as "Save & Run All (Commit)" and the whole Kaggle session ends when this script does.
"""

from __future__ import annotations

import base64
import json
import os
import shutil
import signal
import stat
import subprocess
import sys
import tarfile
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from glob import glob
from pathlib import Path
from typing import Optional, Sequence

# ─── Constants ────────────────────────────────────────────────────────────────

REPO_URL = "https://github.com/Diadems666/ccc-kaggle-agentic-workspace"
WORKSPACE_DIR = os.environ.get("WORKSPACE_DIR", "/tmp/ws")
KEY_PATH = "/tmp/kaggle_tunnel_key"
BIN_DIR = Path("/tmp/llama-bin")
MODEL_DIR = os.environ.get("MODEL_DIR", "/tmp/models")
SERVER_LOG = "/tmp/llm_server.log"

HF_REPO = "unsloth/Qwen3.8-27B-GGUF"

# Sizes (GB) of the Unsloth Dynamic GGUF files in HF_REPO, from the repo listing.
QUANT_SIZES_GB: dict[str, float] = {
    "Q6_K": 21.98,
    "Q5_K_M": 19.77,
    "Q4_K_M": 16.46,
    "IQ4_XS": 14.25,
    "Q3_K_XL": 13.15,
    "IQ3_XXS": 10.93,
    "IQ2_S": 8.37,
}
# Quality-descending preference when the caller does not pick a quant.
AUTO_QUANT_ORDER: tuple[str, ...] = ("Q4_K_M", "IQ4_XS", "IQ3_XXS", "IQ2_S")

# Qwen3.8-27B: 64 layers in a 3:1 DeltaNet:attention pattern, so only 16 layers keep a
# KV cache, each with 4 KV heads x head_dim 256. Bytes per token for K+V:
KV_BYTES_PER_TOKEN: dict[str, int] = {
    "f16": 16 * 2 * 4 * 256 * 2,  # 65,536
    "q8_0": int(16 * 2 * 4 * 256 * 34 / 32),  # 34,816
}
# Per-GPU overhead for CUDA context, compute buffers and recurrent (DeltaNet) state.
PER_GPU_OVERHEAD_GB = 1.5
VRAM_USABLE_FRACTION = 0.92


@dataclass(frozen=True)
class Gpu:
    """One visible GPU."""

    name: str
    memory_mb: int


@dataclass(frozen=True)
class Profile:
    """A concrete model/context choice that fits the detected GPUs."""

    quant: str
    filename: str
    context: int
    kv_type: str
    est_vram_gb: float


# ─── Pure logic (unit-tested) ─────────────────────────────────────────────────


def estimate_vram_gb(quant: str, context: int, kv_type: str, gpu_count: int) -> float:
    """Estimate total VRAM needed to serve ``quant`` at ``context`` tokens.

    Args:
        quant: Key of QUANT_SIZES_GB.
        context: Context window in tokens.
        kv_type: ``f16`` or ``q8_0``.
        gpu_count: Number of GPUs the layers are split over.

    Returns:
        Estimated GB of VRAM across all GPUs.
    """
    kv_gb = KV_BYTES_PER_TOKEN[kv_type] * context / 1e9
    return QUANT_SIZES_GB[quant] + kv_gb + PER_GPU_OVERHEAD_GB * gpu_count


def choose_profile(
    gpus: Sequence[Gpu],
    quant: Optional[str] = None,
    context: Optional[int] = None,
    kv_type: str = "q8_0",
) -> Profile:
    """Pick the best model quantisation and context that fit the GPUs.

    Args:
        gpus: Detected GPUs.
        quant: Force a specific quant (must be in QUANT_SIZES_GB). Otherwise auto.
        context: Preferred context window. Defaults to 65,536 (dual) or 32,768 (single).
        kv_type: KV-cache precision.

    Returns:
        The first Profile that fits, preferring higher quality quants and then
        larger contexts.

    Raises:
        ValueError: If no GPU is present, the quant is unknown, or nothing fits.
    """
    if not gpus:
        raise ValueError("No GPU detected. Enable a GPU accelerator in notebook settings.")
    if kv_type not in KV_BYTES_PER_TOKEN:
        raise ValueError(f"Unsupported KV type {kv_type!r}")
    if quant is not None and quant not in QUANT_SIZES_GB:
        raise ValueError(f"Unknown quant {quant!r}. Choose from {sorted(QUANT_SIZES_GB)}")

    total_gb = sum(g.memory_mb for g in gpus) / 1024 * 1.073741824  # MiB -> GB
    budget_gb = total_gb * VRAM_USABLE_FRACTION
    preferred_ctx = context or (65536 if len(gpus) >= 2 else 32768)
    ctx_options = sorted({preferred_ctx, 32768, 16384}, reverse=True)
    ctx_options = [c for c in ctx_options if c <= preferred_ctx]
    quants = [quant] if quant else list(AUTO_QUANT_ORDER)

    for q in quants:
        for ctx in ctx_options:
            need = estimate_vram_gb(q, ctx, kv_type, len(gpus))
            if need <= budget_gb:
                return Profile(q, f"Qwen3.8-27B-UD-{q}.gguf", ctx, kv_type, round(need, 1))
    raise ValueError(
        f"Nothing fits {len(gpus)} GPU(s) with ~{budget_gb:.1f} GB usable VRAM "
        f"(tried {quants} at contexts {ctx_options})."
    )


def decode_tunnel_key(raw: str) -> str:
    """Normalise the tunnel private key from a Kaggle secret.

    Accepts a raw PEM/OpenSSH key or a base64 encoding of one, and strips the
    CRLF line endings that clipboard pastes introduce.

    Args:
        raw: Secret value.

    Returns:
        Key text with LF endings and a trailing newline.

    Raises:
        ValueError: If the result does not look like a private key.
    """
    text = raw.strip()
    if not text.startswith("-----"):
        text = base64.b64decode(text).decode("utf-8")
    text = text.replace("\r\n", "\n").replace("\r", "\n").strip() + "\n"
    if "PRIVATE KEY" not in text.splitlines()[0]:
        raise ValueError("Tunnel secret does not look like a private key.")
    return text


# ─── Side-effecting helpers ───────────────────────────────────────────────────


def step(number: int, message: str) -> None:
    """Print a section banner."""
    print(f"\n{'=' * 60}\n[{number}] {message}\n{'=' * 60}", flush=True)


def notify(message: str) -> None:
    """Send a best-effort push notification (ntfy topic or generic webhook)."""
    topic = os.environ.get("NTFY_TOPIC", "")
    url = f"https://ntfy.sh/{topic}" if topic else os.environ.get("ALERT_WEBHOOK_URL", "")
    if not url:
        return
    try:
        req = urllib.request.Request(url, data=message.encode(), method="POST")
        urllib.request.urlopen(req, timeout=10).close()  # noqa: S310 - fixed https URL
    except Exception as exc:  # noqa: BLE001
        print(f"  (notify failed: {exc})")


def detect_gpus() -> list[Gpu]:
    """Query nvidia-smi for the visible GPUs."""
    try:
        out = subprocess.check_output(
            ["nvidia-smi", "--query-gpu=name,memory.total", "--format=csv,noheader,nounits"],
            text=True,
            stderr=subprocess.DEVNULL,
        )
    except (OSError, subprocess.CalledProcessError):
        return []
    gpus: list[Gpu] = []
    for line in out.strip().splitlines():
        name, _, mem = line.rpartition(",")
        gpus.append(Gpu(name.strip(), int(float(mem.strip()))))
    return gpus


def load_secret(name: str, required: bool = False) -> str:
    """Read a Kaggle notebook secret, falling back to an environment variable."""
    value = ""
    try:
        from kaggle_secrets import UserSecretsClient  # type: ignore[import-not-found]

        value = UserSecretsClient().get_secret(name)
    except Exception:  # noqa: BLE001 - secret missing / not on Kaggle
        value = os.environ.get(name, "")
    if required and not value:
        raise RuntimeError(
            f"{name} secret not found. Add-ons -> Secrets -> enable {name}, then re-run."
        )
    return value


def write_tunnel_key() -> None:
    """Write the tunnel private key to KEY_PATH with 0600 permissions."""
    key = decode_tunnel_key(load_secret("KAGGLE_TUNNEL_KEY", required=True))
    with open(KEY_PATH, "w", newline="\n", encoding="utf-8") as fh:
        fh.write(key)
    os.chmod(KEY_PATH, stat.S_IRUSR | stat.S_IWUSR)
    print(f"  Tunnel key written to {KEY_PATH}")


def sync_repo() -> None:
    """Clone or fast-forward the workspace repo so helper scripts are current."""
    if (Path(WORKSPACE_DIR) / ".git").exists():
        subprocess.run(["git", "-C", WORKSPACE_DIR, "pull", "--rebase", "-q"], check=False)
    else:
        subprocess.run(["git", "clone", "-q", REPO_URL, WORKSPACE_DIR], check=True)


def find_llama_server() -> Optional[Path]:
    """Find a usable llama-server binary.

    Looks at ``$LLAMA_SERVER_BIN``, a previous extraction in BIN_DIR, then any
    attached dataset (either the bare binary or a ``llama-cpp-sm75.tar.gz``).
    """
    explicit = os.environ.get("LLAMA_SERVER_BIN")
    if explicit and os.access(explicit, os.X_OK):
        return Path(explicit)

    BIN_DIR.mkdir(parents=True, exist_ok=True)
    existing = BIN_DIR / "llama-server"
    if existing.is_file() and os.access(existing, os.X_OK):
        return existing

    for tar_path in sorted(glob("/kaggle/input/**/llama-cpp-sm75*.tar.gz", recursive=True)):
        with tarfile.open(tar_path) as tar:
            try:
                tar.extractall(BIN_DIR, filter="data")  # noqa: S202 - own private dataset
            except TypeError:  # Python without tarfile extraction filters
                tar.extractall(BIN_DIR)  # noqa: S202
        break
    else:
        for bare in sorted(glob("/kaggle/input/**/llama-server", recursive=True)):
            shutil.copy(bare, existing)
            break

    if existing.is_file():
        existing.chmod(existing.stat().st_mode | stat.S_IXUSR)
        return existing
    return None


def ensure_llama_server() -> Path:
    """Return a llama-server binary, building one (~25 min) as a last resort."""
    found = find_llama_server()
    if found:
        return found
    if os.environ.get("ALLOW_BUILD", "1") != "1":
        raise RuntimeError("No llama-server binary found and ALLOW_BUILD=0.")
    print("  No prebuilt binary in an attached dataset -> compiling (~25 min).")
    print("  Tip: run kaggle/build_llama_cpp.sh once and save it as a private dataset.")
    env = dict(os.environ, OUT_DIR=str(BIN_DIR))
    subprocess.run(["bash", f"{WORKSPACE_DIR}/kaggle/build_llama_cpp.sh"], check=True, env=env)
    found = find_llama_server()
    if not found:
        raise RuntimeError("Build finished but no llama-server binary was produced.")
    return found


def http_json(url: str, payload: Optional[dict] = None, key: str = "", timeout: int = 30) -> dict:
    """GET or POST JSON and return the decoded body (raises on HTTP errors)."""
    headers = {"Content-Type": "application/json"}
    if key:
        headers["Authorization"] = f"Bearer {key}"
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(url, data=data, headers=headers)  # noqa: S310 - localhost
    with urllib.request.urlopen(req, timeout=timeout) as resp:  # noqa: S310
        return json.loads(resp.read().decode() or "{}")


def wait_until_ready(port: int, server: subprocess.Popen, timeout_s: int = 900) -> bool:
    """Poll llama-server's /health until it reports ``ok``.

    A 503 or ``{"status": "loading model"}`` means weights are still loading;
    only ``status == "ok"`` counts as ready.
    """
    deadline = time.time() + timeout_s
    last_print = 0.0
    while time.time() < deadline:
        if server.poll() is not None:
            return False
        try:
            body = http_json(f"http://127.0.0.1:{port}/health", timeout=3)
            if body.get("status") == "ok":
                return True
        except (urllib.error.URLError, OSError, ValueError):
            pass
        if time.time() - last_print > 30:
            print(f"  ...loading model ({int(deadline - time.time())}s left)", flush=True)
            last_print = time.time()
        time.sleep(3)
    return False


def smoke_test(port: int, alias: str, key: str) -> None:
    """Send one tiny request, then report speed and whether thinking is enabled."""
    started = time.time()
    body = http_json(
        f"http://127.0.0.1:{port}/v1/chat/completions",
        {
            "model": alias,
            "messages": [{"role": "user", "content": "Reply with the single word: ready"}],
            "max_tokens": 64,
        },
        key=key,
        timeout=120,
    )
    elapsed = max(time.time() - started, 1e-6)
    message = body["choices"][0]["message"]
    tokens = body.get("usage", {}).get("completion_tokens", 0)
    thinking = bool(message.get("reasoning_content")) or "<think>" in (message.get("content") or "")
    print(f"  Reply: {(message.get('content') or '').strip()[:80]!r}")
    print(f"  ~{tokens / elapsed:.1f} tok/s on a tiny request; thinking mode: {'ON' if thinking else 'off'}")


def tail(path: str, lines: int = 30) -> str:
    """Return the last ``lines`` lines of a text file (empty string if unreadable)."""
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return "".join(fh.readlines()[-lines:])
    except OSError:
        return ""


def terminate(proc: Optional[subprocess.Popen], name: str) -> None:
    """Stop a child process politely, then forcefully."""
    if proc is None or proc.poll() is not None:
        return
    print(f"  stopping {name}...")
    proc.terminate()
    try:
        proc.wait(timeout=15)
    except subprocess.TimeoutExpired:
        proc.kill()


# ─── Main ─────────────────────────────────────────────────────────────────────


def main() -> int:  # noqa: C901 - linear orchestration, kept in one place on purpose
    """Run the worker until SESSION_MAX_HOURS elapses or something fails."""
    started = time.time()
    max_hours = float(os.environ.get("SESSION_MAX_HOURS", "6"))
    port = int(os.environ.get("LOCAL_LLM_PORT", "8080"))
    vps_host = os.environ.get("VPS_HOST", "")
    if not vps_host:
        raise RuntimeError("Set VPS_HOST (os.environ['VPS_HOST'] = 'your.vps.ip') first.")
    alias = os.environ.get("MODEL_ALIAS", "qwen3.8-27b")

    step(1, "Detecting GPUs and choosing a model profile")
    gpus = detect_gpus()
    for gpu in gpus:
        print(f"  {gpu.name}: {gpu.memory_mb} MiB")
    ctx_env = os.environ.get("CONTEXT_SIZE")
    profile = choose_profile(
        gpus,
        quant=os.environ.get("QUANT") or None,
        context=int(ctx_env) if ctx_env else None,
        kv_type=os.environ.get("KV_TYPE", "q8_0"),
    )
    print(f"  -> {profile.filename}  ctx={profile.context}  kv={profile.kv_type}  ~{profile.est_vram_gb} GB VRAM")
    if len(gpus) < 2:
        print("  NOTE: single GPU -> heavily quantised model. Quality drops; prefer T4 x2.")

    step(2, "Loading tunnel key and syncing the workspace repo")
    write_tunnel_key()
    sync_repo()
    llm_key = load_secret("LLM_API_KEY")

    step(3, "Locating llama-server")
    binary = ensure_llama_server()
    print(f"  {binary}")

    step(4, "Fetching model weights")
    sys.path.insert(0, f"{WORKSPACE_DIR}/kaggle")
    from fetch_model import ensure_model  # type: ignore[import-not-found]

    model_path = ensure_model(HF_REPO, profile.filename, MODEL_DIR)

    step(5, "Starting llama-server (127.0.0.1 only)")
    server_env = dict(
        os.environ,
        LLAMA_SERVER_BIN=str(binary),
        MODEL_PATH=str(model_path),
        LOCAL_LLM_PORT=str(port),
        CONTEXT_SIZE=str(profile.context),
        KV_TYPE=profile.kv_type,
        MODEL_ALIAS=alias,
        LLM_API_KEY=llm_key,
    )
    log = open(SERVER_LOG, "w", buffering=1, encoding="utf-8")  # noqa: SIM115 - lives with the process
    server = subprocess.Popen(
        ["bash", f"{WORKSPACE_DIR}/kaggle/start_llama_native.sh"],
        stdout=log,
        stderr=subprocess.STDOUT,
        env=server_env,
    )
    tunnel: Optional[subprocess.Popen] = None

    def shutdown(*_: object) -> None:
        terminate(tunnel, "tunnel")
        terminate(server, "llama-server")
        notify("Kaggle GPU worker stopped")

    signal.signal(signal.SIGTERM, lambda *_: (shutdown(), sys.exit(0)))

    try:
        if not wait_until_ready(port, server):
            print("ERROR: llama-server did not become ready. Last log lines:")
            print(tail(SERVER_LOG, 40))
            return 1
        print("  Server ready.")
        smoke_test(port, alias, llm_key)

        step(6, f"Opening reverse SSH tunnel to {vps_host}")
        tunnel_env = dict(
            os.environ,
            VPS_HOST=vps_host,
            VPS_USER=os.environ.get("VPS_USER", "kaggle-gpu"),
            VPS_PORT=os.environ.get("VPS_PORT", "22"),
            VPS_TUNNEL_PORT=os.environ.get("VPS_TUNNEL_PORT", "8081"),
            VPS_TUNNEL_BIND=os.environ.get("VPS_TUNNEL_BIND", "172.17.0.1"),
            KAGGLE_TUNNEL_KEY_PATH=KEY_PATH,
            LOCAL_LLM_PORT=str(port),
        )
        tunnel = subprocess.Popen(
            ["bash", f"{WORKSPACE_DIR}/kaggle/reverse_tunnel_to_vps.sh"], env=tunnel_env
        )
        notify(f"Kaggle GPU worker up: {profile.filename}, stops in {max_hours:g}h")
        print(f"\n  Worker will stop itself after {max_hours:g} h. Check from the VPS:")
        print("    bash scripts/agent_stack_status.sh\n", flush=True)

        deadline = started + max_hours * 3600
        while time.time() < deadline:
            if server.poll() is not None:
                print("ERROR: llama-server exited. Last log lines:")
                print(tail(SERVER_LOG, 40))
                return 1
            time.sleep(20)
        print(f"Reached SESSION_MAX_HOURS={max_hours:g}; shutting down cleanly.")
        return 0
    except KeyboardInterrupt:
        print("Interrupted.")
        return 0
    finally:
        shutdown()


if __name__ == "__main__":
    _exit_code = main()
    if _exit_code:  # only raise on failure so a clean run ends the notebook normally
        raise SystemExit(_exit_code)
