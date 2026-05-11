# spark-minicpm — 会话交接

> 最后更新：2026-05-11 22:15 by Claude Code session（Phase A 归档完成 + Phase B 路线 D 自动 VAD 打断 CLI 验证通过）

---

## 🎯 当前进展（2026-05-11 22:15）

### Phase A: GitHub 归档（commit `adf6496`）

完成项：
- ✅ 目录重组：`routes/{b-cpp,c,d}/` 三主线、`archive/route-a/` 历史快照
- ✅ patches/0001-screen-share-companion-mode.patch（B-cpp commit 596d1af 导出）
- ✅ docs 新增 14（路线对比） / 15（4090-5090 迁移） / 16（故障排查）
- ✅ scripts 新增 download-models.sh / build-llama-cpp-omni.sh / apply-patches.sh / ssh-setup.md
- ✅ README.md 10 section 完整重写 + LICENSE (Apache 2.0)
- ✅ 路线 README × 4 + patches/README × 3

待用户操作：在 GitHub 建空仓 `spark-minicpm`，然后我 `git remote add origin` + `git push`。

### Phase B: 路线 D 自动 VAD 打断（spark commit `6690d01`，route-d 分支）

完成项：
- ✅ `cp -r MiniCPM-o-Demo-Comni MiniCPM-o-Demo-D` + 切 route-d 分支
- ✅ 端口避让：gateway 8050 / worker 22450 / llama 19090（与 B-cpp 19080、C 19060 共存）
- ✅ `core/vad/silero_vad.py` 新建：16kHz float32 PCM 输入，1024-sample 滑窗，单 VAD 简化版（路线 C 是 dual VAD，D 用单 VAD 足够）
- ✅ `worker.py` 集成：duplex_ws audio_chunk 处理时检测 prob > 0.5 → 覆盖 `chunk_force_listen = True`
- ✅ `.venv` symlink 共享 Comni 依赖 + onnxruntime 1.23.2 装好
- ✅ `silero_vad.onnx` 从路线 C 复制（1.8 MB，up.sh 自动处理）

CLI 端到端验证（`/tmp/test_d_silence.py`）：
- ✅ user_audio 11.34s 期间：VAD prob 0.6-0.99 持续触发 → 模型 LISTEN 不抢话
- ✅ 用户停顿后：VAD 不触发 → 模型 SPEAK 出 `"我错了，再也不敢了。"` + 3 个 audio_only msgs (~4s 音频)
- ✅ 静音 prob < 0.05（noise floor 不误触发）
- ✅ 与路线 C 同时跑（2× Q4_K_M 共 ~10G unified mem）

待用户验证：浏览器实测「模型 SPEAK 中开口能否在 < 300ms 内自动打断」。

**启动方式**：`bash routes/d/up.sh [F16|Q8_0|Q4_K_M]`，默认 Q4_K_M。

---

> （历史记录见下方）

---

## ✅ 2026-05-11 16:05 修复进展（接续）

### 真根因（不是 HANDOVER 之前猜的方向）

前端 `static/omni/omni-app.js` 和 `static/audio-duplex/audio-duplex-app.js` 构造 `preparePayload.config` 时**只传 `length_penalty`**，没有传 `listen_prob_scale` / `force_listen_count`。后端因此用 DuplexConfig 默认值（`lps=1.0, flc=3`），F16 模型在该 sampling 分布下**永远输出 LISTEN**，永远不 SPEAK。

### 诊断证据

`/tmp/test_duplex_v6.py`（接 `audio_only` 异步消息流）对比：
- `lps=1.0 flc=3`（默认）：23 chunks 全 LISTEN, 0 audio_only msg, text 为空
- `lps=0.3 flc=0`：c12 起开始 SPEAK, 3 个 audio_only msgs(共 348160 base64 chars ≈ 4s 音频), text=`"我错了，再也不敢了，下次我一定一定会下单的。"`

### audio 流向（之前被误解）

C++ duplex 模式的音频**不走** `result.audio_data`，走独立 WS 消息：
```json
{"type": "audio_only", "audio_data": "..."}
```
由 `worker.py:_wav_poll_loop()` 异步轮询 `cpp_backend._collect_wav_output_nowait()` 推送（worker.py:2499）。

### 已应用修复

| 文件 | 改动 |
|---|---|
| `static/omni/omni-app.js:1591` | preparePayload.config 增加 `listen_prob_scale: 0.3, force_listen_count: 0` |
| `static/audio-duplex/audio-duplex-app.js:958` | 同上 |

备份：`*.bak-20260511`

`cpp_backend.py` 的 patch 已回滚（多余且无效，因为音频不走 result.audio_data）。

### 服务状态

`http://localhost:8040/` HTTP，worker 22440 idle, llama-server 19080 ok, SSH tunnel 已建。

### 2026-05-11 16:55 追加修复（用户实测反馈）

