# 02 — 相对 mgi 原版的改动详解

mgi 学生版 `/home/mgi/minicpm/webrtc_demo/` 设计为 spark 本机接外设（USB 麦克风+扬声器+Orbbec 深度相机）的「瘦客户端」模式：浏览器只显示文字和发摄像头帧，所有音频 IO 都在服务端。

为了让 Mac 远程使用 spark 算力，做了如下改造（不动 mgi 原版，新建到 LChuang 用户下）。

## server.py（449 行 → 267 行）

### 删除

| 原 | 行数 | 删除原因 |
|---|---|---|
| `import sounddevice` 相关 | 通篇 | 服务端不再做音频 IO |
| `_mic_capture_thread()` | 140-207 | 不再服务端采集麦克风 |
| `_tts_playback_thread()` + `_tts_queue` | 85-138, 81-83 | 不再服务端播放 TTS |
| `import orbbec_camera` + `start/stop/get_frames` | 44, 242, 247, 402-407, 423-424 | 改用浏览器 getUserMedia(video) |
| `preview_sender()` (0x04 推送 Orbbec 帧) | 394-412 | 浏览器自己显示本地摄像头预览 |
| 顶层 mic/speaker 配置 | 56-62 | client-side 模式无需 |

### 新增

| 新增 | 位置 | 用途 |
|---|---|---|
| `0x01` 二进制接收分支 | message_receiver | 解析 client 上传的 PCM → VADProcessor.feed() |
| 每连接 `vad: VADProcessor` | WS handler | 替代原来的全局单例（学生版只支持一个麦克风线程） |
| `_inference_busy` 全局标志 | on_status 回调 | processing/speaking 状态丢弃上行 PCM 防回声 |

### 保留

- `inference_coordinator` 流程
- `run_inference` 调用、TTS 0x10 下行
- 0x02 JPEG 接收（学生版本就支持，只是前端没发）
- PTT 模式（浏览器侧累积 PCM 缓冲，server 收到 `ptt_stop` 后从 buffer 取）

## frontend/index.html（353 行 → 456 行）

### 删除

| 原 | 删除原因 |
|---|---|
| `cameraPreview` 用 `<img>` 显示 0x04 服务端推送 | 改用 `<video>` 显示本地 getUserMedia |
| `📷 麦克风由服务端采集` 提示文案 | 已不再如此 |
| 0x04 PREVIEW 处理分支 | 服务端不再推 |

### 新增

| 新增 | 行数估计 | 用途 |
|---|---|---|
| `getUserMedia({audio,video})` 请求 | ~30 | 用户手势内调用 |
| `AudioWorklet` PCMUploader | ~40 | 48k→16k 线性插值，每 320 sample 一帧发 0x01 |
| Canvas JPEG 抓取定时器 | ~25 | 每秒抓 1 帧 → toBlob → 0x02 上行 |
| `await ttsCtx.resume()` | 1 | 解锁 autoplay policy |
| Float32Array 字节对齐复制 | ~5 | 修 RangeError |
| 摄像头开关 checkbox | ~10 | 视觉问答可关 |
| Console TTS chunk 计数日志 | ~5 | 排错用 |

### 保留

- 0x10 TTS PCM 接收 + AudioBufferSourceNode 调度
- 状态点 / 对话记录 UI
- VAD/PTT 模式切换 + 空格键 PTT
- 0x03 控制消息封装

## deploy/config.yaml

学生版只配麦克风/扬声器/摄像头设备号；新版改为：

```yaml
paths:
  model_dir:  /home/LChuang/workspace/minicpm/MiniCPM-o-4_5
  ref_audio:  /home/LChuang/workspace/minicpm/MiniCPM-o-4_5/assets/HT_ref_audio.wav

service:
  host: 127.0.0.1   # 强制 SSH tunnel，避免 LAN 暴露
  port: 8765

inference:  # 全部沿用默认值，显式写出便于调整
  max_new_tokens: 200
  max_video_frames: 8
  tts_rate: 24000
  mic_rate: 16000
  chunk_size: 16000

conda:
  base: /home/LChuang/miniconda3
  env_name: minicpm
```

## 未改动的文件

- `inference_engine.py` — 完全复用，模型加载/推理逻辑不变
- `audio_utils.py` — VADProcessor 直接拿来用，移到服务端处理上传 PCM 即可

## 量化总结

| 项 | mgi 版 | 新版 | 变化 |
|---|---|---|---|
| server.py | 449 行 | 267 行 | -40% |
| frontend/index.html | 353 行 | 456 行 | +29% |
| 服务端依赖 sounddevice/orbbec | 是 | 否 | 部署更轻 |
| 浏览器需要麦克风权限 | 否 | 是 | 用户体验变化 |
| 网络模型 | 同机外设 | 远程算力 | 核心变化 |
