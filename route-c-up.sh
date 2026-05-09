#!/usr/bin/env bash
# 路线 C 启动：MiniCPM-o 4.5 视频全双工 (WebRTC_Demo + llama.cpp-omni F16)
# 用法: bash route-c-up.sh [F16|Q4_K_M|Q8_0|...]   默认 F16

set -euo pipefail

LLM_QUANT="${1:-F16}"
SPARK_REMOTE="${SPARK_REMOTE:-spark_704}"
DEMO_DIR="/home/LChuang/workspace/MiniCPM-V-CookBook/demo/web_demo/WebRTC_Demo"

echo "==> [1/3] 启动 spark 端 4 服务 (LLM_QUANT=$LLM_QUANT, mode=duplex)"
ssh "$SPARK_REMOTE" bash <<EOF
set -e
cd $DEMO_DIR
mkdir -p .logs
# 检查是否已运行
if bash oneclick.sh status 2>&1 | grep -q "frontend.*running"; then
  echo "    [skip] services already running"
else
  rm -f .logs/oneclick-start.log
  nohup env PATH="\$HOME/.local/bin:\$HOME/.npm-global/bin:\$PATH" \\
    PYTHON_CMD=/home/LChuang/miniconda3/envs/minicpm/bin/python \\
    LLAMACPP_ROOT=/home/LChuang/workspace/llama.cpp-omni \\
    MODEL_DIR=/home/LChuang/workspace/MiniCPM-o-4_5-gguf \\
    LLM_QUANT=$LLM_QUANT CPP_MODE=duplex \\
    bash oneclick.sh start > .logs/oneclick-start.log 2>&1 &
  disown
  echo "    started (waiting ~60s for cpp model load)"
fi
EOF

echo "==> [2/3] 等待 cpp_server 健康检查"
for i in {1..60}; do
  if ssh "$SPARK_REMOTE" "curl -sf http://localhost:9061/health" 2>/dev/null | grep -q healthy; then
    echo "    healthy"
    break
  fi
  sleep 2
done

echo "==> [3/3] 建本机 SSH tunnel"
pkill -f "ssh.*-L 8088:localhost:8088.*$SPARK_REMOTE" 2>/dev/null || true
sleep 1
ssh -fN \
  -L 8088:localhost:8088 \
  -L 7880:localhost:7880 \
  -L 9060:localhost:9060 \
  -L 9061:localhost:9061 \
  "$SPARK_REMOTE"

echo ""
echo "✅ 路线 C up. 浏览器打开: https://localhost:8088/"
echo "   (手机同 WiFi: https://192.168.8.202:8088/)"
echo ""
echo "查看日志: ssh $SPARK_REMOTE 'cd $DEMO_DIR && bash oneclick.sh logs cpp'"
echo "停服务:   bash route-c-down.sh"