用户测试发现：
1. ✅ 能用，但**回复卡顿**（F16 + GB10 内存带宽 14% A100 的结构性瓶颈）
2. ❌ 49s 后 KV 滑窗触发 → `Stop on KV pruning` 复选框勾着导致自动停止

修复：
- `config.json`: F16.gguf → **Q8_0.gguf**（8.2G，路线 C2 验证甜点档）
- `static/omni/omni.html:219`: `<input ... id="stopOnKvShrink" checked>` → 去掉 `checked`
- 需要重启路线 B-cpp 服务加载 Q8 模型

### 2026-05-11 17:45 追加诊断（用户问"语音无法打断"）

**真相**：Comni 分支**没有"开口自动打断"功能**。worker.py:2120 注释明确：
> Client 在 audio_chunk 中携带 force_listen: true → **强制模型持续监听（替代旧 interrupt）**

实现机制：前端 Force Listen 按钮 toggle `forceListenActive`，激活时 audio_chunk 自动带 `force_listen: true`，模型立刻切回 listen。这是**手动按钮**，不是自动 VAD。

用户期望的是「开口模型自动停」，这需要前端加 VAD 自动 toggle force_listen。属于功能增强，不是 bug。

**lps 调参实测**（重要）：
- lps=0.3 + flc=0 → speak ✅（c12 起，3 个 audio_only msgs）
- lps=0.4/0.5/0.6 + flc=0 → 完全不 speak ❌（临界点很尖）
- lps=1.0 + flc=3（默认）→ 完全不 speak ❌

也就是说 **lps=0.3 是唯一稳定可用值**，调高反而失败。这反映 F16/Q8 模型的 sampling 分布有 cliff，可能与 logits 缩放方式有关。

**Session 包**：用户已下载 `session_uploads/session_20260511_173451_omni_mp109scs.tar.gz`（44MB），含 frontend_replay.webm + merged_replay.mp4/wav + meta.json + recording.json，准备发给官方排查。

### 2026-05-11 17:55 追加问题（用户反馈）

**Q8 + 视频全双工 + 「高清视频」开关 → 明显卡顿**

- 复现：omni 模式跑 Q8，对话中勾选「高清视觉 64 tok」（HD slices）→ 回答与回复卡顿肉眼可见
- 关联：max_slice_nums 从 1 升到 3 时每帧视觉 token 从 64 → 256+，prefill 单步推理 +100ms 量级（agent 调研数据）
- 临时建议：屏幕共享/陪伴模式下**默认关闭高清视觉**，1 slice 已够识别屏幕元素
- 待办：考虑前端把「高清视觉」与「屏幕共享模式」互斥；或在勾选高清时弹警告

### 📋 待办（TODO）

- [ ] **评估 FlagOS 优化版**：https://modelscope.cn/models/FlagRelease/MiniCPM-o-4.5-nvidia-FlagOS — 看 4090/5090 上能否用这个 NVIDIA 优化版本替代 llama.cpp-omni（可能是 vLLM/TRT-LLM/SGLang），如果可用可能性能更好
- [ ] 路线 D 的 VAD 移植 + 4090/5090 实测
- [ ] B-cpp 在 4090（24G VRAM）上跑 Q4_K_M 验证可行性

---

### 2026-05-11 18:30 屏幕共享陪伴模式上线（A 方案阶段 1）

新增功能：omni 模式顶部加「屏幕共享」按钮，点击切换 摄像头 ↔ 屏幕共享 (`getDisplayMedia`)，自动应用陪伴策略。

**修改文件**：
- `static/omni/omni.html` 加 `screenShareBtn`（屏幕图标）
- `static/omni/omni-app.js` 加 `_videoSource` 状态、`_openVideoStream` screen 分支、`switchVideoSource()` 方法、帧率节流（屏幕模式 0.5 fps）、prepare payload 自动注入陪伴 prompt + 强制 max_slice_nums=1 + 自动关 HD
- 备份：`*.bak-screen-share-20260511`

**踩过的坑**：
1. Python 写 JS 时不小心把字符串引号 `"` 写成中文 typographic `"`，`node --check` 通过但运行时报 ReferenceError 整个 module 加载失败 → fix_quotes.py 修复
2. `screenShareBtn` visibility 跟随 camFlipBtn paired/lone 两种 pattern

**陪伴 prompt 几次迭代**：
- v1（草案）：长篇陪伴分析师 prompt（"沉默观察"等条款）→ **用户反馈太能说**
- v2（当前）：直接用官网默认 prompt（"扮演一个具有以上声音特征的助手..."）

**模型档位实测**（用户偏好）：
- F16：智能高但 GB10 带宽吃满，卡顿明显
- **Q8_0**：甜点档，路线 C2 / 用户验证可用
- Q4_K_M：4.7G 极致流畅，智能水平肉眼降，用作流畅性 baseline

