# 01 — 架构与 Wire Protocol

## 数据流

```
┌─────────────────────────────────────────────┐         ┌──────────────────────────────────┐
│ Mac 浏览器 (http://localhost:8765/)         │         │ Spark uvicorn FastAPI            │
│                                             │         │   /home/LChuang/workspace/minicpm │
│  ┌──────────────┐                           │  WS     │                                  │
│  │ getUserMedia │── float32 PCM 16k → 0x01 ─┼─/ws ───→│  VADProcessor.feed()             │
│  │   (audio)    │                           │         │  → speech_queue                  │
│  └──────────────┘                           │         │  → run_inference()               │
│  ┌──────────────┐                           │         │  → MiniCPM-o 4.5 (GB10)          │
│  │ getUserMedia │── JPEG 1FPS → 0x02 ───────┼─────────→  prefill video + audio chunks    │
│  │   (video)    │                           │         │                                  │
│  └──────────────┘                           │         │  streaming_generate()            │
│  ┌──────────────┐                           │         │   ├─ text token  → JSON          │
│  │ AudioWorklet │← float32 PCM 24k ← 0x10 ──┼─────────┤   ├─ TTS chunk   → 0x10 bin      │
│  │   (TTS out)  │                           │         │   └─ status     → JSON           │
│  └──────────────┘                           │         │                                  │
└─────────────────────────────────────────────┘         └──────────────────────────────────┘
              ↑                                                    ↑
              │  ssh -L 8765:127.0.0.1:8765 spark_704              │  bind 127.0.0.1
              │  (天然 TLS 加密 + getUserMedia 在 localhost 视作 secure)
              └────────────────────────────────────────────────────┘
```

## Wire Protocol

每个 WebSocket 二进制消息首字节为 type，后续为 payload。

### 浏览器 → 服务端

| Type | Payload | 频率 | 说明 |
|---|---|---|---|
| `0x01` | float32 LE PCM | ~50 Hz (20ms 帧) | 麦克风音频，16kHz mono，已在 AudioWorklet 内重采样 |
| `0x02` | JPEG bytes | ~1 Hz | 摄像头帧，320×240，quality=0.6 |
| `0x03` | UTF-8 JSON | 事件触发 | `{action: start/stop/set_mode/ptt_start/ptt_stop/ping}` |

### 服务端 → 浏览器

| Type | Payload | 说明 |
|---|---|---|
| `0x10` | float32 LE PCM | TTS 音频，24kHz mono，流式分块下发 |
| (text) | JSON | `{type: ready/text/status/pong/stats}` |

## 关键文件路径

### Spark 端

| 文件 | 行数 | 说明 |
|---|---|---|
| `webrtc_demo/server.py` | 267 | FastAPI + WebSocket 服务，单连接设计 |
| `webrtc_demo/inference_engine.py` | 233 | 模型 singleton + 推理协程，**未改动** |
| `webrtc_demo/audio_utils.py` | 156 | VADProcessor + TTS 编码，**未改动** |
| `webrtc_demo/frontend/index.html` | 456 | 前端 UI + AudioWorklet + getUserMedia |
| `deploy/config.yaml` | — | 路径/端口配置 |

### 单连接全局状态（server.py）

- `_inference_busy` — 推理/说话期间为 True，丢弃上行 PCM 防回声
- 每个 WS 连接内部局部状态：`speech_queue` / `video_frames` / `vad: VADProcessor` / `ptt_*`

## 运行时行为

1. **冷启动**：uvicorn 起 → `lifespan` 调 `load_model()`（加载 4 个 safetensors 分片 + ref audio，~2 min）
2. **WS 连接**：浏览器连 `/ws` → 服务端发 `{type: ready}` → 前端按钮可点
3. **会话开始**：浏览器发 `0x03 {action: start}` → 状态切到 `listening`
4. **VAD 模式**：连续上行 PCM → `VADProcessor.feed()` 累积，检测到完整语音段（≥0.8s + 300ms 后置静音）→ 入队
5. **推理**：`inference_coordinator` 取队列 → 拼接 system + video frames + audio chunks → `streaming_generate` → 流式 TTS+text 下发
6. **PTT 模式**：浏览器按空格发 `ptt_start`/`ptt_stop`，期间 PCM 累积成段；放开后整段送推理

## 性能与限制

- TTFT 2.3s（GB10 unified memory，bfloat16，sdpa attn）
- 生成速度 15-19 tok/s
- 单连接：一个浏览器吃满 GPU
- max_video_frames=8（旧帧自动丢弃）
- max_new_tokens=200（避免回答过长）
