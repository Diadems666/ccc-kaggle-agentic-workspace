#!/usr/bin/env bash
set -euo pipefail

# Deploy the Kaggle side of the agent stack with the official Kaggle CLI.
#
# Usage:
#   bash scripts/kaggle_deploy.sh check      # CLI installed + authenticated?
#   bash scripts/kaggle_deploy.sh build      # push + run the one-time llama.cpp build notebook (~25 min)
#   bash scripts/kaggle_deploy.sh dataset    # download build output -> private dataset llama-cpp-sm75
#   bash scripts/kaggle_deploy.sh worker     # push + run the GPU worker notebook (personal use only)
#   bash scripts/kaggle_deploy.sh status     # status of both notebooks
#   bash scripts/kaggle_deploy.sh stop       # explain how to stop a running worker
#
# Auth: `kaggle auth login`, or an existing ~/.kaggle/kaggle.json, or the
# KAGGLE_USERNAME + KAGGLE_KEY environment variables.
#
# Environment:
#   SESSION_MAX_HOURS  worker hard stop (default 1 for a first shakedown)
#   VPS_HOST           default 112.213.38.79
#   VPS_HOST_KEY       optional pinned host key line (ssh-keyscan -t ed25519 <vps>)
#   KAGGLE_ACCELERATOR optional value for `kaggle kernels push --accelerator`

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_SLUG="ccc-build-llama-cpp"
WORKER_SLUG="ccc-gpu-worker-v2"
DATASET_SLUG="llama-cpp-sm75"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

die() { echo "ERROR: $*" >&2; exit 1; }

need_cli() {
    command -v kaggle >/dev/null 2>&1 || die "kaggle CLI not found. Install: pip install kaggle   then: kaggle auth login"
}

kaggle_user() {
    if [[ -n "${KAGGLE_USERNAME:-}" ]]; then echo "$KAGGLE_USERNAME"; return; fi
    local u
    u="$(kaggle config view 2>/dev/null | sed -n 's/^- username: *//p' | head -n 1)"
    if [[ -z "$u" && -f "$HOME/.kaggle/kaggle.json" ]]; then
        u="$(python3 -c "import json,os;print(json.load(open(os.path.expanduser('~/.kaggle/kaggle.json')))['username'])")"
    fi
    [[ -n "$u" ]] || die "Cannot determine Kaggle username. Set KAGGLE_USERNAME."
    echo "$u"
}

accel_args() {
    if [[ -n "${KAGGLE_ACCELERATOR:-}" ]]; then echo "--accelerator ${KAGGLE_ACCELERATOR}"; fi
}

write_meta() {  # dir slug title notebook sources_json
    local dir="$1" slug="$2" title="$3" nb="$4" sources="$5" user
    user="$(kaggle_user)"
    mkdir -p "$dir"
    cp "$ROOT/kaggle/$nb" "$dir/$nb"
    python3 - "$dir" "$user" "$slug" "$title" "$nb" "$sources" <<'PY'
import json, sys
d, user, slug, title, nb, sources = sys.argv[1:7]
meta = {
    "id": f"{user}/{slug}",
    "title": title,
    "code_file": nb,
    "language": "python",
    "kernel_type": "notebook",
    "is_private": True,
    "enable_gpu": True,
    "enable_tpu": False,
    "enable_internet": True,
    "dataset_sources": json.loads(sources),
    "competition_sources": [],
    "kernel_sources": [],
    "model_sources": [],
}
with open(f"{d}/kernel-metadata.json", "w", encoding="utf-8") as fh:
    json.dump(meta, fh, indent=2)
PY
}

cmd_check() {
    need_cli
    echo "kaggle CLI: $(kaggle --version 2>&1 | head -n 1)"
    echo "user:       $(kaggle_user)"
    kaggle kernels list --mine --page-size 1 >/dev/null 2>&1 \
        && echo "auth:       OK" || die "Authentication failed. Run: kaggle auth login"
}

cmd_build() {
    need_cli
    write_meta "$WORK/build" "$BUILD_SLUG" "CCC build llama.cpp sm75" "kaggle-build-llama.ipynb" "[]"
    # shellcheck disable=SC2046
    kaggle kernels push -p "$WORK/build" $(accel_args)
    echo "Build started (about 25 min). Watch: bash scripts/kaggle_deploy.sh status"
    echo "When it shows COMPLETE, run: bash scripts/kaggle_deploy.sh dataset"
}

