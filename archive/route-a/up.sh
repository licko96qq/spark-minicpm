#!/usr/bin/env bash
# route-a-up.sh — 一键启动「路线 A · 简化版 webrtc_demo」
#
# 路线 A：基于 mgi 学生版改造的 half-duplex 语音/视频对话服务
# - Spark uvicorn 监听 127.0.0.1:8765
# - Mac 端 SSH tunnel + 浏览器 http://localhost:8765
# - 单一 half-duplex 模式（VAD/PTT），TTFT ~2.3s
#
# 部署位置：spark_704:/home/LChuang/workspace/minicpm/
# 详见 README.md / docs/01-architecture.md
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "${SCRIPT_DIR}/scripts/start-spark-minicpm.sh"
bash "${SCRIPT_DIR}/scripts/connect.sh"

cat <<EOF

=================================================
  ✅ 路线 A 已就绪
  浏览器：http://localhost:8765
  停服务：bash ${SCRIPT_DIR}/route-a-down.sh
=================================================
EOF
