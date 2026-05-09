# spark-minicpm — MiniCPM-o 4.5 远程多模态对话服务

> 在 spark (NVIDIA GB10) 上跑 MiniCPM-o 4.5 实时多模态推理；Mac 浏览器作为前端使用本机麦克风/摄像头/扬声器。
> 改造来源：mgi 用户下学生原版 webrtc_demo（瘦客户端模式）→ LChuang 用户下前后端真分离版本。

**本目录是本机存档（文档+脚本+改造快照），不是源码工作区。** 真正部署在 `spark_704:/home/LChuang/workspace/minicpm/`。

## 一句话架构

```
Mac 浏览器 (麦克风/摄像头/扬声器)
        │  http://localhost:8765
        ↓  ssh -L 8765:127.0.0.1:8765
Spark uvicorn FastAPI
  ├── WebSocket /ws  (0x01 PCM ↑ / 0x02 JPEG ↑ / 0x10 TTS PCM ↓)
  └── MiniCPM-o 4.5 (18GB, GB10 unified memory)
```

## 快速操作

```bash
# 启动 spark 端服务
./scripts/start-spark-minicpm.sh

# 打通 Mac 端隧道 + 打开浏览器
./scripts/connect.sh

# 关停
./scripts/stop.sh
```

## 关键事实

| 项 | 值 |
|---|---|
| spark 工作目录 | `/home/LChuang/workspace/minicpm/` |
| 模型权重 | symlink → `/home/mgi/minicpm/MiniCPM-o-4_5`（不重复占 18GB） |
| Conda env | `LChuang/miniconda3/envs/minicpm`（clone 自 mgi） |
| 服务监听 | `127.0.0.1:8765`（强制走 SSH tunnel，不暴露 LAN） |
| 浏览器入口 | `http://localhost:8765/`（Mac 端通过 ssh -L 转发） |
| 性能基线 | TTFT ~2.3s，15-19 tok/s |

## 目录结构

```
spark-minicpm/
├── README.md                  # 本文件
├── HANDOVER.md                # 会话交接信息
├── docs/
│   ├── 01-architecture.md    # 前后端分离设计与 wire protocol
│   ├── 02-refactor-deltas.md # 相对 mgi 原版的改动详解
│   └── 03-pitfalls.md        # 浏览器音频两大坑（autoplay + 字节对齐）
├── configs/
│   └── config.yaml           # spark 端 deploy/config.yaml 副本
├── refactor-snapshot/         # 改造后的源码快照（已部署到 spark）
│   ├── server.py             # FastAPI 服务（267 行）
│   └── index.html            # 浏览器前端（456 行）
└── scripts/
    ├── start-spark-minicpm.sh # 在 spark 启动 uvicorn
    ├── connect.sh             # Mac 端建隧道 + 打开浏览器
    └── stop.sh                # 关停 spark 服务和本机隧道
```

## 与 mgi 原版的关系

mgi 学生版 `/home/mgi/minicpm/webrtc_demo/` 完全没动，他们仍可用本地外设模式（spark 接 USB 麦克风+扬声器+摄像头）。本项目是另起炉灶的远程算力版本，两者并存互不影响。

## 风险/限制

- **单连接设计**：server.py 使用单一 `_active_speech_queue`，一个浏览器连接吃满整台 spark 的 GPU。多用户场景需重写。
- **回声屏蔽靠状态机**：`_inference_busy` 在 processing/speaking 状态丢上行 PCM。如果 TTS 漏过开始播放和状态切换之间的间隙，可能进 ASR 形成回环。
- **Audio Worklet 降采样**：浏览器 48kHz → 16kHz 用线性插值，质量足够 ASR 但不是最优；若需更高识别率可换 `OfflineAudioContext` 重采样。
- **GB10 unified memory**：`nvidia-smi` 看不到显存占用是正常的（不是 bug）。

## 关联资源

- mgi 原部署：`spark_704:/home/mgi/minicpm/`
- 兄弟项目：`spark-llm`（llama-swap + Qwen 系列）、`spark-vllm`（Qwen3-VL-32B-FP8）
- 模型项目：[OpenBMB/MiniCPM-o](https://github.com/OpenBMB/MiniCPM-o)，[OpenBMB/MiniCPM-o-Demo](https://github.com/OpenBMB/MiniCPM-o-Demo)
