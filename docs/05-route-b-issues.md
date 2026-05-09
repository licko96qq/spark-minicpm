# 05 — 路线 B 问题集（实测记录）

> 持续更新。每条问题包含：复现/现象、根因（如已知）、当前状态、应对。
> 部署：`spark_704:/home/LChuang/workspace/MiniCPM-o-Demo-official/` 官方 demo + GB10 单卡

---

## P0 · Omni Full-Duplex 严重卡顿，开 compile + buffer 1500ms 仍未解决

**最新实测（2026-05-09 14:00 buffer=1500ms）**：用户实测「效果一般」，仍卡顿
- buffer 拉到 1500ms 也无法掩盖结构性单步 1.17s 超阈值
- 正在等 flash-attn 2.8.x 编译完（sm_120 only，预估 30-50 min 完成）
- 即使 flash-attn 成功，5-15% 加速也只能从 1.17s 降到 ~1.0s，仍可能边缘卡顿



**测试时间**：2026-05-09 ~13:20

**现象**：
- 用户对模型说话，模型回答过程中**说一段卡一下、说一段卡一下**反复
- 调 `playback_delay_ms` 200 → 1000：开头几秒缓解，后面问题再次出现
- compile 模式（precompile.py 跑成功，cache 209MB，单步 ~1.17s）下仍卡
- 对比：**Audio Full-Duplex 几乎无卡顿，或非常轻微**

**根因**（已确认 + 实测验证）：
- 官方 README 明文：A100/4090 上 omni 单步 ~0.9s 即触发卡顿；compile 优化后 ~0.5s 流畅
- 实测 GB10 单步 ≥1.17s（即使 compile 开启），始终超过 1s 实时阈值
- GB10 LPDDR5X 内存带宽 ~273 GB/s = A100 HBM3e 14%，**结构性瓶颈**
- Issue #3 作者确认：硬件越弱卡越严重，RTX PRO 6000 (Blackwell sm_120) 是 0.4s 流畅，A100 0.7s 临界，GB10 是 A100 的更弱版本

**为什么 audio_duplex 不卡顿**：
- audio_duplex 不需要每秒同时跑视觉编码（vis_proc + vis_emb + vis_feed）
- log 显示 prefill 部分 vision 占 ~300ms，移除视觉链路后单步 < 1s 可达
- audio_duplex 在 GB10 上是「能用」状态

**已尝试**：
- ✅ `playback_delay_ms` 200 → 800 → 1000：缓解开头但中段失效
- ✅ `torch.compile` 开启 + precompile 完成（Triton 在 GB10 sm_100 工作正常，单步从 ~1.5s 降到 1.17s）
- ❌ 仍卡（GB10 物理瓶颈）

**当前状态**：**不可用 omni 模式**做长时间对话，结构性问题，硬件不达标

**应对方案**（按优先级）：
1. **接受现实**：长时间对话用 audio_duplex 或 half_duplex，omni 仅做短期 demo
2. **后续可试**：Flash Attention 2（5-15% 加速，可能仍不够）
3. **架构层**：等官方下一代 0.5s unit 架构（Issue #3 作者承诺路线图）
4. **换硬件**：RTX PRO 6000 / 单卡 A100 / H100 之类

---

## P1 · 实时打断功能不响应（Omni + Audio Duplex）

**测试时间**：2026-05-09 ~13:25

**现象**：
- 视频全双工（omni）：戴耳机后仍**无法打断模型**
- 音频全双工（audio_duplex）：戴耳机后**也无法打断**
- 模型自己回答："该版本现在不支持实时打断"

**复现条件**：
- ✅ 戴耳机（mic 与 speaker 物理分离，排除回声干扰）
- ✅ 用户主动语音说话试图打断
- ❌ 模型继续回答到底，对用户语音无反应

**根因**（待官方确认）：
- 用户实测 + 模型自述都指向「当前版本不支持」
- 跟 Issue #5 描述吻合：bokesyo 当时给 SuperiorDtj 回复说「audio_duplex experimental，omni 打断更可靠」，但用户实测都不工作

**已尝试**：
- ✅ 戴耳机（按 Issue #5 官方建议）
- ✅ omni 和 audio 两种模式都试

**当前状态**：**官方确认 = PARTIALLY / EXPERIMENTAL，4.5 版本未修复**

**官方明文证据**（已查证）：

1. **README 第 344 行**（main 分支最新）：
   > "In Audio Full-Duplex mode, echo cancellation currently has issues affecting interruption success rate. Using headphones is recommended. **A fix is coming soon.**"
   2026-05-09 仍未兑现。

2. **Issue #5**（open，bokesyo 原话）：
   - "`Audio Full-Duplex` mode is **experimental for MiniCPM-o 4.5, and was not optimized too much**"
   - "In `Omni Duplex`, the interruption is **more reliable**"（注意是 more reliable，不是 reliable）
   - 修复方案：等下一代模型 training data augmentation
   - https://github.com/OpenBMB/MiniCPM-o-Demo/issues/5

3. **主仓库 Issue #843**（closed）：bokesyo 定性为"model robustness problem"，承诺 "enhancement is expected in the next version"
   - https://github.com/OpenBMB/MiniCPM-o/issues/843

4. **Commit 历史**：Issue #5 之后**无打断相关修复**，README 的 "fix coming soon" 至今未兑现

**应对**：
- 4.5 版本不要把"实时打断"作为核心卖点
- 短期方案：用 Half-Duplex（README 第 41 行）+ 外部 VAD + 强制 cancel generation 绕开
- 长期：等下一代模型

---

## 已解决的问题（reference）

### ✅ TorchCodec missing
- 现象：`Failed: TorchCodec is required for load_with_torchcodec`
- 解决：`pip install torchcodec` (0.11.1+cu130 cp310 aarch64 wheel 可用)

### ✅ 没声音
- 现象：服务端推理正常，浏览器收到 0x10 PCM 但不出声
- 根因：AudioContext autoplay policy + Float32Array 字节对齐
- 解决：`await ctx.resume()` + 复制对齐 ArrayBuffer
- 详见 docs/03-pitfalls.md

### ✅ KV cache 8258 自动停（auto-stopping）
- 现象：omni 模式 ~2 分钟后触发上限
- 根因：demo 硬编码 8192 上限，模型架构 max_position_embeddings 实际是 32768
- 解决方案（待执行）：方案 B Rolling Context + 外挂摘要

### ✅ PyTorch 2.8.0 aarch64 是 CPU-only
- 解决：用现有 minicpm conda env（torch 2.7.1+cu128 → 升 2.11.0+cu130 with CUDA），symlink `.venv/base`

### ✅ torchvision::nms 不存在
- 现象：accelerate 1.12 升级 torch 到 2.11，但 torchvision 0.22.1 没跟上
- 解决：`pip install torchvision>=0.26.0 torchaudio>=2.11.0` 三家对齐
