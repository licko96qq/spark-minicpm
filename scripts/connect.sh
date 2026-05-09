#!/usr/bin/env bash
# connect.sh — Mac 端建 SSH 隧道并打开浏览器
set -euo pipefail

REMOTE=spark_704
PORT=8765

echo "[connect] 检查并清理旧隧道…"
pkill -f "ssh.*-L ${PORT}.*${REMOTE}" 2>/dev/null || true
sleep 1

echo "[connect] 建立 SSH 隧道 localhost:${PORT} → ${REMOTE}:${PORT}…"
nohup ssh -L "${PORT}:127.0.0.1:${PORT}" -N "${REMOTE}" \
  > /tmp/spark-minicpm-tunnel.log 2>&1 &
TUNNEL_PID=$!
echo "[connect] 隧道 PID: ${TUNNEL_PID}"

sleep 2

if ! lsof -i:${PORT} -sTCP:LISTEN 2>/dev/null | grep -q ssh; then
  echo "[connect] ❌ 隧道建立失败，查 /tmp/spark-minicpm-tunnel.log"
  exit 1
fi

echo "[connect] 测试 HTTP…"
if curl -fsS "http://localhost:${PORT}/" -o /dev/null; then
  echo "[connect] ✅ 服务可达，打开浏览器…"
  open "http://localhost:${PORT}/?nocache=$(date +%s)"
else
  echo "[connect] ⚠️ HTTP 测试失败，spark 端服务可能没起。先跑 start-spark-minicpm.sh"
  exit 1
fi
