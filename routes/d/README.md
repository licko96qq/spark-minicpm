# 路线 D — B-cpp + silero-vad 自动打断 + 量化切换脚本

## 一句话定位

路线 B-cpp 的**功能超集**：保留屏幕共享 / 4 模式 UI，**加上**路线 C 的自动 VAD 打断能力（silero-vad ONNX，前端或后端检测 ≥0.85 → 自动 `force_listen=true`），并封装 CLI 量化切换，一步走到**B-cpp 的 UI + C 的打断体验**。

## 状态

🚧 **规划中**（plan 文件已批准，代码尚未实施）。目前在做哪步、预计验收时再更新本 README。

- Phase A（已完成）：plan 文档批准，路径确定、端口规划完成
- Phase B（进行中）：clone Demo-Comni → spark 新目录 → 移植路线 C 的 `vad_dual_detection` 逻辑 → 复用 silero_vad.onnx
- Phase C（待定）：端到端验证 + KPI 对比（打断延迟、长会话稳定性）

## 目标上游来源

```bash
# 基于 B-cpp 的 Comni 分支，clone 到独立目录避免冲突
git clone https://github.com/OpenBMB/MiniCPM-o-Demo
cd MiniCPM-o-Demo
git checkout Comni
# spark 部署路径: /home/LChuang/workspace/MiniCPM-o-Demo-D/
```

VAD 代码移植自路线 C：
- 源文件：`~/workspace/MiniCPM-V-CookBook/demo/web_demo/WebRTC_Demo/omini_backend_code/code/voice_chat/omni_stream.py`
- 核心函数：`vad_dual_detection` —— silero-vad ONNX 推理，两级阈值（快速响应 + 稳态触发）
- ONNX 模型：复用路线 C 已下载的 `silero_vad.onnx`，软链到 `MiniCPM-o-Demo-D` 的 assets 目录

## 前置条件（目标）

- 路线 B-cpp 全部前置条件 + silero-vad ONNX 运行时（`onnxruntime`，CPU 推理 ~2ms/chunk，无需 GPU）
- 与路线 B-cpp / C **互斥**（同样共享 F16/Q8 模型，内存只够一份）——up.sh 会先停另外两个路线
- 独立 spark 部署路径避免与 B-cpp 冲突

## 部署步骤（目标）

1. `git clone ... MiniCPM-o-Demo-D && git checkout Comni`；
2. venv 装依赖（同 B-cpp 基础 + `onnxruntime`）；
3. 软链 `silero_vad.onnx` 从路线 C 的 assets 过来；
4. 应用 patch：
   ```bash
   bash ../../scripts/apply-patches.sh d /home/LChuang/workspace/MiniCPM-o-Demo-D
   ```
   当前 patch 序列：
   - `0001-from-b-cpp.patch`（继承 B-cpp 全部前端/后端改动）
   - `0002-silero-vad-integration.patch`（核心 VAD 集成，worker 里起 VAD 线程 + 自动 `force_listen` 注入）
5. 启动：`bash routes/d/up.sh [F16|Q8_0|Q4_K_M]`

## 启停（目标）

```bash
bash /Users/licko/Documents/workspace/cc_test/AllRealHub/spark-minicpm/routes/d/up.sh Q8_0
bash /Users/licko/Documents/workspace/cc_test/AllRealHub/spark-minicpm/routes/d/down.sh
```

`up.sh` 职责（规划）：
- 停路线 B-cpp / C 释放内存
- 量化档位走 `$1`（如路线 C，而不是路线 B-cpp 改 config.json，避免多档切换要改代码）
- 建本机 8050 / 22450 的 tunnel

## 端口表（规划）

| 服务 | 端口 | 备注 |
|---|---|---|
| gateway (HTTP) | 8050 | 浏览器入口 |
| worker WS | 22450 | 4 模式共用 |
| llama-server | 19090 | 内部 |

端口都 +10 避开路线 B-cpp（8040/22440/19080），方便并行开发时互不干扰（但生产上仍与 B-cpp / C 互斥共享模型）。

## 配置文件改动点（规划）

- `config.json` → `cpp_backend.llm_model`：**由 `up.sh $1` 生成**（继承路线 C 的方式），不是手改
- VAD 配置（新增字段）：
  - `vad.threshold`：默认 0.85（= 路线 C 默认）
  - `vad.min_speech_duration_ms`：最短检测语音长度，默认 200
  - `vad.silence_hangover_ms`：silence 后多久取消 force_listen，默认 500
- 仍继承 B-cpp 的 `stopOnKvShrink` 默认取消勾选

## 该路线 patches 说明

见 `./patches/README.md`。当前为**占位说明**，待 Phase B 实施后填充真实 patch 文件和 diff 摘要。

## 已知问题（预期）

- **模型永远 LISTEN 不 SPEAK**：继承自 B-cpp（`lps=0.3 flc=0` 必须）——patch 0001 包含
- **长会话 KV 滑窗停止**：继承自 B-cpp，没有像路线 C 那样的 C++ 滑窗——长会话仍有上限
- **VAD 误触发**：若环境噪音高或 `threshold` 设太低，模型可能说一半被打断；需要在 `docs/16-troubleshooting.md` 中记录调优经验
- **打断同步延迟**：前端检测 → worker WS → cpp_backend 注入 force_listen，预期端到端 50-100ms；如果 > 300ms 要排查 WS 队列堆积

## 何时选这条路线（目标）

- 同时需要屏幕共享陪伴模式 + 自动 VAD 打断
- 短-中会话（< 1 分钟，避开 B-cpp 的 KV 上限）
- 多量化档位快速对比场景
- 想要 B-cpp 4 模式 UI 完整度但又不想手动按 Force Listen

**不选的场景**：长会话视频全双工——用路线 C。路线 D 未实施完毕——现阶段仍用 B-cpp 或 C。

## 追踪

实施进度在 HANDOVER 里滚动更新（标签 "路线 D"）。Phase B 完成后本 README 的「状态」「部署步骤」「已知问题」需要从「规划中」全部刷一遍为实测数据。
