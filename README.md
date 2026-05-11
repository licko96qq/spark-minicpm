# spark-minicpm

> 把 OpenBMB MiniCPM-o 4.5 多模态 LLM 通过多种部署方案跑在边缘设备（DGX Spark GB10 / RTX 4090 / 5090）+ 浏览器远程操作的工具集。

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

---

## 1. 一句话定位

spark-minicpm 是把 OpenBMB MiniCPM-o 4.5 多模态 LLM 通过多种部署方案跑在边缘设备（DGX Spark GB10 / RTX 4090 / 5090）+ 浏览器远程操作的工具集。核心价值：

- 边缘设备本地跑多模态全双工（文本+语音+视觉），不依赖云端
- Mac/手机浏览器通过 SSH tunnel 远程使用边缘设备的算力
- 三条主线路线（B-cpp / C / D）各自覆盖不同的交付场景，都基于同一个 `llama.cpp-omni` 推理核

## 2. 架构图

```
Mac/手机浏览器  ──SSH tunnel──>  spark/4090/5090
   getUserMedia                    │
   getDisplayMedia                 ├─ B-cpp: gateway+worker+llama-server
                                   ├─ C:    LiveKit+backend+frontend+cpp_server+llama-server
                                   └─ D:    (B-cpp + silero-vad)

                                   ↓ 共享
                                   llama.cpp-omni (build/bin/llama-server)
                                   MiniCPM-o-4_5-gguf (F16/Q8_0/Q4_K_M)
```

浏览器侧：`getUserMedia` 采麦克风/摄像头，`getDisplayMedia` 采屏幕共享。WebSocket / WebRTC 上行到边缘机。

边缘机侧：三条路线都套在同一个 `llama-server`（tc-mb/llama.cpp-omni `feat/web-demo` 分支）上。不同路线差在前端/后端如何封装 duplex 协议与视频通道。

## 3. 三条路线快速对比

| 路线 | 模式 | 屏幕共享 | 自动 VAD | 启动复杂度 | 用途 |
|---|---|---|---|---|---|
| B-cpp | 4 模式（text/audio/duplex/omni） | 支持 | 手动按钮 | 低 | 工程改造起点，单机 4 端口 |
| C | 1 模式（视频双工） | 支持 | 自动（后端 dur_vad_full） | 中（5 服务 LiveKit+LLM+前后端） | 生产级简单陪伴 |
| D | 4 模式 + silero-vad | 支持 | 自动（前端 silero-vad WASM） | 低 | 长期主线，B-cpp 体验升级 |

完整对比（含 TTFT、单步耗时、资源占用、滑窗行为、当前已知问题）见 [docs/14-routes-comparison.md](docs/14-routes-comparison.md)。

选型建议：

- 想跑通最小闭环：先走 **B-cpp**
- 要给外部人演示、不想自己调参：走 **C**
- 想做工程改造 + 自动打断：走 **D**

## 4. 快速开始（60 秒）

前提：已在边缘机（spark / 4090 / 5090）按第 5 节完成部署；本机已建好到边缘机的 SSH tunnel（见 `scripts/ssh-setup.md`）。

```bash
# 1. clone
git clone https://github.com/<user>/spark-minicpm.git && cd spark-minicpm

# 2. 选路线启动（前提：spark 上已部署上游 + 应用 patches）
bash routes/b-cpp/up.sh         # 或 routes/c/up.sh F16
                                # 或 routes/d/up.sh Q8_0

# 3. 浏览器打开
open http://localhost:8040/omni/  # B-cpp
# 或 https://localhost:8088/      # C
# 或 http://localhost:8050/omni/  # D
```

路线 C 使用 HTTPS 自签证书（LiveKit WebRTC 要求 secure context），首次进入需在浏览器手动接受。B-cpp / D 走 HTTP，但因为是 `localhost` 也被浏览器视作 secure context，麦克风/摄像头权限可正常申请。

## 5. spark/边缘机部署

系统要求：

- Linux x86_64 (RTX 4090/5090) 或 aarch64 (DGX Spark GB10)
- CUDA 12.8+（4090 sm_89 / 5090 sm_120 / GB10 sm_120）
- cmake 3.20+，gcc 11+
- Python 3.10+ 带 venv
- Node 18+ 与 pnpm 10+（仅路线 C 前端编译需要）
- 至少 32GB 可用内存，推荐 64GB+（F16 档位）

