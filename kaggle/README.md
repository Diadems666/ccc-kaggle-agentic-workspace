# Kaggle GPU Scripts

Scripts for setting up a Kaggle T4 notebook as a free GPU inference worker.

## Overview

Kaggle offers free access to an NVIDIA T4 GPU (16 GB VRAM) for up to 30 GPU-hours per week. These scripts:

1. Set up the Kaggle notebook environment (CUDA, dependencies)
2. Download and start an LLM server (llama.cpp or vLLM)
3. Open a reverse SSH tunnel to expose the LLM on your VPS
4. Monitor the session and save state before the 12-hour timeout

## Files

| File | Purpose |
|------|---------|
| `KAGGLE_NOTEBOOK_SETUP.md` | Step-by-step Kaggle setup guide |
| `setup_kaggle_gpu_worker.sh` | Install dependencies, download model |
| `start_llama_server.sh` | Start llama.cpp server (recommended) |
| `start_vllm_server.sh` | Start vLLM server (higher throughput) |
| `reverse_tunnel_to_vps.sh` | Open SSH reverse tunnel to VPS |
| `session_watchdog.py` | Monitor session time, auto-save before expiry |
| `save_state.sh` | Save workspace state to GitHub |
| `requirements.txt` | Python dependencies |

## Quick Start

In a Kaggle notebook with T4 GPU enabled, run these cells in order:

```python
# Cell 1: Clone workspace
!git clone https://github.com/YOUR_ORG/ccc-kaggle-agentic-workspace /tmp/ws

# Cell 2: Set up worker
!bash /tmp/ws/kaggle/setup_kaggle_gpu_worker.sh

# Cell 3: Start LLM server (runs in background)
import subprocess
proc = subprocess.Popen(['bash', '/tmp/ws/kaggle/start_llama_server.sh'])

# Cell 4: Start tunnel (runs in background — keep this cell running)
import os
os.environ['VPS_HOST'] = 'YOUR_VPS_IP'
os.environ['KAGGLE_TUNNEL_KEY'] = open('/tmp/kaggle_tunnel_key').read()
!bash /tmp/ws/kaggle/reverse_tunnel_to_vps.sh

# Cell 5: Start watchdog (optional but recommended)
!python3 /tmp/ws/kaggle/session_watchdog.py
```

## Security Notes

- Never store the tunnel private key in this repo or in Kaggle notebook files
- Use Kaggle Secrets to inject the key at runtime
- The key should only be authorised for port forwarding, not interactive shell access

See `SECURITY.md` in the repo root for full details.

## Qwen3.8 agent stack (v2)

The recommended path is now `quick_start_v2.py` / `kaggle-quick-start-v2.ipynb` (native llama.cpp, Qwen3.8-27B, auto-sized for the GPUs). Build llama.cpp once with `kaggle-build-llama.ipynb`. The v1 `quick_start.py` is deprecated (it uses `os` before importing it). Full details: `../docs/KAGGLE_QWEN38_AGENT.md`.