**打断功能现状**：
- 手动：底部「强制收听」按钮（force_listen=true）
- 自动 VAD：**未实现**（路线 C 是后端 dur_vad_full ≥ 0.85 检测，需要移植 silero-vad 或前端 RMS）
- 决策：用户暂搁置，先用手动按钮

### 下一步（用户操作）

刷新浏览器，进 omni / audio duplex tab，说话，预期：
- 文字字幕出现
- 模型语音回复（拼接 `audio_only` 消息播放）

### 如果浏览器还不响应

按以下顺序排查：
1. F12 控制台看 WS 消息是否真有 `audio_only`
2. AudioPlayer 是否消费 `audio_only`（grep `audio_only` in `static/omni/`, `static/duplex/lib/`）
3. 试 `lps=0.2 flc=0` 进一步压低 listen 偏好
4. 看 `tmp/worker_0.log` 看后端是否真在 SPEAK

### CLI 验证脚本（永久保留）

```bash
ssh spark_704 'cd /home/LChuang/workspace/MiniCPM-o-Demo-Comni && .venv/base/bin/python /tmp/test_duplex_v6.py 0.3 0'
```
预期看到 `speak>=2, audio_only_msgs>=1, TEXT 非空`。

---

## 历史 ACTIVE（已解，留作记录）

---

## 🚧 ACTIVE：路线 B-cpp 4 模式 demo（2026-05-11 15:05）

### 用户最终请求
> "我说话，它现在没有任何的反应，也没有消息出来。一直问'你好在吗'没反馈。希望全局规划、考虑、测试，确认通过了再给我。我先去休息。"

### 任务目标（下一次会话要完成）
让浏览器打开 http://localhost:8040/ → 视频全双工/音频双工 tab → 说话 → 模型有文字+语音回复。

### 当前状态（已修复部分）

✅ **依赖缺失修复完成** — 这是阻塞了启动的真根因，HANDOVER 之前的"实测启动成功"是误判（只验证了 health endpoint，没真点 4 模式按钮）。

`.venv/base` 里今天新装了：`soundfile`, `PyYAML`, `Pillow`, `librosa`, `websockets`（及其依赖：scipy/numba/numba 等）。

走完整 audio_chunk 处理路径不再抛 `ModuleNotFoundError`。

✅ **服务可启动且 worker idle** — `bash route-b-cpp-up.sh` 起来后：
- gateway 8040（**HTTP 不是 HTTPS**，start_all.sh `--http` 模式）✅
- worker 22440 ✅ status=idle, model_loaded=true
- llama-server 19080 ✅ ok, F16 ctx 8192
- SSH tunnel 已建（本机 8040 / 22440）

✅ **WebSocket 端到端走完** — 我用 `/tmp/test_duplex_v4.py`（已 scp 到 spark `/tmp/`）连 worker WS：
- prepare → `{type: "prepared"}` ✅
- audio_chunk（11.34s 官方 user_audio `tests/cases/common/user_audio/000_user_audio0.wav` + ref `BH-Ref-HT-F224-...wav`） → 每个 chunk 都收到 `{type: "result", is_listen: True, ...}` ✅
- worker 日志：`LISTEN t=N wall=277ms | prefill=72 generate=205ms kv=279` —— prefill + generate 全部跑了 ✅

### ❌ 未解决：模型一直 LISTEN 不 SPEAK

不管发什么音频（合成 sine、真人 ref audio 6s、官方 user_audio 11.34s），模型每个 chunk 返回 `is_listen=True` `text=""`，**完全不 speak**。

可能原因（按优先级）：
1. **F16 模型在此 ctx 下默认参数 sample 不出 speak token** — 路线 C2 用 Q8 + 不同 backend 跑通过，B-cpp 是 F16 + cpp backend 第一次端到端跑。可能 sampling distribution 对 listen_id 偏置太大
2. **DuplexConfig 没传** — 我 test 只传了 `{"temperature": 0.7, "top_p": 0.9, "top_k": 50}`，未传 `listen_prob_scale` / `force_listen_count` / `ls_mode`。默认 `force_listen_count=3` 前 3 chunks 强制 listen，但后面的也 listen
3. **decode_mode="sampling"** — 试试 `"greedy"`
4. **listen_prob_scale 默认 1.0**，调到 0.3-0.5 强制偏向 speak
5. **前端可能要发 turn-end / end_of_user_speech 信号** —— 看 docs 协议是否完整

### 下次会话第一步（明确指令）

**别再装依赖、别再重启服务**（已经齐了）。直接做以下尝试，每步独立验证：

