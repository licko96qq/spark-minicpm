#!/usr/bin/env bash
# 用法: bash scripts/build-llama-cpp-omni.sh [89|120|86|...]
# 默认根据 nvidia-smi 自动检测 GPU 架构
# 目标目录: ${LLAMACPP_ROOT:-~/llama.cpp-omni}
# 输出:    ${LLAMACPP_ROOT}/build/bin/llama-server
# 分支:    feat/web-demo (tc-mb/llama.cpp-omni)

set -euo pipefail

LLAMACPP_ROOT="${LLAMACPP_ROOT:-$HOME/llama.cpp-omni}"
REPO_URL="${REPO_URL:-https://github.com/tc-mb/llama.cpp-omni}"
BRANCH="${BRANCH:-feat/web-demo}"
ARCH="${1:-}"

# 自动检测 GPU 架构
if [ -z "$ARCH" ]; then
  if command -v nvidia-smi >/dev/null 2>&1; then
    GPU=$(nvidia-smi --query-gpu=name --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "unknown")
  else
    GPU="unknown"
  fi
  case "$GPU" in
    *4090*)                      ARCH=89 ;;
    *5090*|*GB10*|*Blackwell*)   ARCH=120 ;;
    *3090*|*A100*)               ARCH=86 ;;
    *H100*)                      ARCH=90 ;;
    *) echo "[!] 未知 GPU: $GPU, 默认 sm_120 (Blackwell)"; ARCH=120 ;;
  esac
  echo "==> 自动检测 GPU=\"$GPU\", CUDA_ARCH=$ARCH"
fi

# clone 或 fetch
if [ ! -d "$LLAMACPP_ROOT/.git" ]; then
  echo "==> [1/4] clone $REPO_URL → $LLAMACPP_ROOT"
  git clone "$REPO_URL" "$LLAMACPP_ROOT"
else
  echo "==> [1/4] $LLAMACPP_ROOT 已存在, fetch"
  git -C "$LLAMACPP_ROOT" fetch --all
fi

cd "$LLAMACPP_ROOT"

echo "==> [2/4] checkout $BRANCH"
git checkout "$BRANCH"

echo "==> [3/4] cmake configure (CUDA_ARCH=$ARCH)"
cmake -B build \
  -DCMAKE_CUDA_ARCHITECTURES="$ARCH" \
  -DGGML_CUDA=ON \
  -DLLAMA_CURL=OFF

echo "==> [4/4] cmake build llama-server"
t0=$(date +%s)
cmake --build build --target llama-server -j"$(nproc)"
t1=$(date +%s)
elapsed=$((t1 - t0))

BIN="$LLAMACPP_ROOT/build/bin/llama-server"
if [ ! -x "$BIN" ]; then
  echo "[ERR] llama-server 未生成: $BIN"
  exit 1
fi

echo ""
echo "==> done. 编译耗时: ${elapsed}s"
ls -lh "$BIN"
echo ""
echo "快速 smoke test:"
echo "  $BIN --version"
