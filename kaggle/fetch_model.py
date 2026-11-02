#!/usr/bin/env python3
"""Locate or download a single GGUF model file for the Kaggle worker.

Search order:
  1. An already-downloaded copy in the target directory.
  2. A GGUF with the same filename inside an attached Kaggle Dataset
     (``/kaggle/input/**``) -- zero download time.
  3. Download from Hugging Face (one file, not the whole repo).

Models are stored in ``/tmp/models`` by default, NOT ``/kaggle/working``:
``/kaggle/working`` is capped at ~20 GB and anything in it is saved as
notebook output on "Save & Run All" runs.

Usage:
    python3 fetch_model.py unsloth/Qwen3.8-27B-GGUF Qwen3.8-27B-UD-Q4_K_M.gguf
"""

from __future__ import annotations

import argparse
import glob
import os
import sys
from pathlib import Path
from typing import Optional

DEFAULT_MODEL_DIR = "/tmp/models"
KAGGLE_INPUT_GLOB = "/kaggle/input/**/{name}"


def find_in_kaggle_input(filename: str) -> Optional[Path]:
    """Return the first attached-dataset file matching ``filename``, if any.

    Args:
        filename: Exact GGUF file name to look for.

    Returns:
        Path to the file, or None when no attached dataset contains it.
    """
    matches = sorted(glob.glob(KAGGLE_INPUT_GLOB.format(name=filename), recursive=True))
    return Path(matches[0]) if matches else None


def ensure_model(repo: str, filename: str, model_dir: str = DEFAULT_MODEL_DIR) -> Path:
    """Return a local path to ``filename``, downloading it only if necessary.

    Args:
        repo: Hugging Face repo id, e.g. ``unsloth/Qwen3.8-27B-GGUF``.
        filename: Exact file within the repo.
        model_dir: Directory used for downloads and caches.

    Returns:
        Path to a readable GGUF file.

    Raises:
        RuntimeError: If the download fails or produces an empty file.
    """
    target_dir = Path(model_dir)
    target_dir.mkdir(parents=True, exist_ok=True)

    local = target_dir / filename
    if local.is_file() and local.stat().st_size > 0:
        print(f"  Model already present: {local} ({local.stat().st_size / 1e9:.1f} GB)")
        return local

    attached = find_in_kaggle_input(filename)
    if attached is not None:
        print(f"  Using attached dataset copy: {attached}")
        return attached

    print(f"  Downloading {repo}/{filename} -> {target_dir} (this can take 10-20 min)...")
    os.environ.setdefault("HF_HUB_CACHE", "/tmp/hf_cache")
    os.environ.setdefault("HF_HUB_ENABLE_HF_TRANSFER", "0")
    try:
        from huggingface_hub import hf_hub_download  # imported lazily: heavy dependency
    except ImportError as exc:
        raise RuntimeError("huggingface_hub is not installed (pip install huggingface_hub)") from exc

    token = os.environ.get("HF_TOKEN") or None
    try:
        downloaded = Path(
            hf_hub_download(repo_id=repo, filename=filename, local_dir=str(target_dir), token=token)
        )
    except Exception as exc:  # noqa: BLE001 - surface any hub error with context
        raise RuntimeError(f"Download failed for {repo}/{filename}: {exc}") from exc

    if not downloaded.is_file() or downloaded.stat().st_size == 0:
        raise RuntimeError(f"Downloaded file is missing or empty: {downloaded}")
    print(f"  Download complete: {downloaded} ({downloaded.stat().st_size / 1e9:.1f} GB)")
    return downloaded


def main(argv: Optional[list[str]] = None) -> int:
    """CLI entry point. Prints the resolved model path on the last line."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("repo")
    parser.add_argument("filename")
    parser.add_argument("--model-dir", default=DEFAULT_MODEL_DIR)
    args = parser.parse_args(argv)
    try:
        path = ensure_model(args.repo, args.filename, args.model_dir)
    except RuntimeError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    print(path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