#### Step 1 — 调 sampling 参数让 model speak
改 `/tmp/test_duplex_v4.py` 的 prepare 消息：
```python
await ws.send(json.dumps({
    "type": "prepare",
    "system_prompt": "You are a helpful assistant.",
    "ref_audio_base64": base64.b64encode(ref.tobytes()).decode(),
    "config": {
        "decode_mode": "greedy",
        "listen_prob_scale": 0.3,
        "force_listen_count": 0,
        "ls_mode": "explicit",
    },
}))
```
重跑 `.venv/base/bin/python /tmp/test_duplex_v4.py`。如果 speak>0 就找到方向了。

#### Step 2 — 切 Q8（如果 Step 1 没解决）
修改 `start_all.sh` 或 `config.json`，把 model 路径从 `MiniCPM-o-4_5-F16.gguf` 改成 Q8_0（路径在 `~/Documents/workspace/spark-minicpm/models/`，跟路线 C2 用的同一个）。重启服务后重跑测试。

#### Step 3 — 看官方 bench 测试是否过
```bash
ssh spark_704 'cd /home/LChuang/workspace/MiniCPM-o-Demo-Comni && .venv/base/bin/python tests/bench_duplex_ws.py'
```
注意它 hardcode worker ports 22400/22401，可能要改成 22440。如果官方 bench 也全 LISTEN，说明这个模型/backend 状态本就是 broken 的，不是我们配错。

#### Step 4 — 路径 4 比对（最后手段）
进路线 C2 调通用的 cpp_server（`MiniCPM-V-CookBook/demo/web_demo/WebRTC_Demo`），对比 sampling 参数差异。

### 关键文件指引
- Worker WS handler: `worker.py:2105 duplex_ws()`
- DuplexConfig schema 默认值: `core/schemas/duplex.py:146` (`force_listen_count=3`, `decode_mode="sampling"`, `listen_prob_scale=1.0`)
- C++ backend prepare: `core/processors/cpp_backend.py:1060 _call_update_session_config`
- 我的测试脚本：spark `/tmp/test_duplex_v{1,2,3,4}.py`（v4 是最完整版）

### Spark 端服务管理（不变）
```bash
# 本机
cd /Users/licko/Documents/workspace/cc_test/AllRealHub/spark-minicpm
bash route-b-cpp-up.sh    # 启 (会先停路线 C)
bash route-b-cpp-down.sh  # 停
# 注意：访问 http://localhost:8040/ (HTTP，不是 HTTPS)
```

### 不要重复踩的坑
- 不要重新装 `soundfile/PyYAML/Pillow/librosa/websockets` — 已装好
- 不要以为是"前端 timeout 太短" — 真根因是 worker 抛 ModuleNotFoundError 直接断 WS
- 不要在 .venv 之外的环境装（venv 路径：`/home/LChuang/workspace/MiniCPM-o-Demo-Comni/.venv/base/`）
- 切 Q8 时注意 ctx 不要超过 GGUF metadata（昨晚发现 16K 反而慢）

---

## 历史进度（路线 C2，仍可用）

> 最后更新：2026-05-11 14:10 by Claude Code session（路线 C2 调优 + 监控分析）

## 当前进度（2026-05-11 14:10）

**路线 C2 屏幕共享 + 陪伴 prompt 全链路打通 + 调优定型**：

- **当前配置（用户实测保留）**：Q8_0 + ctx 8192 + 短陪伴 prompt + n_keep 122
- 用户体感：流畅+智能好（Q8 是甜点档）
- 屏幕共享 ✅（localStorage.videoSource=screen 触发）
- 陪伴 prompt ✅（cpp_server.py warmup 注入 SYSTEM_PROMPT 环境变量绕开 fast_resume）

**3 个剩余问题（根因已定位 = 滑窗机制）**：

1. 周期性卡顿（~52s 一次）
2. 记忆突然丢失（滑窗 `freed 3934 tokens`）
3. 字幕有但语音停（滑窗 `TTS KV cleared` 把正在生成的 wav chunk 中断）

→ 根治需改 C++ 源码 `tools/omni/omni.cpp` 滑窗逻辑（不清 TTS KV / 等 turn 结束才滑窗），后续工作。

详见 `docs/11-user-feedback.md`、`docs/12-tuning-plan.md`、`docs/13-monitoring-tuning-results.md`。

24G GGUF 全套已 rsync 到本机 `~/Documents/workspace/spark-minicpm/models/`。

spark 端清理：删 `gguf-ms-test/` + `V-CookBook-main.zip`（残留），workspace 27G。

git 三层 baseline：
- 本机 spark-minicpm: commit `58104b3` snapshot
- spark MiniCPM-V-CookBook: baseline `5968457` → C2 patch `c489953`
- spark llama.cpp-omni: baseline `edef517` → gitignore patch `479cbc4`

### 路线 C 最新状态（2026-05-09 23:30）

