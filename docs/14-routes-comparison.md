# 14 — 路线 B-cpp vs C vs D 完整对比

> 事实来源：HANDOVER.md / docs/05-route-b-issues.md / docs/08-route-c-llama-cpp-omni.md
> 更新时间：2026-05-11

## 对比矩阵

| 维度 | 路线 B-cpp | 路线 C | 路线 D（在做） |
|---|---|---|---|
| 后端栈 | OpenBMB `MiniCPM-o-Demo` Comni 分支 + `llama.cpp-omni` cpp_server | OpenSQZ `MiniCPM-V-CookBook` WebRTC_Demo + LiveKit + `llama.cpp-omni` | 基于 B-cpp + `silero-vad`（移植 C 的自动打断） |
| 前端栈 | 静态 HTML/JS（多 tab 切换） | Vue 3 + Vite（单页 WebRTC） | 静态 HTML/JS（继承 B-cpp） |
| 模式数 | 4（omni / audio-duplex / half-duplex / chat） | 1（视频双工） | 4（同 B-cpp） |
| 屏幕共享 | ✅ omni 顶部按钮切换摄像头/屏幕 | ✅ `localStorage.videoSource=screen` | ✅ 继承 B-cpp |
| 自动 VAD 打断 | ❌ 仅手动「强制收听」按钮 | ✅ 后端 `dur_vad_full ≥ 0.85` | 🎯 移植 C 的 silero-vad |
| 量化档位 | F16 / Q8_0 / Q4_K_M（改 `config.json` 后重启） | F16 / Q8_0 / Q4_K_M（`LLM_QUANT=` 脚本传参） | F16 / Q8_0 / Q4_K_M（脚本传参） |
| 端口 | gateway 8040 / worker 22440 / llama-server 19080 | LiveKit 7880 / backend 8021 / frontend 8088 / cpp_server 9060/9061 / llama-server 19060 | gateway 8050 / worker 22450 / llama-server 19090（待验证） |
| 启动复杂度 | 低（`bash route-b-cpp-up.sh`） | 中（4 服务 + pnpm build） | 低（继承 B-cpp） |
| 默认 prompt | 官网默认 + 屏幕模式陪伴 prompt | 陪伴助手 prompt | 同 B-cpp |
| 实测稳定性 | 调通后可用，lps=0.3 flc=0 为唯一稳定参数 | 4 服务全 healthy，F16/Q8 用户主观「速度很快」 | 🚧 开发中 |
| 何时选 | 调试 / 多模式对比 / 工程改造起点 | 生产级简单视频陪伴 | 等 D 实现完接管所有场景 |

## 何时选 B-cpp

- 需要 4 模式切换做对照（omni / audio-duplex / half-duplex / chat）
- 需要工程化二次开发的入口（前端全是裸 HTML/JS 好改）
- 可接受手动按「强制收听」按钮实现打断
- 场景示例：协议调试、prompt 调优、参数扫描

## 何时选 C

- 只要视频双工 + 自动打断，立即可用的最佳路径
- 可接受单一模式（不需要切 half-duplex / chat）
- 可接受 Vue + Vite 前端栈
- 场景示例：陪伴助手演示、对外 demo、固定场景生产

## 何时选 D

- 等 D 落地后接管所有场景：B-cpp 的 4 模式工程化 + C 的自动 VAD 打断
- 当前（2026-05-11）尚未交付，不要作为主线

## 互斥与共存

- **B-cpp 和 D 互斥**：同一台 spark 不能同时跑。端口 19080 vs 19090 虽不冲突，但 GB10 unified 121G 内存吃紧
  - 实测参考：单路 F16 GGUF 加载就要 ~16G，Q8 ~8.2G，Q4_K_M ~4.7G；叠加 worker/gateway/前端后一路就到 25G 级别
- **C 和 D 端口不冲突**：理论可共存，但 unified 121G 实测两路加起来仍吃紧，GB10 上不建议长期并行
- **C 和 B-cpp**：端口完全不重叠，短时共存可以，长时共存会挤占内存带宽
- 决策：生产环境任何时刻**只跑一条路线**，切换用 up/down 脚本完成

## 关键事实确认

- 模型档位用户主观偏好（B-cpp omni 实测）：
  - F16：智能高但 GB10 带宽瓶颈明显卡顿
  - **Q8_0**：甜点档（路线 C2 + 用户均验证）
  - Q4_K_M：极致流畅，智能肉眼下降
- B-cpp 采样参数窄窗口（F16 / Q8 实测）：**`listen_prob_scale=0.3` + `force_listen_count=0` 是唯一稳定值**，调到 0.4/0.5/0.6 全失败（HANDOVER 17:45 段）
- GB10 硬件 baseline：内存带宽 ≈ A100 的 14%，是 omni 卡顿的结构性根因
