# spark-minicpm

> MiniCPM-o 4.5 多模态边缘部署 + **屏幕共享陪伴助手** + **自动 VAD 语音打断**。
> 支持 DGX Spark (GB10) / RTX 4090 / 5090，浏览器远程操作，可读论文/看视频/做调研。

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

---

## ✨ 我们做了什么（区别于官方 demo）

官方 `OpenBMB/MiniCPM-o-Demo` 是个 4 模式 baseline demo，**裸跑会有这些问题**：模型不开口 / 49 秒后自动断线 / 视频卡顿 / 没有屏幕共享 / 不能语音打断。我们解决了所有这些。

| 亮点 | 说明 | 在哪 |
|---|---|---|
| 🖥️ **屏幕共享陪伴模式** | omni tab 新增按钮，点一下切「摄像头 ↔ 屏幕共享」。模型实时看你的桌面（论文 PDF / Chrome 标签 / 视频窗口）回答问题 | 路线 B-cpp / D |
| 🎙️ **自动 VAD 语音打断** | 模型说话时你一开口，silero-vad ONNX 后端检测到（prob ≥ 0.5）→ 200ms 内闭嘴切回 LISTEN。**告别手动按按钮** | 路线 C / D |
| 🎛️ **量化档位脚本切换** | `bash routes/d/up.sh Q4_K_M\|Q8_0\|F16`，无需手编 config | 路线 C / D |
| 💬 **可改提示词** | 屏幕共享模式默认注入官方人设，可换成你的专业陪伴 prompt（科研助手 / 客服 / 教师等） | 见下方 |
| ⚡ **修了 sampling 真根因** | 官方 demo F16/Q8/Q4 默认全 LISTEN 不 SPEAK，根因是前端没传 `listen_prob_scale`。我们默认 `lps=0.3, flc=0` | 路线 B-cpp / D |
| 🛡️ **滑窗自动停止 fix** | 49s 后 KV cache pruned → 默认勾选导致服务自动 stop，已去勾 | 路线 B-cpp / D |
| 📺 **HD vision 自动避坑** | 屏幕共享模式自动关「高清视觉」（max_slice_nums=1），avoid +100ms 卡顿 | 路线 B-cpp / D |
| 🚀 **多机迁移文档** | 4090（sm_89）需重编 llama-server，5090（sm_120）可直接复用 GB10 编译产物 | `docs/15` |

---

## 🎯 我该选哪条路线？

```
┌──────────────────────────────────────────────────────────┐
│  想要自动 VAD 打断  +  屏幕共享  +  4 模式  +  Q4/Q8/F16  │
│  → 路线 D（推荐主线）                                       │
├──────────────────────────────────────────────────────────┤
│  只要简单视频陪伴 + 自动打断（生产成熟）                       │
│  → 路线 C                                                  │
├──────────────────────────────────────────────────────────┤
│  调试 / 4 模式对比 / 工程改造起点                           │
│  → 路线 B-cpp                                              │
└──────────────────────────────────────────────────────────┘
```

完整对比矩阵：[docs/14-routes-comparison.md](docs/14-routes-comparison.md)

---

## 🚀 60 秒上手（默认 Q4_K_M）

```bash
# 1. clone
git clone https://github.com/licko96qq/spark-minicpm.git && cd spark-minicpm

# 2. 在 GPU 机器上下载 Q4_K_M 模型（默认 4.7G，4090/5090/GB10 都能跑）
bash scripts/download-models.sh
# 想要更聪明：bash scripts/download-models.sh Q8_0   或   F16

# 3. 编译 llama-server（自动探 GPU 架构 sm_89/sm_120）
bash scripts/build-llama-cpp-omni.sh

# 4. 部署上游代码并应用 patches（spark / 4090 / 5090 任一）
# 详见 routes/d/README.md

# 5. 启动路线 D
bash routes/d/up.sh           # 默认 Q4_K_M
# bash routes/d/up.sh Q8_0    # 想要更聪明换 Q8

# 6. 浏览器打开
open http://localhost:8050/omni/
# 顶部点「屏幕共享」按钮 → 选窗口/标签页 → 说话提问
```

---

## 💬 怎么改提示词适配自己的场景

模型默认用官方「面壁小钢炮」人设。**不同场景换不同 prompt** 才能发挥它的能力。

### 方式 A：浏览器侧改（最简单，临时改）

打开 omni 页面 → 左侧面板 **System Prompt** textarea 直接改即可，下次启动会话生效。

### 方式 B：屏幕共享模式默认 prompt（永久改，覆盖 textarea）

文件：`spark` 端 `MiniCPM-o-Demo-D/static/omni/omni-app.js` 找 `_companionPrompt` 变量（约 1642 行）。

**示例 prompt 模板**：

```js
// 调研/论文陪读
const _companionPrompt = `你是一个学术论文陪读助手。能看到用户屏幕（PDF/网页）。
- 主动指认图表/公式/章节标题
- 用中文解释技术概念，必要时附英文原文
- 用户问"这段什么意思"时给出 2-3 句精确总结，不要长篇大论`;

// 客服支持
const _companionPrompt = `你是一名专业客服。能看到用户当前页面截图。
- 引导用户操作，按钮位置精确指认
- 不知道答案时直接说"我需要转人工"`;

// 编程导师
const _companionPrompt = `你是经验丰富的工程师陪伴写代码。能看到用户的 IDE 屏幕。
- 主动指出明显的代码错误
- 解释 API 用法时配合屏幕上的代码举例
- 不要主动改代码，等用户问再回答`;

// 视频陪看
const _companionPrompt = `你是用户的视频陪看伙伴。能看到屏幕上播放的视频。
- 主动评论画面内容（人物/场景/字幕）
- 用户问"刚才说什么"时复述上一段台词
- 不抢话，停顿超过 3 秒再开口`;
```

