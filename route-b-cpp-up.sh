#!/usr/bin/env bash
# 路线 B-cpp 启动：MiniCPM-o-Demo Comni 分支（4模式 demo + cpp backend → llama.cpp-omni）
# ⚠️ 与路线 C 互斥（共享 F16 模型，内存只够一份）
# 启动前自动停路线 C 释放内存

set -euo pipefail

SPARK_REMOTE="${SPARK_REMOTE:-spark_704}"
DEMO_DIR="/home/LChuang/workspace/MiniCPM-o-Demo-Comni"
ROUTE_C_DIR="/home/LChuang/workspace/MiniCPM-V-CookBook/demo/web_demo/WebRTC_Demo"

echo "==> [0/3] 检查路线 C 是否在跑（互斥）"
if ssh "$SPARK_REMOTE" "cd $ROUTE_C_DIR && bash oneclick.sh status 2>&1 | grep -q 'cpp_server.*running'"; then
  echo "    路线 C cpp_server 在跑，先停（释放 ~22G 内存）..."
  ssh "$SPARK_REMOTE" "cd $ROUTE_C_DIR && bash oneclick.sh stop 2>&1 | tail -3"
  sleep 3
fi

echo "==> [1/3] 启动 Demo-Comni 4 模式服务（gateway 8040, cpp_server 19080）"
ssh "$SPARK_REMOTE" "cd $DEMO_DIR && nohup bash start_all.sh --http > /tmp/route-b-cpp.log 2>&1 < /dev/null & disown; echo started"

echo "==> [2/3] 等待 cpp_server 启动 + F16 加载（~90s）"
for i in {1..120}; do
  if ssh "$SPARK_REMOTE" "curl -sf http://localhost:8040/health 2>/dev/null" | grep -q ok 2>/dev/null; then
    echo "    gateway healthy"
    break
  fi
  sleep 2
done

echo "==> [3/3] 建本机 SSH tunnel"
pkill -f "ssh.*-L 8040:localhost:8040.*$SPARK_REMOTE" 2>/dev/null || true
sleep 1
ssh -fN -L 8040:localhost:8040 -L 22440:localhost:22440 "$SPARK_REMOTE"

echo ""
echo "✅ 路线 B-cpp up. 浏览器打开:"
echo "   https://localhost:8040/                  (4 模式入口 desktop)"
echo "   https://localhost:8040/mobile/           (mobile React)"
echo "   https://localhost:8040/mobile-omni/      (mobile Omni)"
echo ""
echo "查看日志: ssh $SPARK_REMOTE 'tail -f /tmp/route-b-cpp.log'"
echo "停服务:   bash route-b-cpp-down.sh"
echo "切回路线C: bash route-b-cpp-down.sh && bash route-c-up.sh F16"
