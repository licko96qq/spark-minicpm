# 12 - 路线 C2 智能/速度调优方案

> 2026-05-11 12:30 — 用户实测反馈：F16 智能好但卡顿，Q4_K_M 速度快但智能差。出权衡方案。

## 当前问题诊断

### 矛盾的两端

| 配置 | 智能 | 速度 | 用户体验 |
|---|---|---|---|
| **Q4_K_M (4.7G)** 之前误打误撞跑了 | 差，回答有时简短废话 | 不卡 | "用着可以" |
| **F16 (16G)** 12:22 切上 | 明显好 | 卡顿（一卡一卡） | "智能好很多但又卡了" |

### 根本原因

GB10 unified memory 带宽 = A100 的 14%，**内存带宽是 F16 的瓶颈**：
- F16 一帧推理 ~500-800ms（粗估）
- 视频每秒来 5-10 帧
- F16 单步 > 帧间隔 → 队列堆积 → 卡顿
- Q4_K_M 一帧 ~150-250ms → 跟得上节奏

**Q4_K_M 智能差不是量化的唯一锅**，还有 3 个叠加因素：
1. `ctx_size=8192` 太小，长对话快速塞满
2. `n_keep=82` 只保 system prompt，**滑窗丢用户对话历史 + 早期视觉帧**（这就是"画面与说的不一致 / 说的是上一个画面"的根因）
3. system prompt 默认 `You are a helpful assistant`，没场景引导

## 解决方案 — 三选一

### 🌟 方案 B (推荐): **Q8_0 + ctx 16K + 陪伴 prompt**

| 项 | 现状 | 新值 | 为什么 |
|---|---|---|---|
| 量化 | Q4_K_M 4.7G | **Q8_0 ~9G** | Q8 vs F16 智能损失 <2%（业界共识），速度比 F16 快 ~2x |
| ctx_size | 8192 | **16384** | 推理 KV 翻倍，可容纳 2x 视觉帧历史，缓解滑窗丢历史 |
| system prompt | 默认 helpful assistant | **桌面陪伴特化版**（角色+主动观察+长描述偏好） | prompt 越具体引导越强；明确"画面具体在说什么/不要废话/长描述" |
| n_keep | 82 (硬编码=system token 数) | **自动变 ~400-600**（加长 system prompt 间接拉大 n_keep） | 滑窗保留更多锚点信息，模型不易忘记自己角色 |
| temp / repeat-penalty | 0.7 / 1.05 | 保持 | 适中无需动 |

**预期**：智能 ≈ F16 的 95%，速度 ≈ Q4_K_M 的 70%（仍较流畅）。

### 方案 A (速度优先): **Q4_K_M + ctx 16K + 陪伴 prompt**

如果方案 B 仍卡顿，回退到 Q4_K_M 但保留 ctx + prompt 优化。智能 ≈ Q4 + 20-30%（因为 prompt 改善 + ctx 翻倍）。

### 方案 C (智能优先 - 当前 F16): 保持不动

接受卡顿换最高智能，用于内容理解要求高的场景（如读复杂文档）。

## 关键技术：怎么让 prompt 真生效

**已知约束**：`cpp_server` 启动时有 warmup 调一次 omni_init，之后 fast_resume 不重设 prompt。所以 `voice_clone_prompt` 字段虽链路通但**实际用户调时是 fast_resume 走原 prompt**。

**修复方案**：改 `cpp_server/minicpmo_cpp_http_server.py:813` 的 `pre_init_request`，让它读 `SYSTEM_PROMPT` 环境变量并塞进 `voice_clone_prompt`。这样 warmup 时就用我们的陪伴 prompt，后续所有 fast_resume 都基于这个 prompt。

只改 ~5 行 Python，不动 C++，不重编。

## 推荐执行步骤（待你 ACK）

1. **后台下 Q8_0** (~9G，hf-mirror 约 60-90s) — ✅ 已启动 `/tmp/q8-download.log`
2. **改 cpp_server.py warmup**：读 `SYSTEM_PROMPT` 环境变量注入 voice_clone_prompt（warmup 之前应用）
3. **改 oneclick.sh / route-c-up.sh**：透传 `CTX_SIZE` + `SYSTEM_PROMPT` 环境变量
4. **重启 cpp_server**：`LLM_MODEL=MiniCPM-o-4_5-Q8_0.gguf CTX_SIZE=16384 SYSTEM_PROMPT='...' route-c-up.sh`
5. **实测对比**：智能 + 速度，确定甜点

## 陪伴 prompt 草稿（你 ACK 前可修改）

```
<|im_start|>system
Streaming Duplex Conversation! 你是用户的桌面陪伴助手，能实时看到他屏幕上的内容（网页、视频、游戏、代码、文档）。你的任务：

1. 主动观察：识别屏幕上的关键元素（标题、内容、用户正在操作的位置）。
2. 详细描述：当用户问"这是什么/介绍一下"时，给出具体、有条理的描述（至少 3-5 句），不要简短敷衍。
3. 陪伴感：语气轻松友好像朋友，但内容专业准确。
4. 实时性：根据用户鼠标所指或当前画面动态调整描述焦点。
5. 简短回应：如果用户只是闲聊或简单问题，自然回应即可。

<|audio_start|>
```

## Q8 vs F16 vs Q4 — 实测预期表

| 维度 | Q4_K_M | Q8_0 (推荐) | F16 |
|---|---|---|---|
| 大小 | 4.7G | ~9G | 16G |
| 智能 vs F16 | -8~15% | -1~3% | 基线 |
| 单帧推理 | ~200ms | ~350ms | ~700ms |
| 5min 视频流畅度 | 流畅 | 流畅或微卡 | 卡顿明显 |
| spark 内存占用 | ~14G | ~18G | ~25G |

## 如果方案不及预期

退路：
- A 退路：Q8 仍卡 → 回 Q4 + 调更狠的 prompt
- B 退路：智能仍差 → 改 cpp_server 加大 n_keep 到 1024+（要小心 KV 容量）
- C 退路：考虑分阶段降帧率（10fps → 5fps）让 F16 跟得上

## 你的决策

请回 A / B / C 选定，或修改方案后回 ACK 我就开干。
