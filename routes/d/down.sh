#!/usr/bin/env bash
# 路线 D 停止
set -euo pipefail
SPARK_REMOTE="${SPARK_REMOTE:-spark_704}"
DEMO_DIR="/home/LChuang/workspace/MiniCPM-o-Demo-D"

echo "==> 关本机 SSH tunnel"
pkill -f "ssh.*-L 8050:localhost:8050.*$SPARK_REMOTE" 2>/dev/null && echo "    tunnel killed" || echo "    no tunnel"

echo "==> 停 spark Demo-D 进程（gateway / worker / llama-server）"
ssh "$SPARK_REMOTE" "
  cd $DEMO_DIR/tmp 2>/dev/null && for f in *.pid; do
    [ -f \"\$f\" ] || continue
    pid=\$(cat \"\$f\")
    kill \$pid 2>/dev/null && echo \"  killed \$f (\$pid)\" || true
  done
  pkill -f 'gateway.py.*--port 8050' 2>/dev/null || true
  pkill -f 'worker.py.*--port 22450' 2>/dev/null || true
  pkill -f 'llama-server.*19090' 2>/dev/null || true
  sleep 2
  ! pgrep -f 'gateway.py.*8050|worker.py.*22450|llama-server.*19090' >/dev/null && echo '✅ 路线 D down.' || echo '⚠️ 仍有进程'"
