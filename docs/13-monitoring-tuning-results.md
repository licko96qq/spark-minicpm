# 13 - 路线 C2 监控数据 + 调优结果 + 滑窗根因

> 2026-05-11 13:00-14:10 实测数据汇总
> 用户场景：屏幕共享 + 文献阅读 + 网页浏览陪伴

## 最终落地配置（已生效）

```bash
LLM_MODEL=MiniCPM-o-4_5-Q8_0.gguf
CTX_SIZE=8192
SYSTEM_PROMPT="<|im_start|>system
Streaming Duplex Conversation! 你是用户的专业陪伴助手，看到屏幕（论文/网页/文档）后主动解读、翻译英文、补充专业背景（生物/AI/医学/自动化）。回答详细但紧扣当前画面，简单问题可简短回应。
<|audio_start|>"
```

用户实测："**Q8 挺流畅的，保留 Q8**"。

## 关键改动（spark + 本机）

| 文件 | 改动 |
|---|---|
| `cpp_server/minicpmo_cpp_http_server.py:813` | warmup 读 `SYSTEM_PROMPT` 环境变量注入 `voice_clone_prompt`（绕开 fast_resume 限制） |
| 本机 `route-c-up.sh` | 默认 ctx=8192 + 短陪伴 prompt + 透传 CTX_SIZE / SYSTEM_PROMPT |

## 量化性能对比（实测）

| 量化 | 大小 | rounds/sec | prefill 单步 | CPU 峰 | 体感 |
|---|---|---|---|---|---|
| Q4_K_M | 4.7G | ~1.2 | 35-90ms | 36% | 流畅 |
| **Q8_0**（当前） | **8.1G** | **~0.56** | **50-200ms** | **47%** | **流畅+智能好** ✅ |
| F16 | 16G | ~0.2-0.3 | 200-400ms | (未测) | 卡顿明显 |

ctx 8K vs 16K 对比（Q4 测试）：
- 8K：n_past 上限 ~6144 触发滑窗，单步稳定
- **16K：n_past 涨到 10910，单步推理变慢**（注意力 KV 全量计算 ∝ n_past）

> ⚠️ **不要为"长记忆"贪心 ctx 16K** — GB10 上 attention 计算量随 n_past 线性增长，单步变慢比丢历史更影响体验

## 用户反馈的 3 个问题 + 根因

### 现象

1. **周期性卡顿**（每几十秒一次顿一下）
2. **记忆突然没了**（刚说的几句话 AI 不记得）
3. **字幕生成正常但语音突然停**

### 根因：**全是滑窗机制（slide window）副作用**

滑窗触发周期（Q8 + 8K ctx 实测）：~52 秒一次

```
14:06:02 → 14:07:19（77s）
14:07:19 → 14:08:13（54s）
14:08:13 → 14:09:05（52s）
14:09:05 → 14:09:57（52s）
```

每次滑窗 log（典型）：
```
⚠️ slide TRIGGERED: n_past=6085, chunk=64, trigger=6144, n_ctx=8192, n_keep=125, rounds=53
⚠️ slide DONE: n_past 6085→2151, freed 3934, boundaries_kept=19, TTS KV cleared
```

三个问题完全对应：
- **现象 1**：滑窗触发瞬间 prefill 加重（rounds 计数 reset）
- **现象 2**：`freed 3934` 把 ~20+ 轮对话历史扔掉了
- **现象 3**：**`TTS KV cleared` 是真凶** — TTS thread 正在生成 wav chunk 时被滑窗强制清 KV → wav 文件半途中断
  ```
  TTS: chunk file tts_output_chunk_94.wav does not exist or is empty
  TTS: chunk file tts_output_chunk_95.wav does not exist or is empty
  ...到 chunk_103.wav
  TTS: no valid WAV files to merge
  ```

## 优化方案（待决策）

| 方案 | 改动 | 效果 | 代价 |
|---|---|---|---|
| **A. ctx 8K → 16K** | env CTX_SIZE | 滑窗周期 ~104s（翻倍） | Q8 单步可能稍慢，但内存够 |
| **B. 改 C++ 源码：滑窗不清 TTS KV** | 改 `tools/omni/omni.cpp` 滑窗逻辑 + 重编 llama-server | 语音不会突然停 | 30 min 改+编 |
| **C. 改 C++ 源码：等 turn 结束才滑窗** | 同上 | 不打断语音 + 记忆更稳 | 30 min |
| **D. 接受现状** | 无 | 周期记忆 reset 仍存在 | 0 |

**推荐顺序：D（先用着）→ A（一行改可逆）→ B/C（根治需 PR 上游）**。

## 路线选择决策树

```
是否需要长时间陪伴对话（>1 分钟连续）？
├─ 是 → 推荐 B+C 改 C++ 源码（一劳永逸）
└─ 否（短问短答为主）→ Q8 当前配置已足够
```

## 监控命令（复用）

```bash
# 实时看滑窗触发
ssh spark_704 'tail -f .../webrtc_demo/.logs/cpp_server.log | grep "slide TRIGGERED\|TTS KV"'

# 实时 prefill 耗时
ssh spark_704 'tail -f .../cpp_server.log | grep "prefill done"'

# 监控 90s 收集数据
ssh spark_704 'tail -f .../cpp_server.log | grep -E "prefill|slide|round" > /tmp/mon.log' & sleep 90 && pkill -f "tail.*cpp_server"
```
