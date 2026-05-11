#!/usr/bin/env bash
# stop.sh — 关停 spark 服务和本机隧道
set -euo pipefail

REMOTE=spark_704
PORT=8765

echo "[stop] 关闭本机 SSH 隧道…"
pkill -f "ssh.*-L ${PORT}.*${REMOTE}" 2>/dev/null && echo "  隧道已关" || echo "  无隧道"

echo "[stop] 关闭 spark 端 uvicorn…"
ssh "${REMOTE}" "pkill -f 'uvicorn server:app' && echo '  uvicorn 已关' || echo '  uvicorn 未运行'"

echo "[stop] 完成。"