部署步骤：

```bash
# 1. 下载模型（F16 / Q8_0 / Q4_K_M 一次拉齐，约 33GB）
bash scripts/download-models.sh all
#    只拉某个档位：bash scripts/download-models.sh Q8_0

# 2. 编译 llama.cpp-omni（feat/web-demo 分支，含 CUDA）
bash scripts/build-llama-cpp-omni.sh
#    产物：build/bin/llama-server

# 3. clone 对应路线的上游仓库
#    路线 B-cpp：OpenBMB/MiniCPM-o-Demo 的 Comni 分支
#    路线 C：  OpenSQZ/MiniCPM-V-CookBook demo/web_demo/WebRTC_Demo
#    路线 D：  基于 B-cpp 的 fork（本仓库内含）
#    详见 routes/<X>/README.md

# 4. 应用本仓库的 patches
bash scripts/apply-patches.sh b-cpp /path/to/MiniCPM-o-Demo-Comni
bash scripts/apply-patches.sh c     /path/to/MiniCPM-V-CookBook
bash scripts/apply-patches.sh d     /path/to/MiniCPM-o-Demo-Comni-d

# 5. 改 config.json：模型路径、端口、量化档位
vim config.json
```

模型档位选择：

| 档位 | 大小 | 显存占用 | 推荐硬件 | 智能水平 |
|---|---|---|---|---|
| F16 | 16G | ~18G | 5090 32G / GB10 121G | 接近 HF BF16 原始权重 |
| Q8_0 | 8.2G | ~10G | 4090 24G / 5090 / GB10 | 甜点档，肉眼无差 |
| Q4_K_M | 4.7G | ~6G | 4090 24G | 极致流畅，智能肉眼降 |

## 6. Mac 本地使用

SSH 连接与 tunnel 配置：

- 在 `~/.ssh/config` 里为边缘机配个 Host 别名（本项目示例用 `spark_704`）
- 用 SSH key 免密登录，tunnel 端口由 `scripts/ssh-setup.md` 一键建立
- 每条路线需要转发的端口不同（B-cpp 1 个 / C 5 个 / D 1 个），启动脚本会自动转

浏览器权限：

- 首次打开会弹麦克风/摄像头授权，必须 Allow（拒绝后要去浏览器站点权限里手动恢复）
- Chrome / Edge / Safari 均测试通过
- iOS Safari 走 `https://localhost:<port>` 通过局域网访问（需边缘机 IP 直连，不走 tunnel）

HTTPS 自签证书（仅路线 C）：

- 首次访问 `https://localhost:8088/` 会报"不安全"，点"高级 → 继续访问"
- 证书由 LiveKit oneclick 脚本自签，有效期 10 年

## 7. 迁移到 4090/5090

完整迁移指南见 [docs/15-migration-4090-5090.md](docs/15-migration-4090-5090.md)。关键点：

**4090（sm_89）**：

- 必须重编 `llama-server`，GB10 的 sm_120 二进制不能跑
- `cmake -DCMAKE_CUDA_ARCHITECTURES=89`，其他步骤同 `scripts/build-llama-cpp-omni.sh`
- 24G 显存推荐跑 Q4_K_M（留 buffer 给 ctx 与 vision encoder），Q8_0 勉强但 ctx 要压到 4096

**5090（sm_120）**：

- 与 GB10 同 arch，可直接复用 GB10 编译产物（`build/bin/llama-server` 拷过去即可）
- 32G 显存推荐 Q8_0，ctx 可以开 8192 甚至 16384

**GB10（DGX Spark）**：

- 内存带宽 = A100 的 14%，F16 omni 单步 ~1s 会卡
- Q8_0 是目前实测的甜点档
- 屏幕共享 + 高清视觉（max_slice_nums=3）会把 prefill 吃到 +100ms，实测建议关掉

## 8. 故障排查

完整排查手册见 [docs/16-troubleshooting.md](docs/16-troubleshooting.md)。常见前三：

**1. 模型一直 LISTEN 不 SPEAK**

