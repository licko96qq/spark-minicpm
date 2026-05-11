# 11 - 用户反馈：路线 C2 屏幕共享测试

## 测试元数据

- **日期**：2026-05-11
- **路线**：C2（WebRTC_Demo + llama.cpp-omni）
- **环境**：spark DGX Spark + MiniCPM-o 4.5 F16 GGUF
- **触发方式**：浏览器 localStorage 开启屏幕共享
- **测试内容**：AI 实时描述 Biomni（General-Purpose Biomedical AI Agent）网页

## 功能结论

- 屏幕共享链路正常
- AI 能看到屏幕并实时字幕输出

## 用户原话

> 可以用。不过每次回答的智能程度比较差，不知道是提示词问题还是模型问题还是上下文不够长的问题。有些时候可以回答很多很长，适当引导一些就可以讲很多内容，有时候不管怎么问都是说废话和很简短的话。

## 反馈拆解

### 现象

- 智能程度不稳定，回答长度方差大
- 适当引导下可输出长内容
- 无引导时易输出简短废话

### 用户怀疑方向

1. 提示词问题
2. 模型问题（9B 参数上限）
3. 上下文不够长

## 待定位问题清单

- [ ] **Prompt**：当前双工模式默认 `You are a helpful assistant`，未针对"桌面观察"场景调优
- [ ] **模型容量**：MiniCPM-o 9B 参数在多模态长对话中的智能上限
- [ ] **上下文窗口**：`ctx_size=8192` + 滑窗丢历史，长对话记忆丢失
- [ ] **KV cache 压力**：视频全双工每帧采样过快，可能压爆 KV cache 导致退化

## 用户期望

AI 作为"桌面陪伴助手"：

- 主动观察屏幕内容
- 长时间记忆（跨会话、跨片段）
- 有上下文的连贯对话（非一问一答）

## 补充反馈（2026-05-11 12:20）

> 它说的内容有些时候画面与说的内容不一致，比如我鼠标在移动，问它我现在指的是什么，介绍这块内容，它说的部分正确，部分不对，部分说的是上一个画面的内容。

现象：**视觉描述与当前画面有时间错位**，AI 输出混合了几秒前的画面信息。

## 排查结果（主 agent）

### 🚨 1. 决定性根因：实际跑的是 **Q4_K_M 不是 F16**

- 用户测试时 cpp_server 实际加载 `MiniCPM-o-4_5-Q4_K_M.gguf`（4.7G），不是预期的 F16
- 启动日志：`✅ 自动检测到 LLM 模型: MiniCPM-o-4_5-Q4_K_M.gguf`
- llama-server 实际命令行：`--model .../MiniCPM-o-4_5-Q4_K_M.gguf`
- **原因**：`cpp_server/minicpmo_cpp_http_server.py:67 auto_detect_llm_model()` 的优先级是 `Q4_K_M > Q4_K_S > Q8_0 > Q5_K_M > F16`，写死偏好量化版
- **oneclick.sh 的 `LLM_QUANT=F16` 不工作**：这个环境变量没传到 cpp_server，cpp_server 只读 `LLM_MODEL` 环境变量或 `--llm-model` 参数
- **修复**：传 `LLM_MODEL=MiniCPM-o-4_5-F16.gguf`（已 12:22 重启验证生效，PID 462137 跑 F16）

### 🚨 2. KV cache 长期累积 + 滑窗丢历史

- 实测 log：`n_past=3424, n_keep=82, n_ctx=8192` — 已用 41% ctx，但 n_keep 只保 system prompt 82 token
- 视频全双工每帧产生上千 vision token，**几分钟内** KV cache 就触发滑窗
- 滑窗只保 n_keep（82）部分，**用户对话历史 + 几秒前的视觉帧全被扔**
- 这解释了补充反馈"说的是上一个画面"——KV 里残留的旧视觉 token 与新帧混杂

### ⚠️ 3. system prompt 是默认的（C2 prompt override 受 fast_resume 限制）

- 当前 prompt：`Streaming Duplex Conversation! You are a helpful assistant.`（没有"桌面陪伴"特化引导）
- 路线 C2 的 voice_clone_prompt 字段虽链路通，但 cpp_server 启动后 warmup 已 init，后续 fast_resume 不重设 prompt
- 修复路径：cpp_server.py 启动参数加 `--system-prompt` 或环境变量 `SYSTEM_PROMPT`，启动时一次性设入

### ⚠️ 4. 9B 模型本身上限

- MiniCPM-o 4.5 = 9B 参数（OpenCompass 视觉均分 77.6，超 GPT-4o 但远逊大模型）
- 即使 F16 + 完美 prompt + 充裕 ctx，文本智能仍有天花板
- 这是不可逾越的硬限制

## 行动项

1. ✅ **立即切 F16**（已做，12:22 重启完成）— 用户应该感知到智能明显提升
2. ⏳ 增大 `ctx_size` 8192→16384 或 32768（GB10 unified 装得下，但要看 llama-server 是否支持）
3. ⏳ 增大 `n_keep`：保留 system + 最近 1-2 轮对话，避免滑窗过激
4. ⏳ 把"陪伴 prompt"通过 cpp_server.py 启动参数注入（绕开 fast_resume）
5. ⏳ 修 oneclick.sh：`LLM_QUANT` → 自动转 `LLM_MODEL` 透传给 cpp_server

## 用户回测前后对比指引

切换 Q4_K_M → F16 后请用户重测以下 case：

- ✅ 长描述：让 AI 描述一个网页（应输出 5-10 句具体内容，而非 2-3 句废话）
- ✅ 指认：鼠标指元素问"这是什么"（视觉延迟应改善）
- ✅ 多轮：连续问 3-5 个问题（早期问题被记住吗？还是答非所问？）

如果 F16 仍智能差，问题就在 prompt + ctx_size 上，不在量化。
