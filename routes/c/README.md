# 路线 C — WebRTC_Demo + llama.cpp-omni (feat/web-demo) 视频全双工

## 一句话定位

OpenSQZ `MiniCPM-V-CookBook` 的 `WebRTC_Demo` 子项目 + `tc-mb/llama.cpp-omni` (feat/web-demo 分支)，**带 KV 滑窗**，带**自动 VAD**（`dur_vad_full ≥ 0.85`），是当前长会话视频全双工唯一可用路线。

## 上游来源

```bash
# 应用层（前后端 + cpp_server wrapper）
git clone https://github.com/OpenSQZ/MiniCPM-V-CookBook
cd MiniCPM-V-CookBook
git checkout 5968457   # baseline
# 我们的 C2 定制 patch commit: c489953（已 rebase 在 5968457 之上）
# 子项目位于:
#   demo/web_demo/WebRTC_Demo/
# 注意嵌套:
#   demo/web_demo/WebRTC_Demo/WebRTC_Demo/o45-frontend   <- 内层才是实际前端构建目录

# 推理引擎
git clone https://github.com/tc-mb/llama.cpp-omni
cd llama.cpp-omni
git checkout feat/web-demo   # baseline edef517 + gitignore patch 479cbc4
```

- spark 端部署路径：
  - 应用：`/home/LChuang/workspace/MiniCPM-V-CookBook/demo/web_demo/WebRTC_Demo/`
  - 引擎：`/home/LChuang/workspace/llama.cpp-omni/`（编好的 `llama-server` 二进制在这里）

## 前置条件

- GPU：GB10（sm_120）或同级，unified memory ≥ 30G 可用
- 系统依赖：`livekit-server` 1.9.11 装到 `~/.local/bin/`，`pnpm` 装到 `~/.npm-global/bin`（用户级）
- Python：`/home/LChuang/miniconda3/envs/minicpm/`（与路线 B-cpp 共用的 conda env）
- 前端构建：绕开 pnpm 10 的 `ERR_PNPM_IGNORED_BUILDS` 安全机制，直接 `node_modules/.bin/vite build`（oneclick.sh 已封装；如果要重新 build 见 HANDOVER「2026-05-10 00:20 Session」段）
- 模型：`MiniCPM-o-4_5-{F16,Q8_0,Q4_K_M}.gguf`，放 `/home/LChuang/workspace/MiniCPM-o-4_5-gguf/`

## 部署步骤

1. clone 仓库 + checkout commit（见上游来源）；
2. 按 `oneclick.sh` 提示装 livekit-server / pnpm 到用户目录；
3. 第一次跑 `oneclick.sh start` 会 sparse-clone 嵌套 `WebRTC_Demo/WebRTC_Demo/` 子目录。前端手动 build 在内层 `o45-frontend/`：
   ```bash
   ssh spark_704 'cd ~/workspace/MiniCPM-V-CookBook/demo/web_demo/WebRTC_Demo/WebRTC_Demo/o45-frontend && node_modules/.bin/vite build && touch dist/.cpp_mode'
   ```
4. 下载 GGUF 到 `MODEL_DIR`（`~/workspace/MiniCPM-o-4_5-gguf/`）；
5. 启动：`bash routes/c/up.sh F16`（或 `Q8_0` / `Q4_K_M`）。

## 启停

```bash
# 启（量化档位作为 $1）
bash /Users/licko/Documents/workspace/cc_test/AllRealHub/spark-minicpm/routes/c/up.sh F16
bash /Users/licko/Documents/workspace/cc_test/AllRealHub/spark-minicpm/routes/c/up.sh Q8_0
# 停
bash /Users/licko/Documents/workspace/cc_test/AllRealHub/spark-minicpm/routes/c/down.sh
```

`up.sh` 会：
- 通过 `LLM_MODEL=MiniCPM-o-4_5-<QUANT>.gguf` 环境变量透传量化档位（`LLM_QUANT` oneclick 不转发，这是已踩的坑）
- 通过 `SYSTEM_PROMPT` 环境变量（base64 编码规避换行）注入陪伴 prompt 到 cpp_server warmup
- 建本机 5 个端口 SSH tunnel

## 端口表

| 服务 | 端口 | 备注 |
|---|---|---|
| LiveKit Server | 7880 | WebRTC 信令 |
| Backend (FastAPI) | 8021 | HTTP health / session 管理 |
| Frontend (Vite prod) | 8088 | HTTPS 自签，浏览器入口 `https://localhost:8088/` |
| cpp_server | 9060 | 推理请求 |
| cpp_server health | 9061 | `curl http://localhost:9061/health` |
| llama-server | 19060 | cpp_server 内部调用，不对外 |

同 WiFi 直连：`https://<SPARK_LAN_IP>:8088/`（首次需接受自签证书）。

## 配置文件改动点

- 量化档位：**只走 `up.sh $1`**，不要手改 config。`LLM_MODEL` 环境变量是唯一可靠入口。
- ctx_size：`CTX_SIZE` 环境变量，默认 8192。16K 实测更慢，别动。
- 陪伴 prompt：`SYSTEM_PROMPT` 环境变量（短版 ~80 token，见 `up.sh` 顶部 heredoc）。改长会撑大 `n_keep` 让 attention 慢。
- cpp_server 滑窗参数：`~/workspace/llama.cpp-omni/tools/omni/omni.cpp`（不改，用上游默认的 28 input / 25 stride）。

## 该路线 patches 说明

见 `./patches/README.md`。路线 C 本身**没有代码 patch 需要应用**，`up.sh` 自身包含所有必要的环境变量透传。上游 `MiniCPM-V-CookBook` 的 C2 定制 patch（`c489953`）已 rebase 进主仓库，直接 clone 即包含。

## 已知问题

- **周期性卡顿 ~52s 一次**：滑窗触发时全链路短暂卡顿。
- **记忆突然丢失**：滑窗 `freed 3934 tokens` 把 system prompt 之外的历史清了。
- **字幕有但语音停**：滑窗 `TTS KV cleared` 把正在生成的 wav chunk 中断——字幕文字已经 flush 到前端，音频断了。

根治需改 `tools/omni/omni.cpp`：滑窗时不清 TTS KV / 等 turn 结束才滑窗。见 HANDOVER 路线 C2 段 + `docs/11-user-feedback.md` / `docs/12-tuning-plan.md` / `docs/13-monitoring-tuning-results.md`。

`docs/16-troubleshooting.md` 对应章节（若未建，查上述 3 份 docs 与 HANDOVER）。

## 何时选这条路线

- 需要**长会话**（> 1 分钟）视频全双工不崩
- 需要**自动 VAD**打断（说话时模型自动闭嘴）
- 接受 ~52s 一次周期性卡顿 + 记忆丢失现象（滑窗副作用）
- 需要 WebRTC（LiveKit）而非 WebSocket 传输

**不选的场景**：需要屏幕共享陪伴模式——用路线 B-cpp。需要快速切量化档位做对比——路线 B-cpp 改 `config.json` 更快。
