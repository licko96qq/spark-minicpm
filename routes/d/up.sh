#!/usr/bin/env bash
# 路线 D 启动：B-cpp + silero-vad 自动打断（4 模式 + 屏幕共享）
# 用法: bash routes/d/up.sh [F16|Q4_K_M|Q8_0]   默认 Q4_K_M（流畅档）
# ⚠️ 互斥关系：与路线 B-cpp 共享 cpp_server 二进制，但端口完全独立
#   - 路线 D 端口：gateway 8050 / worker 22450 / llama 19090
#   - 路线 B-cpp 端口：gateway 8040 / worker 22440 / llama 19080
#   - 共存内存压力：121G unified 上 Q4(D) + Q4(B-cpp) 共 ~10G 可行，Q8+Q8 ~16G 偏紧

set -euo pipefail

LLM_QUANT="${1:-Q4_K_M}"
LLM_MODEL_FILE="MiniCPM-o-4_5-${LLM_QUANT}.gguf"

SPARK_REMOTE="${SPARK_REMOTE:-spark_704}"
DEMO_DIR="/home/LChuang/workspace/MiniCPM-o-Demo-D"

echo "==> [pre] 确保 silero_vad.onnx 就位（来自路线 C，约 1.8 MB）"
ssh "$SPARK_REMOTE" "
  ONNX_DST=$DEMO_DIR/core/vad/silero_vad.onnx
  ONNX_SRC=/home/LChuang/workspace/MiniCPM-V-CookBook/demo/web_demo/WebRTC_Demo/omini_backend_code/code/voice_chat/vad/silero_vad.onnx
  if [ ! -f \"\$ONNX_DST\" ]; then
    if [ -f \"\$ONNX_SRC\" ]; then
      mkdir -p \$(dirname \$ONNX_DST) && cp \$ONNX_SRC \$ONNX_DST && echo '    onnx copied from route C'
    else
      echo '    ⚠️ silero_vad.onnx 不存在，VAD 不可用（路线 D 退化为手动 force_listen）'
    fi
  else
    echo '    onnx already present'
  fi
"

echo "==> [0/3] 检查端口冲突"
if ssh "$SPARK_REMOTE" "ss -tlnp 2>/dev/null | grep -qE ':(8050|22450|19090)\s'"; then
  echo "    ⚠️ 端口 8050/22450/19090 之一已占用，可能 D 已在跑"
  echo "    检查: ssh $SPARK_REMOTE 'curl -sf http://localhost:8050/health'"
  echo "    停止: bash routes/d/down.sh"
fi

echo "==> [1/3] 更新 config.json 量化档位 → $LLM_QUANT"
ssh "$SPARK_REMOTE" "cd $DEMO_DIR && sed -i 's|\"llm_model\":[[:space:]]*\"[^\"]*\"|\"llm_model\":     \"$LLM_MODEL_FILE\"|' config.json && grep llm_model config.json"

echo "==> [2/3] 启动 Demo-D 4 模式服务（gateway 8050, cpp_server 19090）"
ssh "$SPARK_REMOTE" "cd $DEMO_DIR && nohup bash start_all.sh --http > /tmp/route-d.log 2>&1 < /dev/null & disown; echo started"

echo "    等待 worker 加载（~90s）..."
for i in {1..120}; do
  if ssh "$SPARK_REMOTE" "curl -sf http://localhost:22450/health 2>/dev/null" | grep -q '"model_loaded":true'; then
    echo "    worker ready"
    break
  fi
  sleep 2
done

echo "==> [3/3] 建本机 SSH tunnel (8050/22450)"
pkill -f "ssh.*-L 8050:localhost:8050.*$SPARK_REMOTE" 2>/dev/null || true
sleep 1
ssh -fN -L 8050:localhost:8050 -L 22450:localhost:22450 "$SPARK_REMOTE"

echo ""
echo "✅ 路线 D up ($LLM_QUANT). 浏览器打开:"
echo "   http://localhost:8050/omni/         (omni + 自动 VAD + 屏幕共享)"
echo "   http://localhost:8050/audio-duplex/ (纯语音双工 + 自动 VAD)"
echo "   http://localhost:8050/              (4 模式入口)"
echo ""
echo "查看 VAD 触发: ssh $SPARK_REMOTE 'grep \"\\[VAD-D\\]\" $DEMO_DIR/tmp/worker_0.log | tail -20'"
echo "查看启动日志: ssh $SPARK_REMOTE 'tail -f /tmp/route-d.log'"
echo "停服务:       bash routes/d/down.sh"
