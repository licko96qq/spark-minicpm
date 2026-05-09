# 07 — MiniCPM-o-Demo-official 4 模式实测矩阵

> 任务 #18 P0：跑通所有模式并记录问题与成果。每个模式各填一格。
> 测试方法：浏览器访问对应 URL，按照「测试清单」每条做一次。

---

## 测试硬件 & 配置

- Spark GB10（aarch64, sm_120, unified memory 121GB）
- torch 2.11.0+cu130, transformers 4.51.0
- compile=true（torch_compile_cache 209MB）
- playback_delay_ms=1500
- attn_implementation: **sdpa**（flash_attention_2 编译中，待启用）

---

## 模式 1 · Turn-based Chat（`/`）

**架构**：按钮触发，文本+音频+视频输入 → 文本+音频输出

**测试清单**：
- [ ] 文本输入「你好，今天天气怎么样？」→ 音频回复
- [ ] 上传一张图片 → 描述
- [ ] 上传 30s 视频 → 描述
- [ ] 长对话（10 轮）→ 是否触发 KV 上限
- [ ] 切换 ref audio → 音色变化

**实测结果**：（待填）

**问题**：（待填）

---

## 模式 2 · Half-Duplex Audio（`/half_duplex`）

**架构**：VAD 自动检测语音边界，自动开闭 mic

**测试清单**：
- [ ] 语音输入「介绍一下你自己」→ 流畅回复
- [ ] 连续对话 10 轮，无明显延迟
- [ ] 长时对话 5 分钟以上不触发 KV 上限
- [ ] VAD 是否漏检/误检

**实测结果**：（待填）

**问题**：（待填）

---

## 模式 3 · Omni Full-Duplex（`/omni`）

**架构**：视觉+音频实时全双工，模型自主决定何时说话

**测试清单**（GB10 已知卡顿，重点记录改善幅度）：
- [ ] **戴耳机**测试基础语音对话流畅度
- [ ] 视觉问答：摄像头对桌面物品提问
- [ ] 实时打断：模型说话时插话（已知不支持，作为对照）
- [ ] 单步延迟（log: prefill total + generate total）
- [ ] 「Ahead」「Shift」面板数字对比

**实测基线（sdpa + compile）**：
- 单步：1.17s
- omni 严重卡顿（用户实测）

**flash-attn 后实测**：（待填，预期 1.0-1.1s，可能仍卡）

**问题**：（待填）

---

## 模式 4 · Audio Full-Duplex（`/audio_duplex`）

**架构**：音频实时全双工，无视觉，可打断（理论上）

**实测基线**：用户已实测「几乎不卡顿」

**测试清单**：
- [ ] 长对话 5 分钟+ 流畅度
- [ ] 实时打断（已知 4.5 不支持，作为对照）
- [ ] Ahead/Shift 数字对比 omni
- [ ] 噪声环境下 VAD 表现

**实测结果**：（待填）

**问题**：（待填，已知打断不支持）

---

## 总结表（最后填）

| 模式 | 流畅度 | 延迟 | 打断 | KV 限制 | 推荐场景 |
|---|---|---|---|---|---|
| Turn-based | TBD | TBD | N/A | TBD | TBD |
| Half-Duplex | TBD | TBD | N/A | TBD | TBD |
| Omni Full-Duplex | TBD | TBD | ❌ | 8K → 2min | demo only |
| Audio Full-Duplex | TBD | TBD | ❌ | TBD | TBD |
