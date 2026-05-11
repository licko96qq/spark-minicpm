#!/usr/bin/env bash
# route-a-down.sh — 一键关停路线 A
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "${SCRIPT_DIR}/scripts/stop.sh"