| 服务 | PID | 端口 | 状态 |
|---|---|---|---|
| LiveKit Server | 322286 | 7880 | ✅ running |
| Backend (FastAPI) | 322328 | 8021 | ✅ healthy |
| C++ Inference | 322428 | 9060 / 9061 / 19060 | ✅ healthy, registered, **滑窗激活** |
| Frontend (Vue+Vite prod) | 322536 | 8088 (HTTPS) | ✅ HTTP 200 |

**滑窗证据**（cpp_server.log 23:26:19）：`[SW] system_prompt registered: preserve_length=82 (will be protected from sliding)` + duplex 三线程（LLM/TTS/T2W）就绪。这是**路线 B 没有的能力**，是路线 C 的核心价值。

### 用户访问方式（醒来直接用）

```bash
# 在 Mac 上建 SSH tunnel（5 个端口都要转发）
ssh -fN \
  -L 8088:localhost:8088 \
  -L 8021:localhost:8021 \
  -L 7880:localhost:7880 \
  -L 9060:localhost:9060 \
  -L 9061:localhost:9061 \
  spark_704

# 浏览器打开（首次接受自签证书）
open https://localhost:8088/
```

如果在同一局域网内可直连 `https://192.168.8.202:8088/`。

### 路线 B → 路线 C 选型决策

| 路线 | 后端 | 卡顿 | 滑窗 | 状态 |
|---|---|---|---|---|
| A | mgi 学生版 webrtc_demo (PyTorch) | TTFT 2.3s | ❌ | fallback 保留 |
| B | OpenBMB/MiniCPM-o-Demo (PyTorch+flash-attn) | 单步 ~1s 持续卡 | ❌ | 结构性瓶颈，弃 |
| **C** | **WebRTC_Demo + tc-mb/llama.cpp-omni feat/web-demo** | **待实测** | **✅** | **🎯 当前主线** |

选型依据（飞书群 21:35-21:44）：MiniCPM 团队成员魏弘量 + 蔡天驰明确推荐 llama.cpp-omni，理由是硬件门槛更低 + 实现 token2wav 滑窗（28 token input / 25 token stride）+ 子豪在 DGX Spark 上实测流畅。

### "Comni vs llama.cpp-omni" 概念厘清

- **`tc-mb/llama.cpp-omni`** 仓库 `feat/web-demo` 分支 = 我们用的 C++ 推理引擎
- **Comni** = 基于 llama.cpp-omni 打包的 Mac/Win 桌面 GUI 应用，与服务器无关
- **MiniCPM-o-Demo-Comni** = `OpenBMB/MiniCPM-o-Demo` 仓库 `Comni` 分支，是给 llama.cpp-omni 当 wrapper 的另一个 demo（gateway/worker/frontend），**不走这条线**，主线是 `OpenSQZ/MiniCPM-V-CookBook` 的 `WebRTC_Demo`

### 已完成

- **2026-05-09 23:30** **路线 C WebRTC_Demo + llama.cpp-omni 端到端跑通**（详见上方）— 4 服务全部 running，滑窗激活，KPI 待实测
- **2026-05-09 22:31~22:50** 前一会话产出（spark 上）：clone llama.cpp-omni（feat/web-demo tarball）、编 llama-server 二进制、下载 8.4G GGUF 全套
- **2026-05-09 15:50** flash_attention_2 启用 + 完整链路实测：服务起来（8006 + 22400 listening），用户实测 omni "比之前好一些但仍卡"，确认结构性瓶颈无解
- **2026-05-09 15:25** flash-attn 2.8.2 编译完成（sm_120 only，~90 min），enable_flash_attn.sh 自动改 config + 清 torch_compile_cache + 重 precompile 成功
- **2026-05-09 ~14:00** 路线 B 部署 + 4 模式 demo 跑通，发现 omni 单步 1.17s 卡顿、实时打断官方确认 4.5 不支持
- **2026-05-08** 路线 A 简化版跑通（spark `/home/LChuang/workspace/minicpm/`）：Mac 浏览器 → SSH tunnel → spark 全链路（TTFT 2.3s, 15-19 tok/s）

### 进行中 / 未完成

- **路线 C 5 分钟视频全双工 KPI 实测**（用户醒来后做）— 这是路线 C 立项的核心 KPI，必须实测确认无卡顿才能宣告"路线 C 成功"
- 路线 C 性能基线数据（TTFT/单步耗时/滑窗 stride 行为日志）记录到 `docs/07-mode-test-matrix.md`
- P0 4 模式实测矩阵 路线 B 列填充（低优先）

### 已知问题

- **omni 卡顿无解**：GB10 内存带宽 = A100 的 14%，README 明文 A100 0.9s 已会卡，GB10 数学上不达标（启用 flash-attn 后单步从 1.17s 估降到 ~1.0s，仍超阈值）
- **实时打断 4.5 版本不支持**：OpenBMB Issue #5 官方确认，README L344 "fix coming soon" 至今未兑现
- **KV 8192 demo 硬编码上限**：模型架构 max=32K，但 demo 不让改（Issue #876）

