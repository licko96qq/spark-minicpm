# 16 — 故障排查（已知坑大全）

> 事实来源：HANDOVER.md 全量 session 记录 + docs/03-pitfalls.md + docs/05-route-b-issues.md
> 按主题分类，每条 = 现象 → 根因 → 修复

---

## 一、后端启动失败

### llama-server 启动超时

- **现象**：`bash route-b-cpp-up.sh` 卡住或超时，worker 起不来
- **排查**：`tail -f /tmp/route-b-cpp.log`；看 llama-server 有没有在 19080 listening
- **常见根因**：
  - GGUF 权重路径写错（`config.json` 里 model 字段）
  - 端口 19080 被旧进程占着 → `ss -lntp | grep 19080`
  - CUDA arch 编译不匹配目标 GPU（4090 需要 sm_89，GB10/5090 需要 sm_120）

### worker 抛 ModuleNotFoundError

- **现象**：WS 连接建立后首个 `audio_chunk` 就断
- **根因**（HANDOVER 2026-05-11 15:05）：`.venv/base` 缺依赖
- **修复**：
  ```bash
  .venv/base/bin/pip install soundfile PyYAML Pillow librosa websockets
  ```
- **注意**：必须装在 `.venv/base` 里，不是系统 Python

### conda env 走错

- **现象**：启动成功但推理报 torch CUDA 不可用
- **预防**：路线 A/B 明确 conda env 路径 `/home/LChuang/miniconda3/envs/minicpm/`；路线 B-cpp/C 用 `.venv/base`
- **GB10 注意**：aarch64 上 PyTorch 2.8.0 是 CPU-only wheel，必须装 2.11.0+cu130（路线 C 指定）

---

## 二、模型不 SPEAK（永远 LISTEN）

### 现象

- audio_chunk 发了，worker 日志显示 `LISTEN t=N wall=277ms | prefill=72 generate=205ms`，每个 chunk 都 `is_listen=True`、`text=""`
- 前端完全没文字没声音

### 根因

前端 `preparePayload.config` 只传 `length_penalty`，**没传** `listen_prob_scale` / `force_listen_count`，后端用 `DuplexConfig` 默认值 `lps=1.0 flc=3`，F16/Q8 模型在该分布下永远输出 LISTEN token。

### 修复

| 文件 | 改动 |
|---|---|
| `static/omni/omni-app.js:1591` | `preparePayload.config` 增加 `listen_prob_scale: 0.3, force_listen_count: 0` |
| `static/audio-duplex/audio-duplex-app.js:958` | 同上 |

### 参数窗口（实测，不可乱调）

| lps | flc | speak? |
|---|---|---|
| 1.0 | 3（默认） | ❌ 全 LISTEN |
| 0.3 | 0 | ✅ 稳定 SPEAK |
| 0.4 / 0.5 / 0.6 | 0 | ❌ 全 LISTEN |
| 0.2 | 0 | 待验证（可能 speak 过度） |

**结论**：`lps=0.3 flc=0` 是唯一稳定值。F16/Q8 的 sampling 分布有 cliff，调高反而失败。

### CLI 冒烟验证

```bash
ssh spark_704 'cd /home/LChuang/workspace/MiniCPM-o-Demo-Comni && .venv/base/bin/python /tmp/test_duplex_v6.py 0.3 0'
```
预期：`speak>=2, audio_only_msgs>=1, TEXT 非空`

---

## 三、自动停止（KV 滑窗触发）

- **现象**：对话约 49s 后自动结束，浏览器看到 `KV cache pruned (sliding window)` + `Stop on KV pruning enabled. Auto-stopping`
- **根因**：`omni.html:219` 的 `stopOnKvShrink` 复选框默认 `checked`
- **修复**：
  ```html
  <!-- before -->
  <input type="checkbox" id="stopOnKvShrink" checked>
  <!-- after -->
  <input type="checkbox" id="stopOnKvShrink">
  ```
- **进阶**：滑窗清 TTS KV 会中断正在生成的 wav chunk，根治需改 `tools/omni/omni.cpp` C++ 源码（见 docs/13-monitoring-tuning-results.md）

