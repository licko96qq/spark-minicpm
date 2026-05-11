#!/usr/bin/env bash
# start-spark-minicpm.sh — 在 spark 启动 MiniCPM-o 4.5 服务
set -euo pipefail

REMOTE=spark_704
WORKDIR=/home/LChuang/workspace/minicpm
PORT=8765

echo "[start] 检查端口是否已占用…"
if ssh "$REMOTE" "ss -tnlp 2>/dev/null | grep -q ':${PORT}'"; then
  echo "[start] 端口 ${PORT} 已在监听，跳过启动"
  ssh "$REMOTE" "ss -tnlp 2>/dev/null | grep ':${PORT}'"
  exit 0
fi

echo "[start] 启动 uvicorn (后台)…"
ssh "$REMOTE" "
  source /home/LChuang/miniconda3/etc/profile.d/conda.sh
  conda activate minicpm
  export MINICPM_CONFIG=${WORKDIR}/deploy/config.yaml
  cd ${WORKDIR}/webrtc_demo
  nohup python -m uvicorn server:app --host 127.0.0.1 --port ${PORT} \
    > ${WORKDIR}/server.log 2>&1 &
  disown
  echo \"PID: \$!\"
"

echo "[start] 等待模型加载（约 2 分钟）…"
for i in {1..40}; do
  sleep 5
  if ssh "$REMOTE" "grep -q '模型就绪' ${WORKDIR}/server.log 2>/dev/null"; then
    echo "[start] ✅ 模型就绪，监听 127.0.0.1:${PORT}"
    echo "[start] 下一步：bash $(dirname "$0")/connect.sh"
    exit 0
  fi
  echo "  …等待中 (${i}/40)"
done

echo "[start] ⚠️ 等待超时，请检查 ssh ${REMOTE} 'tail -50 ${WORKDIR}/server.log'"
exit 1