## 下一步行动（按优先级）

### 0. **建 SSH tunnel + Mac 浏览器 5 分钟视频全双工实测**（用户醒来第一件事）

```bash
# Mac 终端，一行起所有 tunnel
ssh -fN -L 8088:localhost:8088 -L 8021:localhost:8021 -L 7880:localhost:7880 -L 9060:localhost:9060 -L 9061:localhost:9061 spark_704
open https://localhost:8088/
```

**KPI**：连续视频对话 ≥ 5 分钟，无 "说一段卡一段"。如果 KPI 通过 → 路线 C 立项成功 → 可以转入业务接入。

**KPI 失败排查切入点**：
- 看 `tail -f /home/LChuang/.../WebRTC_Demo/.logs/cpp_server.log` 找 `[SW]` 滑窗触发证据 + 单步推理耗时
- 路线 B 单步 ~1s 持续卡，路线 C 应该明显改善

### 1. 服务管理（需要时）

```bash
# 状态
ssh spark_704 'cd ~/workspace/MiniCPM-V-CookBook/demo/web_demo/WebRTC_Demo && bash oneclick.sh status'
# 日志
ssh spark_704 'cd ~/workspace/MiniCPM-V-CookBook/demo/web_demo/WebRTC_Demo && bash oneclick.sh logs cpp'
# 停 / 重启
ssh spark_704 'cd ~/workspace/MiniCPM-V-CookBook/demo/web_demo/WebRTC_Demo && bash oneclick.sh stop'
```

或本地：`bash ~/Documents/workspace/cc_test/AllRealHub/spark-minicpm/route-c-up.sh` / `route-c-down.sh`（见下）

### 2. （旧）推进 WebRTC 路线 — 实际已通过路线 C 自带 LiveKit/WebRTC 完成，本项作废

3. **推进 WebRTC 路线**（用户优先级最高）历史记录

   待用户启动该任务时再开始。先决问题：
   - 是基于现有路线 A 简化版（已是 WebSocket，可平滑改 WebRTC）扩展，还是另起架构？
   - 是否同步保留官方 demo 的 4.5 模型推理后端，仅替换前端音频传输？

   建议第一步：调研 webrtc 候选方案对比 + 评估改造成本，1-2 小时内出方案再动手。

2. **可选：补全路线 B 实测矩阵**（低优先）

   ```bash
   # 启 spark 服务
   ssh spark_704 "cd /home/LChuang/workspace/MiniCPM-o-Demo-official && nohup bash launch.sh > /tmp/launch.log 2>&1 &"
   # 等 ~90s, 建隧道
   ssh -fN -L 8006:127.0.0.1:8006 spark_704
   # 浏览器测 4 模式，填 docs/07-mode-test-matrix.md
   ```

   预期结果：4 模式各自 TTFT/卡顿/可用性数据齐，作为 WebRTC 路线 baseline 对比。

3. **可选：更新 docs/05-route-b-issues.md 的 P0 结论**

   当前 P0 还停留在「等 flash-attn 编完」状态，应追加最终结论：「flash-attn + compile 启用后仍卡，路线 B 内部调优结束」。

## 最近 Session 记录

### 2026-05-10 00:20 Session（路线 C 跑通 + F16 切换）

**做了什么：**
- 解开"Comni vs llama.cpp-omni"概念混淆：Comni 是基于 llama.cpp-omni 的 GUI app；OpenBMB/MiniCPM-o-Demo 的 Comni 分支是 PyTorch demo 的 cpp 后端版（Demo-Comni 目录）；**主线选 OpenSQZ/MiniCPM-V-CookBook 的 WebRTC_Demo + tc-mb/llama.cpp-omni feat/web-demo**
- 复用前次会话 spark 上已有的 llama-server 二进制 + 8.4G GGUF Q4_K_M
- 跑 oneclick.sh start，踩三个坑全部解决：(1) livekit-server 装 /usr/local/bin 要 sudo → 手动装到 ~/.local/bin/；(2) pnpm 装到 ~/.npm-global/bin 不在脚本搜索路径 → 加 PATH 环境变量；(3) **pnpm 10+ ERR_PNPM_IGNORED_BUILDS 安全机制误判 build 失败** → 绕开 pnpm 直接 `node_modules/.bin/vite build` + 写 dist/.cpp_mode 让 oneclick 跳过 build
- 4 服务全部 running：LiveKit 7880 / Backend 8021 / cpp_server 9060/9061 / Frontend 8088（HTTPS 自签）
- 用户 Mac 浏览器实测：能用 + 不卡 + 字幕实时显示，但智能水平低（Q4_K_M 4-bit 量化 + 9B 上限）
- 飞书发地址给手机端测：`https://192.168.8.202:8088/`
- 切 F16：发现 spark 内存紧张（121G/121G，swap 吃 8G），原因 vLLM Qwen3.6-35B-A3B-FP8 容器占 73G + modelscope 在下 Nemotron-30B
- 用户授权停 vLLM `docker stop vllm-35b-a3b`，释放至 105G available
- 下 F16 GGUF 16G（hf-mirror 90 秒下完）+ `LLM_QUANT=F16` 重启 oneclick → 4 服务 healthy，滑窗激活，**用户实测「速度也很快」**

