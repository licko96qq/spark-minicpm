#!/usr/bin/env bash
# 用法: bash scripts/apply-patches.sh <route> <upstream-dir>
# 例:
#   bash scripts/apply-patches.sh b-cpp ~/workspace/MiniCPM-o-Demo-Comni
#   bash scripts/apply-patches.sh c     ~/workspace/MiniCPM-V-CookBook/demo/web_demo/WebRTC_Demo
#   bash scripts/apply-patches.sh d     ~/workspace/MiniCPM-o-Demo-D
#
# 按文件名排序对 routes/<route>/patches/*.patch 用 git am 逐个应用。
# 失败会自动 git am --abort，不留半 applied 状态。

set -euo pipefail

if [ $# -lt 2 ]; then
  echo "用法: $0 <route> <upstream-dir>"
  echo "route ∈ {b-cpp, c, d}"
  exit 1
fi

ROUTE="$1"
UPSTREAM="$2"

# 找 patches 目录 —— 基于本脚本所在位置推算
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PATCH_DIR="$REPO_ROOT/routes/$ROUTE/patches"

if [ ! -d "$PATCH_DIR" ]; then
  echo "[ERR] patches 目录不存在: $PATCH_DIR"
  exit 1
fi

# 收集 patch (按文件名排序)
mapfile -t PATCHES < <(find "$PATCH_DIR" -maxdepth 1 -name '*.patch' -type f | sort)

if [ ${#PATCHES[@]} -eq 0 ]; then
  echo "[ERR] $PATCH_DIR 下没有 *.patch 文件"
  exit 1
fi

if [ ! -d "$UPSTREAM/.git" ]; then
  echo "[ERR] upstream-dir 不是 git 仓库: $UPSTREAM"
  exit 1
fi

echo "==> apply ${#PATCHES[@]} patches to $UPSTREAM"
for p in "${PATCHES[@]}"; do
  echo "    $(basename "$p")"
done
echo ""

cd "$UPSTREAM"

BASE_COMMIT="$(git rev-parse HEAD)"

for p in "${PATCHES[@]}"; do
  name="$(basename "$p")"
  echo "==> git am < $name"
  if ! git am < "$p"; then
    echo "[ERR] $name 应用失败, 执行 git am --abort 回滚"
    git am --abort || true
    echo "    当前 HEAD 仍是 $BASE_COMMIT"
    exit 1
  fi
done

echo ""
echo "==> done. 新增 commits:"
git log --oneline "${BASE_COMMIT}..HEAD"