cmd_dataset() {
    need_cli
    local user out
    user="$(kaggle_user)"
    out="$WORK/out"
    mkdir -p "$out"
    kaggle kernels output "${user}/${BUILD_SLUG}" -p "$out"
    [[ -f "$out/llama-cpp-sm75.tar.gz" ]] || die "llama-cpp-sm75.tar.gz not in the build output. Check the build log: kaggle kernels output ${user}/${BUILD_SLUG}"
    mkdir -p "$WORK/ds"
    cp "$out/llama-cpp-sm75.tar.gz" "$out/BUILD_INFO.txt" "$WORK/ds/" 2>/dev/null || cp "$out/llama-cpp-sm75.tar.gz" "$WORK/ds/"
    python3 - "$WORK/ds" "$user" "$DATASET_SLUG" <<'PY'
import json, sys
d, user, slug = sys.argv[1:4]
meta = {"title": "llama.cpp sm75 build", "id": f"{user}/{slug}",
        "licenses": [{"name": "MIT"}]}
with open(f"{d}/dataset-metadata.json", "w", encoding="utf-8") as fh:
    json.dump(meta, fh, indent=2)
PY
    if kaggle datasets status "${user}/${DATASET_SLUG}" >/dev/null 2>&1; then
        kaggle datasets version -p "$WORK/ds" -m "rebuild $(date +%F)"
    else
        kaggle datasets create -p "$WORK/ds"   # private by default
    fi
    echo "Dataset ${user}/${DATASET_SLUG} is ready (private)."
}

cmd_worker() {
    need_cli
    local user hours
    user="$(kaggle_user)"
    hours="${SESSION_MAX_HOURS:-1}"
    echo "Personal / R&D use only (Kaggle ToS). Client work goes through ccc-client."
    echo "Worker will stop itself after ${hours} h."
    write_meta "$WORK/worker" "$WORKER_SLUG" "CCC GPU worker v2" "kaggle-quick-start-v2.ipynb" \
        "[\"${user}/${DATASET_SLUG}\"]"
    # Inject runtime settings into the notebook's config cell.
    python3 - "$WORK/worker/kaggle-quick-start-v2.ipynb" "${VPS_HOST:-112.213.38.79}" "$hours" "${VPS_HOST_KEY:-}" <<'PY'
import json, sys
path, host, hours, hostkey = sys.argv[1:5]
nb = json.load(open(path, encoding="utf-8"))
for cell in nb["cells"]:
    src = "".join(cell["source"])
    if cell["cell_type"] == "code" and "VPS_HOST" in src and "SESSION_MAX_HOURS" in src:
        lines = [f"import os", f"os.environ['VPS_HOST'] = {host!r}",
                 f"os.environ['SESSION_MAX_HOURS'] = {hours!r}"]
        if hostkey:
            lines.append(f"os.environ['VPS_HOST_KEY'] = {hostkey!r}")
        lines.append("print('Config set.')")
        cell["source"] = [l + "\n" for l in lines]
        break
else:
    raise SystemExit("config cell not found in notebook")
json.dump(nb, open(path, "w", encoding="utf-8"), indent=1)
PY
    # shellcheck disable=SC2046
    kaggle kernels push -p "$WORK/worker" $(accel_args)
    cat <<MSG

Pushed. FIRST RUN ONLY: Kaggle notebook Secrets cannot be set from the CLI.
  1. Open https://www.kaggle.com/code/${user}/${WORKER_SLUG}
  2. Add-ons -> Secrets: add KAGGLE_TUNNEL_KEY (the restricted tunnel private key,
     see vps/agent-stack/install-agent-stack.sh output) and attach it to this notebook.
  3. Settings: Accelerator = GPU T4 x2, Internet = On.
  4. Save Version -> Save & Run All.
Later pushes keep the secret attachment.
Check from the VPS: bash scripts/agent_stack_status.sh
MSG
}

cmd_status() {
    need_cli
    local user
    user="$(kaggle_user)"
    for slug in "$BUILD_SLUG" "$WORKER_SLUG"; do
        printf '%-22s ' "$slug"
        kaggle kernels status "${user}/${slug}" 2>&1 | tail -n 1
    done
}

cmd_stop() {
    cat <<'MSG'
The worker stops itself at SESSION_MAX_HOURS. To stop earlier, open the notebook
on kaggle.com and use the session menu -> Stop session. The CLI has no stop command.
MSG
}

case "${1:-}" in
    check)   cmd_check ;;
    build)   cmd_build ;;
    dataset) cmd_dataset ;;
    worker)  cmd_worker ;;
    status)  cmd_status ;;
    stop)    cmd_stop ;;
    *) sed -n '3,20p' "${BASH_SOURCE[0]}"; exit 2 ;;
esac
