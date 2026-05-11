#!/usr/bin/env bash
# 路线 C 停止：杀本机 SSH tunnel + spark 4 服务
set -euo pipefail
SPARK_REMOTE="${SPARK_REMOTE:-spark_704}"
DEMO_DIR="/home/LChuang/workspace/MiniCPM-V-CookBook/demo/web_demo/WebRTC_Demo"

echo "==> 关本机 SSH tunnel"
pkill -f "ssh.*-L 8088:localhost:8088.*$SPARK_REMOTE" 2>/dev/null && echo "    tunnel killed" || echo "    no tunnel running"

echo "==> 停 spark 4 服务"
ssh "$SPARK_REMOTE" "cd $DEMO_DIR && bash oneclick.sh stop" 2>&1 | tail -8

echo "✅ 路线 C down."