---

## 四、卡顿

### F16 + GB10 结构性卡顿

- **现象**：回复流式输出断断续续
- **根因**：GB10 LPDDR5X 内存带宽 ≈ A100 HBM3e 的 14%，omni 单步 ≥1.17s 超 1s 实时阈值
- **修复**：
  - 切 Q8_0（用户验证甜点档）
  - 极限流畅切 Q4_K_M（智能下降）
  - F16 仅在 5090 / A100 / H100 等独显机用

### HD 视觉 + 屏幕共享卡顿

- **现象**：omni 勾选「高清视觉 64 tok」后回复明显卡
- **根因**：`max_slice_nums` 从 1 升到 3 → 每帧视觉 token 64→256，prefill +100ms 量级
- **修复**：
  - 屏幕模式自动强制 `max_slice_nums=1` + 关 HD 开关（已在 `omni-app.js` 实现，见 HANDOVER 18:30）
  - 摄像头模式想开 HD 自己斟酌，1 slice 其实够识别屏幕元素

---

## 五、打断功能

- **B-cpp 当前（Comni 分支）**：手动按底部「强制收听」按钮 → `audio_chunk` 带 `force_listen=true`
- **C**：后端 `dur_vad_full ≥ 0.85` 自动 VAD 打断，开箱可用
- **B-cpp 想要自动打断**：Comni 分支**没有**自动 VAD，需要移植 silero-vad（路线 D 在做）
- **旧概念澄清**（HANDOVER 17:45）：worker.py:2120 注释明确 `force_listen: true` 是「强制模型持续监听（替代旧 interrupt）」，不是「打断当前 speak」

---

## 六、浏览器 console 错误

### "Cannot use import statement outside a module" + module 加载失败

- **现象**：`node --check` 通过，但浏览器运行时报 ReferenceError，整个 JS module 失效
- **根因**：JS 文件混入中文 typographic 引号 `“` `”`（Python 脚本批量改 JS 时常见）
- **修复**：用 `fix_quotes.py` 或正则把 `“` `”` 统一成 ASCII `"`；`'` `'` 同理
- **预防**：Python 写 JS 字符串时用 raw string + ASCII-only 断言

### AudioContext autoplay policy

- **现象**：spark log 完美、浏览器收到 PCM 帧但完全没声音
- **根因**：Chrome/Safari autoplay policy 要求 AudioContext 必须在用户手势同步栈内显式 resume
- **修复**：
  ```js
  ttsCtx = new AudioContext({ sampleRate: TTS_RATE });
  await ttsCtx.resume();
  ```
- **验证**：Console `[TTS] AudioContext ... state=running` 必须是 running 不是 suspended

### Float32Array 字节对齐 RangeError

- **现象**：`RangeError: start offset of Float32Array should be a multiple of 4`
- **根因**：wire protocol 1 字节 type prefix → `new Float32Array(buf, 1)` byteOffset=1 非 4 对齐
- **修复**：
  ```js
  const raw = new Uint8Array(buf, 1);
  const aligned = new ArrayBuffer(raw.byteLength);
  new Uint8Array(aligned).set(raw);
  const f32 = new Float32Array(aligned);
  ```
- **预防**：未来 wire protocol 设计用 4 字节头（type + 3 字节 reserved/length）

---

## 七、浏览器无声（但推理正常）

- **排查顺序**：
  1. F12 Network → WS → 有没有 `"type":"audio_only"` 消息（B-cpp 音频走这个通道，不走 `result.audio_data`）
  2. AudioPlayer 是否消费 `audio_only`：grep `audio_only` in `static/omni/`、`static/duplex/lib/`
  3. AudioContext state 是否 running（见上条）
  4. 后端确认：`tail tmp/worker_0.log` 看有没有真在 SPEAK
- **关键事实**（HANDOVER 16:05）：C++ duplex 的音频**不走** `result.audio_data`，由 `worker.py:_wav_poll_loop()` 异步轮询独立推送

---

## 八、启动脚本问题

### route-c-up.sh LLM_QUANT 不透传

