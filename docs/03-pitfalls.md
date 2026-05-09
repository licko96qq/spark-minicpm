# 03 — 已踩过的坑

## P0 · 浏览器没声音（autoplay policy）

**症状**：spark log 完美，inference 跑过 TTFT 2.3s 输出 16-189 tokens，浏览器收到了 0x10 PCM 帧但**完全没声音**。

**根因**：Chrome/Safari autoplay policy 要求 AudioContext 必须在用户手势同步栈内 **显式 resume**。即使 `new AudioContext()` 在 click 回调里创建，state 也可能是 `suspended`。

**修复**：
```js
ttsCtx = new AudioContext({ sampleRate: TTS_RATE });
await ttsCtx.resume();  // ← 必须！
```

**验证方式**：Console 看 `[TTS] AudioContext sampleRate=... state=running`，state 必须是 `running` 不是 `suspended`。

---

## P0 · Float32Array 字节对齐 RangeError

**症状**：浏览器 console 抛 `RangeError: start offset of Float32Array should be a multiple of 4`，TTS 静默不播。

**根因**：wire protocol 用 1 字节 type prefix → `new Float32Array(buf, 1)` 的 byteOffset=1 非 4 字节对齐，规范要求强制对齐。

**修复**：
```js
const raw = new Uint8Array(buf, 1);
const aligned = new ArrayBuffer(raw.byteLength);
new Uint8Array(aligned).set(raw);
const f32 = new Float32Array(aligned);
```

**预防**：未来 wire protocol 设计直接用 4 字节头（type + 3 字节 reserved/length），这样 payload 天然对齐。

---

## P1 · scp 失败：cert.pem 权限拒绝

**症状**：`cp -r /home/mgi/minicpm/webrtc_demo .` 报 `Permission denied` for `key.pem`。

**根因**：mgi 自签证书私钥 600 权限，LChuang 读不了。

**修复**：白名单逐文件 cp，跳过 cert.pem/key.pem。SSH tunnel 方案下也根本不需要 HTTPS 证书。

---

## P2 · `~/minicpm/assets/HT_ref_audio.wav` 默认路径找不到

**症状**：config_loader 默认 `paths.ref_audio = "assets/HT_ref_audio.wav"`，相对路径在 LChuang 工作目录下找不到。

**根因**：mgi 原版的 `assets/` 在 `/home/mgi/minicpm/assets/`（700 权限不可读）。但模型本身权重目录里也带了 ref audio：`MiniCPM-o-4_5/assets/HT_ref_audio.wav`（664 可读）。

**修复**：config.yaml 显式 `paths.ref_audio: /home/LChuang/workspace/minicpm/MiniCPM-o-4_5/assets/HT_ref_audio.wav`（走 symlink 复用 mgi 模型权重里的）。

---

## P2 · GB10 nvidia-smi 显存读不出

**症状**：`nvidia-smi --query-gpu=memory.used` 返回 `[N/A]`。

**根因**：NVIDIA GB10 (Grace Blackwell) 是 unified memory 架构，CPU/GPU 共享内存池，`memory.total/used/free` 字段不适用。

**预防**：判断显存是否够时改用 `free -h` 看系统内存。`torch.cuda.is_available()` 仍正常返回 True。

---

## 未来可能踩的坑（已埋雷）

### 多浏览器并发

server.py 里有 `_inference_busy` 全局变量、单一 WebSocket handler 设计。如果同时开两个浏览器连 spark，**会互相串话**（共享 inference_coordinator 队列与 _inference_busy 标志）。

**预防**：不要让两个浏览器同时连。如果未来需要多用户，要把 `_inference_busy` 改成 per-connection 状态，并加 `_inference_lock` 排队。

### TTS 回声进 ASR

VAD/ASR 与 TTS 共用浏览器麦克风。理论上 `_inference_busy` 在 processing/speaking 期间丢上行 PCM 防回声，但**状态切换有延迟**：TTS 第一帧到达浏览器播放时，spark 的 `_inference_busy` 可能还没变 True。极小概率会把自己的 TTS 录回去触发新 inference。

**预防**：浏览器开 `echoCancellation: true`（已开），还可以在 client side 加 `_is_playing_tts` 标志屏蔽 0x01 上行。

### 模型加载 2 分钟

每次 spark 重启服务都要重新加载 18GB 权重。

**预防**：要上 systemd 长驻；或写 watchdog 自动 restart。