改完刷新浏览器即可生效。注意 prompt 不要太长（会消耗 KV cache），200 token 内最佳。

### 方式 C：让 prompt 动态化（高级）

把 system_prompt textarea 改成 dropdown，用户选场景 → 自动注入对应 prompt。需要改 omni.html + omni-app.js。issue 欢迎。

---

## 🏗️ 架构图

```
浏览器（Mac/手机）
    │ getUserMedia (麦克风)
    │ getDisplayMedia (屏幕共享) ⭐
    │
    ├─ SSH tunnel ──► spark / 4090 / 5090
    │                  │
    │                  ├─ 路线 B-cpp: gateway (8040) → worker (22440) → llama-server (19080)
    │                  │   4 模式 (omni / audio-duplex / half-duplex / chat)
    │                  │
    │                  ├─ 路线 C: LiveKit (7880) + backend (8021) + frontend (8088 HTTPS)
    │                  │   + cpp_server (9060) → llama-server (19060)
    │                  │   原生自动 VAD 打断 ⭐
    │                  │
    │                  └─ 路线 D: gateway (8050) → worker (22450) → llama-server (19090)
    │                       4 模式 + 自动 VAD 打断 ⭐ + 屏幕共享 ⭐
    │
    └─ 共享底层：llama.cpp-omni (feat/web-demo 分支)
                MiniCPM-o-4_5-gguf (F16 / Q8_0 / Q4_K_M)
                silero_vad.onnx (1.8 MB)
```

---

## 📁 仓库结构

```
spark-minicpm/
├── README.md                # 本文件
├── HANDOVER.md              # 时序日志（含已解决问题 + TODO）
├── LICENSE                  # Apache 2.0
│
├── docs/                    # 16 篇专题文档
│   ├── 14-routes-comparison.md       # 三路线完整对比
│   ├── 15-migration-4090-5090.md     # GPU 迁移指南
│   └── 16-troubleshooting.md         # 已知坑全记录
│
├── routes/
│   ├── b-cpp/               # 4 模式 demo + 屏幕共享 + 手动打断
│   │   ├── README.md
│   │   ├── up.sh / down.sh
│   │   └── patches/0001-screen-share-companion-mode.patch
│   ├── c/                   # WebRTC + 自动 VAD 打断（生产成熟）
│   │   ├── README.md
│   │   └── up.sh / down.sh
│   └── d/                   # ⭐ 推荐主线：B-cpp + silero-vad
│       ├── README.md
│       ├── up.sh / down.sh
│       └── patches/0001-silero-vad-integration.patch
│
├── scripts/
│   ├── download-models.sh        # 默认下 Q4_K_M（4.7G），可选 Q8/F16
│   ├── build-llama-cpp-omni.sh   # 自动探 sm_89/sm_120 编译
│   ├── apply-patches.sh          # 一键应用 patches
│   └── ssh-setup.md              # SSH key + tunnel
│
└── archive/                 # 历史路线（route-a，已弃用）
```

---

## 🖥️ 4090 / 5090 迁移

详见 [docs/15-migration-4090-5090.md](docs/15-migration-4090-5090.md)。要点：

| GPU | CUDA SM | VRAM | 推荐量化 | llama-server |
|---|---|---|---|---|
| GB10 (DGX Spark) | sm_120 | 121G unified | F16 / Q8 | 直接用 |
| **RTX 4090** | sm_89 | 24G | **Q4_K_M / Q8** | ⚠️ **必须重编** `-DCMAKE_CUDA_ARCHITECTURES=89` |
| **RTX 5090** | sm_120 | 32G | Q8 / F16 | 复用 GB10 编译产物 |

`scripts/build-llama-cpp-omni.sh` 已自动探卡。

---

## 🔧 故障排查（前三）

1. **模型一直 LISTEN 不 SPEAK** → 前端 `preparePayload.config` 没传 `listen_prob_scale=0.3`（详见 [docs/16](docs/16-troubleshooting.md)）
2. **49s 后自动断线** → 取消 `omni.html` 的 `stopOnKvShrink` 默认 `checked`
3. **卡顿明显** → 切 Q4_K_M / 关「高清视觉」 / 屏幕共享降帧率到 0.5fps

完整：[docs/16-troubleshooting.md](docs/16-troubleshooting.md)

---

## 🙏 致谢

上游（均 Apache 2.0 / MIT）：
- [OpenBMB/MiniCPM-o-Demo](https://github.com/OpenBMB/MiniCPM-o-Demo) (Comni 分支) — 4 模式 baseline demo
- [OpenSQZ/MiniCPM-V-CookBook](https://github.com/OpenSQZ/MiniCPM-V-CookBook) — WebRTC + LiveKit 集成
- [tc-mb/llama.cpp-omni](https://github.com/tc-mb/llama.cpp-omni) (feat/web-demo) — C++ 推理后端
- [snakers4/silero-vad](https://github.com/snakers4/silero-vad) (MIT) — 语音活动检测

本仓库：Apache 2.0 © 2026 licko & contributors
