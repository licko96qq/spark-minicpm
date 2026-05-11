# 路线 D — Patches 说明

## 状态

✅ **已上线**（spark commit `6690d01`，route-d 分支）

## Patch 文件

### `0001-silero-vad-integration.patch`

**含义**：从 spark commit `6690d01`（route-d 分支）导出，叠加在 B-cpp commit `596d1af` 之上。也就是说路线 D 已**继承 B-cpp 全部改动**（屏幕共享、sampling defaults、陪伴 prompt），本 patch 只携带 D 独有差异。

**改动**：
- `worker.py`
  - 顶部加 `from core.vad.silero_vad import get_vad as _get_silero_vad`（graceful fallback，模块缺失时 VAD 不启用，路线 D 退化为手动 force_listen）
  - `duplex_ws` audio_chunk 处理：在 `chunk_force_listen = bool(msg.get("force_listen", False))` 后插 VAD 检测，prob > 0.5 时覆盖为 `True`
  - `prepare` msg：reset VAD LSTM state（新会话）
  - 日志格式：`[VAD-D] auto-interrupt prob=0.87`
- `core/vad/silero_vad.py`（新建）：thread-safe 单例，16kHz float32 PCM 输入，1024-sample 滑窗，单 VAD 简化版（路线 C 是 dual VAD）
- `core/vad/__init__.py`（新建）：空文件
- `config.json`：端口避让 `19080→19090 / 8040→8050 / 22440→22450`，`data_dir data → data-d`
- `.gitignore`：data-d/ + .venv

**不含**：`silero_vad.onnx`（1.8 MB 二进制）。由 `routes/d/up.sh` 自动从路线 C 复制：

```bash
cp /home/LChuang/workspace/MiniCPM-V-CookBook/demo/web_demo/WebRTC_Demo/omini_backend_code/code/voice_chat/vad/silero_vad.onnx \
   /home/LChuang/workspace/MiniCPM-o-Demo-D/core/vad/
```

## 应用顺序（首次部署）

```bash
# 1. clone Demo-Comni 完整副本（包含 B-cpp commit 596d1af）
ssh spark_704 "cp -r /home/LChuang/workspace/MiniCPM-o-Demo-Comni /home/LChuang/workspace/MiniCPM-o-Demo-D"
ssh spark_704 "cd /home/LChuang/workspace/MiniCPM-o-Demo-D && git checkout -b route-d"

# 2. 应用本 patch（仅 D 独有改动）
bash scripts/apply-patches.sh d /home/LChuang/workspace/MiniCPM-o-Demo-D

# 3. .venv symlink 共享 B-cpp 依赖
ssh spark_704 "cd /home/LChuang/workspace/MiniCPM-o-Demo-D && rm -rf .venv && ln -s /home/LChuang/workspace/MiniCPM-o-Demo-Comni/.venv .venv"

# 4. 装 onnxruntime（如果还没装）
ssh spark_704 "/home/LChuang/workspace/MiniCPM-o-Demo-Comni/.venv/base/bin/pip install onnxruntime==1.23.2"
```

`routes/d/up.sh` 启动时会自动复制 onnx 文件。

## 验证（已通过 CLI 测试）

| 场景 | 预期 | 实测 |
|---|---|---|
| 用户说话期间 | VAD prob ≥ 0.5 触发 force_listen=True，模型 LISTEN | ✅ prob 0.6-0.99 触发 |
| 用户停顿后 | VAD 不触发，模型自然 SPEAK | ✅ 11s 后 SPEAK 出文本 + 3 个 audio_only msgs |
| 静音背景 | VAD prob < 0.05 | ✅ 0.04 |
| 与路线 C 共存 | 端口/内存无冲突 | ✅ 2× Q4_K_M 同跑稳定 |
| 浏览器实测「SPEAK 中开口打断」 | < 300ms 内停止 | 🚧 待用户实测 |

## 反向操作（回滚）

```bash
ssh spark_704 "cd /home/LChuang/workspace/MiniCPM-o-Demo-D && git checkout master"  # 切回 B-cpp 基线
# 或彻底删除目录
ssh spark_704 "rm -rf /home/LChuang/workspace/MiniCPM-o-Demo-D"
```

## 相关参考

- 路线 B-cpp patches：`../../b-cpp/patches/README.md`（路线 D 起点）
- 路线 C VAD 原版实现：`spark_704:/home/LChuang/workspace/MiniCPM-V-CookBook/demo/web_demo/WebRTC_Demo/omini_backend_code/code/voice_chat/vad/vad_utils.py:380-405`
- HANDOVER「路线 D」条目：滚动更新
