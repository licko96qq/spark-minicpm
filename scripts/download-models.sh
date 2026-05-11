#!/usr/bin/env bash
# 用法: bash scripts/download-models.sh [Q4_K_M|Q8_0|F16|all]
# 默认 Q4_K_M（4.7G，流畅档，4090/5090/GB10 都能跑）
# 升级智能可后续追加：bash scripts/download-models.sh Q8_0  (8.2G 甜点)
#                  bash scripts/download-models.sh F16   (16G 最高)
# 目标目录: ${MODEL_DIR:-~/MiniCPM-o-4_5-gguf}
# 依赖:   pip install -U "huggingface_hub[cli]"
# 镜像:   HF_ENDPOINT=https://hf-mirror.com  (国内加速)
# 参考:   spark_704:/home/LChuang/workspace/MiniCPM-o-4_5-gguf/  (已下载版本)

set -euo pipefail

# TODO 验证仓库名 — tc-mb 发布的 MiniCPM-o-4_5 GGUF 仓库。若报 404 检查
# https://hf-mirror.com/openbmb 和 https://hf-mirror.com/tc-mb
REPO="${HF_REPO:-openbmb/MiniCPM-o-4_5-gguf}"
QUANT="${1:-Q4_K_M}"
MODEL_DIR="${MODEL_DIR:-$HOME/MiniCPM-o-4_5-gguf}"
export HF_ENDPOINT="${HF_ENDPOINT:-https://hf-mirror.com}"

mkdir -p "$MODEL_DIR"
cd "$MODEL_DIR"

# 依赖检查
if ! command -v huggingface-cli >/dev/null 2>&1; then
  echo "[!] huggingface-cli 未安装，尝试 pip install..."
  pip install -U "huggingface_hub[cli]"
fi

# 主模型 gguf —— 按 quant 选
declare -a MAIN_FILES=()
case "$QUANT" in
  F16)     MAIN_FILES=("MiniCPM-o-4_5-F16.gguf") ;;
  Q8_0)    MAIN_FILES=("MiniCPM-o-4_5-Q8_0.gguf") ;;
  Q4_K_M)  MAIN_FILES=("MiniCPM-o-4_5-Q4_K_M.gguf") ;;
  all)     MAIN_FILES=("MiniCPM-o-4_5-F16.gguf" "MiniCPM-o-4_5-Q8_0.gguf" "MiniCPM-o-4_5-Q4_K_M.gguf") ;;
  *) echo "用法: $0 [Q4_K_M|Q8_0|F16|all]"; exit 1 ;;
esac

echo "==> [1/2] 下载主模型 gguf (quant=$QUANT) to $MODEL_DIR"
for f in "${MAIN_FILES[@]}"; do
  if [ -f "$MODEL_DIR/$f" ]; then
    echo "    [skip] $f 已存在"
    continue
  fi
  echo "    downloading $f ..."
  huggingface-cli download "$REPO" "$f" --local-dir "$MODEL_DIR" --local-dir-use-symlinks False
done

echo "==> [2/2] 下载子模型目录 (audio/ vision/ tts/ token2wav-gguf/)"
# 子模型体积相对小，用 include pattern 一次下完
huggingface-cli download "$REPO" \
  --local-dir "$MODEL_DIR" \
  --local-dir-use-symlinks False \
  --include "audio/*" "vision/*" "tts/*" "token2wav-gguf/*"

echo ""
echo "==> done. 最终目录大小:"
du -sh "$MODEL_DIR"
echo ""
echo "内容:"
ls -lh "$MODEL_DIR"
