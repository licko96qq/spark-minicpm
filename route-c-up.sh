#!/usr/bin/env bash
# 路线 C 启动：MiniCPM-o 4.5 视频全双工 (WebRTC_Demo + llama.cpp-omni F16)
# 用法: bash route-c-up.sh [F16|Q4_K_M|Q8_0|...]   默认 F16

set -euo pipefail

LLM_QUANT="${1:-F16}"
# ⚠️ oneclick.sh 的 LLM_QUANT 不传到 cpp_server，cpp_server 走 auto_detect 优先 Q4_K_M
# 唯一可靠办法：传 LLM_MODEL=<完整文件名> 环境变量
LLM_MODEL_FILE="MiniCPM-o-4_5-${LLM_QUANT}.gguf"
CTX_SIZE="${CTX_SIZE:-8192}"  # 8K 默认。实测：16K 让 n_past 上限翻倍，attention 计算复杂度 ↑ → 单步慢 → 卡顿。除非有强长上下文需求否则别动
# 路线 C2 陪伴 prompt（注入到 cpp_server warmup，绕开 fast_resume）
# 短版（~80 token）— n_keep 不撑大避免 attention 慢
SYSTEM_PROMPT="${SYSTEM_PROMPT:-<|im_start|>system
Streaming Duplex Conversation! 你是用户的专业陪伴助手，看到屏幕（论文/网页/文档）后主动解读、翻译英文、补充专业背景（生物/AI/医学/自动化）。回答详细但紧扣当前画面，简单问题可简短回应。
<|audio_start|>}"
SPARK_REMOTE="${SPARK_REMOTE:-spark_704}"
DEMO_DIR="/home/LChuang/workspace/MiniCPM-V-CookBook/demo/web_demo/WebRTC_Demo"

echo "==> [1/3] 启动 spark 端 4 服务 (LLM_QUANT=$LLM_QUANT, mode=duplex)"
# inline 单行 ssh + < /dev/null 防止后台进程随 ssh 退出（heredoc + nohup 实测会被 SIGHUP）
# 用 health endpoint 检查更稳，避免 grep "frontend.*running" 误匹配 "frontend not running"
if ssh "$SPARK_REMOTE" "curl -sf http://localhost:9061/health 2>/dev/null | grep -q healthy"; then
  echo "    [skip] services already running (cpp_server healthy)"
else
  # SYSTEM_PROMPT 含换行，用 base64 透传避免 shell 转义炸
  PROMPT_B64=$(printf '%s' "$SYSTEM_PROMPT" | base64)
  ssh "$SPARK_REMOTE" "cd $DEMO_DIR && rm -f .logs/oneclick-start.log && nohup env PATH=\"\$HOME/.local/bin:\$HOME/.npm-global/bin:\$PATH\" PYTHON_CMD=/home/LChuang/miniconda3/envs/minicpm/bin/python LLAMACPP_ROOT=/home/LChuang/workspace/llama.cpp-omni MODEL_DIR=/home/LChuang/workspace/MiniCPM-o-4_5-gguf LLM_MODEL=$LLM_MODEL_FILE CTX_SIZE=$CTX_SIZE SYSTEM_PROMPT=\"\$(echo $PROMPT_B64 | base64 -d)\" CPP_MODE=duplex bash oneclick.sh start > .logs/oneclick-start.log 2>&1 < /dev/null & disown && echo started"
  echo "    started (waiting ~90s for cpp model load)"
fi

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