根因：前端 `preparePayload.config` 没传 `listen_prob_scale`，后端用默认值 1.0 导致 sampling 永远偏向 listen。

解决：确认 `static/omni/omni-app.js` 的 preparePayload 里 `config.listen_prob_scale=0.3, force_listen_count=0`。实测 0.3 是目前 F16/Q8 唯一稳定可用值，调高到 0.4+ 反而失败。

**2. 49s 后自动 stop（视频/音频对话自动中断）**

根因：KV 滑窗触发时前端 `stopOnKvShrink` 复选框默认勾着，滑窗一触发就停。

解决：`static/omni/omni.html` 里 `<input id="stopOnKvShrink">` 去掉 `checked` 属性，或运行时手动取消勾选。

**3. 屏幕共享 / 视频全双工卡顿**

根因：Q8_0 + omni 模式 + 勾了「高清视觉 64 tok」会把 max_slice_nums 从 1 升到 3，视觉 token 从 64 激增到 256+，prefill 单步 +100ms。

解决：切 Q4_K_M 或关「高清视觉」。屏幕共享场景 1 slice 已够识别屏幕元素。

## 9. 仓库结构

```
spark-minicpm/
├── README.md
├── HANDOVER.md        # 时序日志（每次会话的进展、决策、踩坑）
├── LICENSE            # Apache 2.0
├── docs/              # 16 篇专题文档
│   ├── 01-architecture.md            # 路线 A 架构（历史，瘦客户端）
│   ├── 02-refactor-deltas.md         # 路线 A 改造 diff
│   ├── 03-pitfalls.md                # 浏览器音频踩坑
│   ├── 04-route-b-deployment-plan.md # 路线 B 部署规划
│   ├── 05-route-b-issues.md          # 路线 B 问题集
│   ├── 06-rollback-snapshots.md      # 路线 B 回滚
│   ├── 07-mode-test-matrix.md        # 4 模式实测矩阵
│   ├── 08-route-c-llama-cpp-omni.md  # 路线 C llama.cpp-omni 部署
│   ├── 09 ~ 13                       # 路线 C 调优与监控
│   ├── 14-routes-comparison.md       # 三条路线完整对比
│   ├── 15-migration-4090-5090.md     # 迁移 4090/5090 指南
│   └── 16-troubleshooting.md         # 故障排查手册
├── routes/            # 主线路径
│   ├── b-cpp/         # 4 模式 demo（上游 OpenBMB Comni）
│   ├── c/             # WebRTC 视频双工（上游 OpenSQZ CookBook）
│   └── d/             # B-cpp + silero-vad（本仓库自研）
├── scripts/           # 模型下载 / 编译 / patch / SSH tunnel
│   ├── download-models.sh
│   ├── build-llama-cpp-omni.sh
│   ├── apply-patches.sh
│   └── ssh-setup.md
└── archive/           # 弃用路线（route-a 瘦客户端等历史快照）
```

## 10. 致谢 + License

**上游仓库**：

- [OpenBMB/MiniCPM-o-Demo](https://github.com/OpenBMB/MiniCPM-o-Demo) (Apache 2.0) — 路线 B-cpp / D 的上游 demo（Comni 分支）
- [OpenSQZ/MiniCPM-V-CookBook](https://github.com/OpenSQZ/MiniCPM-V-CookBook) (Apache 2.0) — 路线 C 的上游（WebRTC_Demo + LiveKit 编排）
- [tc-mb/llama.cpp-omni](https://github.com/tc-mb/llama.cpp) (MIT) — 三条路线共享的 C++ 推理引擎（`feat/web-demo` 分支，含 duplex 协议与 token2wav 滑窗）
- [OpenBMB/MiniCPM-o](https://github.com/OpenBMB/MiniCPM-o) — 模型权重与论文（本项目仅重分发 GGUF 量化）

**工具与资源**：

- DGX Spark / GB10 硬件测试平台
- MiniCPM 团队（魏弘量 / 蔡天驰 / 子豪）的飞书群答疑与路线推荐

**License**：本仓库内所有原创代码、脚本、文档采用 [Apache License 2.0](LICENSE)。对上游仓库的 patches 保留各上游 LICENSE（主要是 Apache 2.0 和 MIT），应用 patch 时不改变上游授权。

**作者**：licko & contributors