- **现象**：指定 `LLM_QUANT=Q8_0` 但 cpp_server 起来还是加载 Q4_K_M
- **根因**：oneclick auto_detect 优先匹配到 Q4_K_M
- **修复**：改用 `LLM_MODEL=<完整文件名>`，如 `LLM_MODEL=MiniCPM-o-4_5-Q8_0.gguf`

### pnpm 10 ERR_PNPM_IGNORED_BUILDS

- **现象**：pnpm 10+ 安全机制误判 build 失败，前端起不来
- **修复**：绕开 pnpm 直接调 vite
  ```bash
  cd o45-frontend
  node_modules/.bin/vite build
  echo "cpp" > dist/.cpp_mode   # 让 oneclick 跳过 build
  ```
- **注意**：`.npmrc` 写 `verify-deps-before-run=never` 聊胜于无，IGNORED_BUILDS 独立于 verify-deps

### livekit-server 装 /usr/local/bin 要 sudo

- **修复**：装到 `~/.local/bin/livekit-server`，在脚本里 `export PATH=$HOME/.local/bin:$PATH`

### oneclick 嵌套目录

- **现象**：路线 C 首次 clone 后有 `WebRTC_Demo/WebRTC_Demo/` 两层
- **修复**：手动 build 要进**内层** `WebRTC_Demo/WebRTC_Demo/o45-frontend`，不是外层

---

## 九、权重和资源

### GB10 nvidia-smi 显存 N/A

- **现象**：`nvidia-smi --query-gpu=memory.used` 返回 `[N/A]`
- **根因**：unified memory 架构，CPU/GPU 共享内存池
- **替代**：用 `free -h` 和 `tegrastats`

### vLLM / modelscope 偷吃内存

- **现象**：GB10 上 vLLM Qwen 容器吃 73G + modelscope 下载吃 N G，新加 F16 权重直接 OOM
- **排查**：`docker ps` + `free -h` 必须双验证
- **修复**：加载大权重前 `docker stop vllm-XXX` 释放

### cert.pem 权限拒绝

- **现象**：从 `/home/mgi/minicpm/` 复制过来报 `Permission denied` for `key.pem`
- **修复**：白名单逐文件 cp，跳过 cert.pem/key.pem（SSH tunnel 方案根本不需要 HTTPS 证书）

### HT_ref_audio.wav 默认路径找不到

- **现象**：`config_loader` 默认 `paths.ref_audio = "assets/HT_ref_audio.wav"` 找不到
- **修复**：`config.yaml` 显式绝对路径 `/home/LChuang/workspace/minicpm/MiniCPM-o-4_5/assets/HT_ref_audio.wav`

---

## 十、未来可能踩的雷（预防）

- **多浏览器并发**：server.py 的 `_inference_busy` 是全局变量，同时开两个浏览器会互相串话。要多用户必须改 per-connection
- **TTS 回声进 ASR**：`_inference_busy` 状态切换有延迟，极小概率把 TTS 录回去触发新 inference。Client side 加 `_is_playing_tts` 标志屏蔽上行
- **模型加载 2 分钟**：每次重启要重新加载 18GB 权重。要上 systemd 长驻或 watchdog
- **KV 8192 demo 硬编码上限**：模型架构 max=32K，但 demo 不让改（Issue #876）。长对话方案 B Rolling Context + 外挂摘要
- **实时打断 4.5 版本不支持（Comni 分支）**：OpenBMB Issue #5 官方确认，README L344 "fix coming soon" 至今未兑现。想要立即可用的自动打断走路线 C

---

## 附：CLI 快速诊断

```bash
# 1. 服务存活
ssh spark_704 'ss -lntp | grep -E "8040|22440|19080"'

# 2. worker idle/busy
curl -s http://localhost:22440/health | jq

# 3. llama-server 健康
curl -s http://localhost:19080/health

# 4. 端到端 duplex 冒烟
ssh spark_704 'cd /home/LChuang/workspace/MiniCPM-o-Demo-Comni && .venv/base/bin/python /tmp/test_duplex_v6.py 0.3 0'

# 5. 看实时日志
ssh spark_704 'tail -f /tmp/route-b-cpp.log'
```
