# 路线 D — Patches 说明

## 状态

🚧 **占位文档**，待 Phase B 实施后填充。

## 预期 patch 列表

路线 D 的代码改动预计走 patch 链承载（类似路线 B-cpp，而非路线 C 的启动脚本注入方式），因为 VAD 集成涉及 worker/backend 源码改动较深。

### `0001-from-b-cpp.patch`（规划）

- **用途**：继承路线 B-cpp 的全部前端/后端改动（sampling defaults、屏幕共享按钮、陪伴 prompt、Q4_K_M 默认、gitignore）
- **来源**：直接 copy `../../b-cpp/patches/0001-screen-share-companion-mode.patch`，rebase 到 spark 端 `MiniCPM-o-Demo-D` 目录
- **影响文件**（与 B-cpp 一致）：
  - `static/omni/omni-app.js`
  - `static/omni/omni.html`
  - `static/audio-duplex/audio-duplex-app.js`
  - `config.json`
  - `.gitignore`

### `0002-silero-vad-integration.patch`（核心，规划）

- **用途**：路线 D 区别于 B-cpp 的**核心能力** —— 自动 VAD 打断
- **移植源**：路线 C 的 `omini_backend_code/code/voice_chat/omni_stream.py:vad_dual_detection`
- **ONNX 模型**：复用路线 C 已下载的 `silero_vad.onnx`（软链到 `MiniCPM-o-Demo-D/assets/silero_vad.onnx`）
- **预期影响文件**：
  - `worker.py`：在 `duplex_ws` handler 启 VAD 线程，消费上行 audio_chunk buffer，检测 `dur_vad_full ≥ 0.85` 时自动注入 `force_listen=true` 发送给 cpp_backend
  - `core/schemas/duplex.py`：`DuplexConfig` 可能需要新增 `vad_enabled` / `vad_threshold` / `vad_hangover_ms` 字段
  - `core/processors/cpp_backend.py`：可能需要对齐 VAD force_listen 注入 timing，避免和用户手动「Force Listen」按钮双触发
  - 前端：新增「自动 VAD 打断」开关（ON/OFF toggle），默认 ON
- **依赖**：`onnxruntime`（CPU 推理足够，~2ms/chunk）

## 应用方式（规划）

```bash
bash /Users/licko/Documents/workspace/cc_test/AllRealHub/spark-minicpm/scripts/apply-patches.sh d /home/LChuang/workspace/MiniCPM-o-Demo-D
```

patch 按数字前缀顺序应用。建议**顺序敏感**：必须先 0001 再 0002（0002 依赖 0001 的 sampling defaults 否则模型仍不 SPEAK）。

## 反向操作（规划）

```bash
cd /home/LChuang/workspace/MiniCPM-o-Demo-D
git reset --hard <baseline-commit>   # 完全回滚到 clone 时的 commit
# 或单独 revert
git revert <sha-of-0002>
```

## 待办清单（Phase B 实施时填）

- [ ] clone Demo-Comni 到 `MiniCPM-o-Demo-D/`
- [ ] 软链 `silero_vad.onnx` 从路线 C
- [ ] apply `0001-from-b-cpp.patch`，跑 smoke 确认 4 模式仍正常
- [ ] 写 `0002-silero-vad-integration.patch`：worker 侧 VAD 线程 + force_listen 自动注入
- [ ] 加前端「自动 VAD 打断」toggle
- [ ] 端到端测试：说话 → 模型闭嘴延迟 < 200ms；对比路线 C 的 dur_vad_full 体验
- [ ] 更新 `docs/16-troubleshooting.md` 加 VAD 误触发 / 延迟 / 噪音鲁棒性章节
- [ ] 把本 README 的「状态」改成「✅ 已上线」并填写真实 commit SHA、实测数据

## 相关参考

- 路线 B-cpp patches：`../../b-cpp/patches/README.md`（0001 原版）
- 路线 C VAD 实现：spark `~/workspace/MiniCPM-V-CookBook/demo/web_demo/WebRTC_Demo/omini_backend_code/code/voice_chat/omni_stream.py`
- HANDOVER「路线 D」条目：进度滚动更新
