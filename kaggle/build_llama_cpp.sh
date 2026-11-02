#!/usr/bin/env bash
set -euo pipefail

# Build llama.cpp's `llama-server` for Kaggle T4 GPUs (CUDA arch sm_75).
#
# Run this ONCE in a Kaggle GPU notebook (takes ~25 min), then save the output
# (/kaggle/working/llama-cpp-sm75.tar.gz) as a private Kaggle Dataset and attach
# it to the worker notebook. The worker then starts in seconds instead of
# recompiling every session.
#
# Why not `pip install llama-cpp-python`? Its pre-built wheels lag behind new
# model architectures (Qwen3.8 uses the hybrid DeltaNet "qwen3_5" arch).
#
# Env overrides:
#   LLAMA_CPP_REF   git ref to build (branch, tag or SHA). Default: master
#   OUT_DIR         where to put the result. Default: /kaggle/working/llama-cpp-sm75
#   SRC_DIR         scratch checkout. Default: /tmp/llama.cpp-src
#   JOBS            parallel compile jobs. Default: nproc

REF="${LLAMA_CPP_REF:-master}"
OUT_DIR="${OUT_DIR:-/kaggle/working/llama-cpp-sm75}"
SRC_DIR="${SRC_DIR:-/tmp/llama.cpp-src}"
JOBS="${JOBS:-$(nproc)}"
REPO_URL="https://github.com/ggml-org/llama.cpp"

echo "=== Building llama-server (sm_75) ==="
echo "Ref:    $REF"
echo "Out:    $OUT_DIR"
echo "Jobs:   $JOBS"
echo ""

if ! command -v nvcc >/dev/null 2>&1; then
    # Kaggle images keep the toolkit here but do not always put it on PATH.
    if [[ -x /usr/local/cuda/bin/nvcc ]]; then
        export PATH="/usr/local/cuda/bin:$PATH"
    else
        echo "ERROR: nvcc not found. Enable a GPU accelerator in notebook settings." >&2
        exit 1
    fi
fi
nvcc --version | tail -n 2

apt-get install -qq -y cmake build-essential git >/dev/null 2>&1 || true
command -v cmake >/dev/null 2>&1 || { echo "ERROR: cmake missing" >&2; exit 1; }

# ─── Fetch source (works for branches, tags and commit SHAs) ─────────────────
rm -rf "$SRC_DIR"
mkdir -p "$SRC_DIR"
git -C "$SRC_DIR" init -q
git -C "$SRC_DIR" remote add origin "$REPO_URL"
git -C "$SRC_DIR" fetch -q --depth 1 origin "$REF"
git -C "$SRC_DIR" checkout -q FETCH_HEAD
SRC_SHA="$(git -C "$SRC_DIR" rev-parse --short HEAD)"
echo "Source: $REPO_URL @ $SRC_SHA"

# ─── libcuda stub: the driver library is not on the link path in Kaggle ──────
# (llama.cpp links against libcuda.so; only libcuda.so.1 exists at runtime.)
CUDA_HOME_DIR="${CUDA_HOME:-/usr/local/cuda}"
STUB_DIR="$CUDA_HOME_DIR/lib64/stubs"
EXTRA_CMAKE=()
if [[ -f "$STUB_DIR/libcuda.so" ]]; then
    EXTRA_CMAKE+=("-DCMAKE_LIBRARY_PATH=$STUB_DIR")
else
    REAL_CUDA="$(find / -name 'libcuda.so.1' -not -path '*/proc/*' 2>/dev/null | head -n 1 || true)"
    if [[ -n "$REAL_CUDA" ]]; then
        mkdir -p /tmp/cuda-stubs
        ln -sf "$REAL_CUDA" /tmp/cuda-stubs/libcuda.so
        EXTRA_CMAKE+=("-DCMAKE_LIBRARY_PATH=/tmp/cuda-stubs")
    fi
fi
if [[ -n "${REAL_CUDA:-}" ]]; then
    EXTRA_CMAKE+=("-DCMAKE_EXE_LINKER_FLAGS=-Wl,-rpath-link,$(dirname "$REAL_CUDA")")
fi

# ─── Configure + build ───────────────────────────────────────────────────────
cd "$SRC_DIR"
cmake -B build \
    -DCMAKE_BUILD_TYPE=Release \
    -DGGML_CUDA=ON \
    -DCMAKE_CUDA_ARCHITECTURES=75 \
    -DGGML_NATIVE=OFF \
    -DBUILD_SHARED_LIBS=OFF \
    -DLLAMA_CURL=OFF \
    -DLLAMA_BUILD_TESTS=OFF \
    -DLLAMA_BUILD_EXAMPLES=OFF \
    "${EXTRA_CMAKE[@]}"
cmake --build build --config Release --target llama-server -j "$JOBS"

BIN="$SRC_DIR/build/bin/llama-server"
[[ -x "$BIN" ]] || { echo "ERROR: build finished but $BIN is missing" >&2; exit 1; }

# ─── Package ─────────────────────────────────────────────────────────────────
mkdir -p "$OUT_DIR"
cp "$BIN" "$OUT_DIR/llama-server"
{
    echo "llama.cpp_ref=$REF"
    echo "llama.cpp_sha=$SRC_SHA"
    echo "cuda=$(nvcc --version | grep -oP 'release \K[\d.]+' | head -n 1 || echo unknown)"
    echo "arch=sm_75"
    echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$OUT_DIR/BUILD_INFO.txt"

echo ""
echo "Dynamic library check (anything 'not found' will fail at runtime):"
ldd "$OUT_DIR/llama-server" | tee "$OUT_DIR/ldd.txt" | sed 's/^/  /'
if grep -q "not found" "$OUT_DIR/ldd.txt"; then
    echo "WARNING: missing shared libraries listed above." >&2
fi

TARBALL="$(dirname "$OUT_DIR")/llama-cpp-sm75.tar.gz"
tar -C "$OUT_DIR" -czf "$TARBALL" .
echo ""
echo "=== Done ==="
echo "Binary:  $OUT_DIR/llama-server"
echo "Tarball: $TARBALL ($(du -h "$TARBALL" | cut -f1))"
echo ""
echo "Next: notebook sidebar → Output → '...' → New Dataset → name it 'llama-cpp-sm75'"
echo "      (keep it PRIVATE), then attach it to the worker notebook."
