#!/usr/bin/env bash
# 路线 B-cpp 停止
set -euo pipefail
SPARK_REMOTE="${SPARK_REMOTE:-spark_704}"
DEMO_DIR="/home/LChuang/workspace/MiniCPM-o-Demo-Comni"

echo "==> 关本机 SSH tunnel"
pkill -f "ssh.*-L 8040:localhost:8040.*$SPARK_REMOTE" 2>/dev/null && echo "    tunnel killed" || echo "    no tunnel"

echo "==> 停 spark Demo-Comni 进程（gateway / worker / llama-server）"
ssh "$SPARK_REMOTE" "
  cd $DEMO_DIR/tmp 2>/dev/null && for f in *.pid; do
    [ -f \"\$f\" ] || continue
    pid=\$(cat \"\$f\")
    kill \$pid 2>/dev/null && echo \"  killed \$f (\$pid)\" || true
  done
  pkill -f 'gateway.py\|worker.py\|llama-server.*19080' 2>/dev/null || true
  sleep 2
  ! pgrep -f 'gateway.py\|worker.py' >/dev/null && echo '✅ 路线 B-cpp down.' || echo '⚠️ 仍有进程'"