**关键决策：**
- 路线 C 主线 = WebRTC_Demo + llama.cpp-omni（不是 Demo-Comni），因为 WebRTC_Demo 直接面向视频全双工 + 自带 LiveKit + 完整 oneclick 编排
- F16 是 GGUF 路线天花板（≈ HF BF16 原始权重，几乎无损）；9B 文本智能上限固有，不是量化问题
- pnpm 10 IGNORED_BUILDS 不在项目级 .npmrc 解决，绕开走 vite 直接 build 最快

**注意事项 / 踩过的坑：**
- oneclick.sh 第一次跑会 sparse-clone 一份**嵌套** `WebRTC_Demo/WebRTC_Demo/` 子目录工作。手动 build 要去内层，不是外层 o45-frontend
- pnpm `verify-deps-before-run=never` 写 ~/.npmrc 也不生效——pnpm 10 的 IGNORED_BUILDS 检查独立于 verify-deps；唯一稳妥做法是绕开 pnpm 命令直接调 vite
- spark 上 vLLM 容器 + modelscope 下载会偷偷吃掉 70G+ unified memory 不释放，加载新 GGUF 前必须先 `docker ps` / `free -h` 看清楚
- DGX Spark unified memory 架构 `nvidia-smi` 显存读不出，看负载用 `free -h` 和 `tegrastats`

**修改文件：**
- spark：`~/workspace/MiniCPM-o-4_5-gguf/MiniCPM-o-4_5-F16.gguf` 新下 16G
- spark：`~/.local/bin/livekit-server` 1.9.11 安装
- spark：`~/.npmrc` 加 `verify-deps-before-run=never`（聊胜于无）
- spark：`~/workspace/MiniCPM-V-CookBook/demo/web_demo/WebRTC_Demo/WebRTC_Demo/o45-frontend/dist/` 手动 build
- spark：`~/workspace/MiniCPM-V-CookBook/demo/web_demo/WebRTC_Demo/o45-frontend/.npmrc` 加 verify-deps-before-run
- 本机：`spark-minicpm/HANDOVER.md`（本文件）、`spark-minicpm/docs/08-route-c-llama-cpp-omni.md`（新）、`spark-minicpm/route-c-up.sh`/`route-c-down.sh`（新）

---

### 2026-05-09 15:50 Session

**做了什么：**
- 验证 flash-attn 2.8.x 后台编译已完成（PID 133797 退出，`flash_attn.__version__` = `2.8.2`）
- 跑 `bash enable_flash_attn.sh`：自动改 `config.json` 的 `attn_implementation` → `flash_attention_2` + 清 `torch_compile_cache` + 重新 precompile（耗时 ~7 min，成功，写 cache 到 `./torch_compile_cache`）
- 跑 `bash launch.sh`（后台 nohup），等 ~60s 后 Worker PID 153867 在 22400 listening、Gateway 在 8006 listening、`/health` 返回 200
- 重建 Mac SSH tunnel：`ssh -fN -L 8006:127.0.0.1:8006 spark_704`
- 用户实测 omni "好一些但用到后面还是卡顿"
- 收尾停服务：`pkill -9 -f worker.py / launch.sh / gateway`，端口 8006/22400 清空，Mac 隧道关闭

**关键决策：**
- 选择 **退出 demo 内调优、转 WebRTC 路线**：flash-attn 已是 demo 框架内最后一档优化，启用后仍卡，符合「GB10 内存带宽 14% A100」的结构性预测。继续在 demo 内调（如改 KV 上限、buffer 再调）边际收益低、风险高，不如换架构。
- 干净停服务而非保留运行：用户明示先停，避免占内存

**注意事项 / 踩过的坑：**
- worker_0.log 路径在 `tmp/worker_0.log` 不在仓库根，找日志要去 `MiniCPM-o-Demo-official/tmp/`
- launch.sh 用 nohup + `&`，远程 ssh 调时 stdout 要重定向到 `/tmp/launch.log` 才能在 ssh 退出后存活
- precompile 阶段 worker 自带一个 warmup 推理（speak 出多段音频），输出节奏 ~1.2s/段，与真实交互单步耗时**不是同一回事**，不要拿这个当性能指标
- pkill 进程列表非常长（GB10 系统多核 + torch._inductor compile_worker 启 20 个），用 `pkill -9 -f worker.py` 比按 PID 干净

**修改文件（spark 端）：**
- `spark_704:/home/LChuang/workspace/MiniCPM-o-Demo-official/config.json` — `attn_implementation: flash_attention_2`（由 enable_flash_attn.sh 自动改）
- `spark_704:.../torch_compile_cache/` — 重新生成
- 本机：本 `HANDOVER.md`（其他 docs/ 未动）

---

### 2026-05-09 ~14:00 Session（前次，路线 B 部署）

**做了什么：**
- 在 spark `LChuang` 用户下部署 OpenBMB/MiniCPM-o-Demo-official，复用 mgi 模型权重（symlink）
- 跑通 4 模式 demo，发现 omni 严重卡顿
- 调研确认实时打断 4.5 不支持（Issue #5）、KV 8192 是 demo 硬编码（Issue #876）
- 启动 flash-attn 2.8.x 后台编译（FLASH_ATTN_CUDA_ARCHS=120）

**修改文件：**
- 创建 `docs/04-route-b-deployment-plan.md` / `05-route-b-issues.md` / `06-rollback-snapshots.md` / `07-mode-test-matrix.md`

---

### 2026-05-08 Session（路线 A 落地）

**做了什么：**
- 基于 mgi 学生版 webrtc_demo 改造出瘦客户端版本，部署到 LChuang 用户
- 删 sounddevice/扬声器/orbbec_camera 本地 IO，改纯 WebSocket 音频上下行
- Mac 浏览器 + getUserMedia + AudioWorklet 16kHz PCM 上传
- TTFT 2.3s, 15-19 tok/s

**踩过的坑：**
- AudioContext autoplay policy 需 `await resume()`
- `Float32Array(buf, 1)` 1 字节偏移非 4 对齐 → 必须先复制对齐

**修改文件：**
- `refactor-snapshot/server.py` + `refactor-snapshot/index.html`
- `docs/01-architecture.md` / `02-refactor-deltas.md` / `03-pitfalls.md`
- `scripts/start-spark-minicpm.sh` / `connect.sh` / `stop.sh`

## 关键文件索引

| 文件 | 说明 |
|------|------|
| `docs/01-architecture.md` | 路线 A 架构图（WebSocket wire protocol） |
| `docs/02-refactor-deltas.md` | 路线 A 改造细节（基于 mgi 原版的 diff） |
| `docs/03-pitfalls.md` | 路线 A 踩坑（autoplay / Float32Array 对齐） |
| `docs/04-route-b-deployment-plan.md` | 路线 B 部署规划 |
| `docs/05-route-b-issues.md` | 路线 B 问题集（omni 卡顿、打断不支持等） |
| `docs/06-rollback-snapshots.md` | 路线 B 回滚命令（如新版编炸用这个） |
| `docs/07-mode-test-matrix.md` | 4 模式实测矩阵模板（待填） |
| `refactor-snapshot/server.py` | 路线 A 服务端快照 267 行 |
| `refactor-snapshot/index.html` | 路线 A 前端快照 456 行 |
| `scripts/start-spark-minicpm.sh` | 路线 A 启动 |
| `route-a-up.sh` / `route-a-down.sh` | 路线 A 上/下线（含隧道） |

## 技术要点

### 部署位置

- **路线 A**：`spark_704:/home/LChuang/workspace/minicpm/`（学生瘦客户端改版）
- **路线 B**：`spark_704:/home/LChuang/workspace/MiniCPM-o-Demo-official/`（OpenBMB 官方 demo）
- **模型权重**：`spark_704:/home/LChuang/workspace/minicpm/MiniCPM-o-4_5`（路线 B 通过 symlink 复用）
- **conda env**：`/home/LChuang/miniconda3/envs/minicpm/`
- **mgi 原部署（不动）**：`spark_704:/home/mgi/minicpm/`

### 浏览器入口（路线 B）

`http://localhost:8006/{,/half_duplex,/omni,/audio_duplex,/admin,/docs}` — 走 SSH tunnel 视作 secure context，免 HTTPS 警告

### Mac 隧道

```bash
ssh -fN -L 8006:127.0.0.1:8006 spark_704
```

### 启停（路线 B）

```bash
# 启
ssh spark_704 "cd /home/LChuang/workspace/MiniCPM-o-Demo-official && nohup bash launch.sh > /tmp/launch.log 2>&1 &"
# 停
ssh spark_704 "pkill -9 -f worker.py; pkill -9 -f launch.sh; pkill -9 -f gateway"
```

### 硬件 baseline

GB10 (Blackwell sm_120, unified mem 121GB) — 内存带宽 = A100 的 14%，是 omni full-duplex 卡顿的结构性根因。Compute 够，带宽不够。

### 兄弟项目

- `~/Documents/workspace/spark-llm/`（llama-swap + Qwen 系列）
- `~/Documents/workspace/spark-vllm/`（vLLM Docker 实验）
