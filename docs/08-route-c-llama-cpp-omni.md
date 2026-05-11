# 路线 C 部署手册 — WebRTC_Demo + llama.cpp-omni（F16）

> 最后更新：2026-05-10
> 验证状态：✅ 端到端跑通，用户实测速度快、不卡

## TL;DR

```bash
bash route-c-up.sh           # 默认 F16
bash route-c-up.sh Q4_K_M    # 切回 Q4 也行
bash route-c-down.sh
```

浏览器：`https://localhost:8088/` （Mac，走 SSH tunnel）/ `https://<SPARK_LAN_IP>:8088/`（手机同 WiFi 直连）

---

## 架构

```
浏览器（getUserMedia 摄像头/麦克风）
   ↓ WebRTC (LiveKit SFU)
spark:7880 (LiveKit) ⇄ spark:8021 (FastAPI Backend)
                          ↓ HTTP
                      spark:9060 (cpp_server, Python wrapper)
                          ↓ HTTP /v1/stream/...
                      spark:19060 (llama-server, C++ inference)
                          ↑ loads
                      MiniCPM-o-4_5-F16.gguf + audio/tts/vision/token2wav-gguf
```

前端 prod build 由 spark 端 `serve-prod.mjs` 用 HTTPS 8088 提供（自签证书 IP <SPARK_LAN_IP>）。

## 关键路径（spark）

| 组件 | 路径 |
|---|---|
| 推理引擎 | `/home/LChuang/workspace/llama.cpp-omni/` （tarball，feat/web-demo 分支快照） |
| llama-server 二进制 | `~/workspace/llama.cpp-omni/build/bin/llama-server` |
| GGUF 全套 24G | `~/workspace/MiniCPM-o-4_5-gguf/`（Q4_K_M / F16 / audio / tts / vision / token2wav-gguf） |
| WebRTC_Demo | `~/workspace/MiniCPM-V-CookBook/demo/web_demo/WebRTC_Demo/` |
| 嵌套子项目 | `WebRTC_Demo/WebRTC_Demo/`（**注意：oneclick 实际工作在这层**） |
| 日志 | `WebRTC_Demo/.logs/{livekit,backend,cpp_server,frontend}.log` |
| Python venv | `~/miniconda3/envs/minicpm/`（Python 3.10.20） |
| livekit-server | `~/.local/bin/livekit-server` v1.9.11 |
| 自签证书 | `WebRTC_Demo/.certs/server.{crt,key}`（IP <SPARK_LAN_IP>） |

## oneclick 关键环境变量

```bash
PYTHON_CMD=/home/LChuang/miniconda3/envs/minicpm/bin/python  # 必填，否则可能挑到错的 python
LLAMACPP_ROOT=/home/LChuang/workspace/llama.cpp-omni
MODEL_DIR=/home/LChuang/workspace/MiniCPM-o-4_5-gguf
LLM_QUANT=F16             # F16 (16G) / Q8_0 (~9G) / Q4_K_M (~5G)
CPP_MODE=duplex           # duplex (双工) / simplex (单工)
PATH=$HOME/.local/bin:$HOME/.npm-global/bin:$PATH   # 必须，否则找不到 livekit / pnpm
```

## 已知坑（首次部署都会撞）

1. **livekit-server 装系统目录失败**：oneclick 默认装 `/usr/local/bin` 要 sudo。手动装到 `~/.local/bin/livekit-server`（tarball: `https://ghfast.top/https://github.com/livekit/livekit/releases/download/v1.9.11/livekit_1.9.11_linux_arm64.tar.gz`）
2. **pnpm 装到 `~/.npm-global/bin`，oneclick 找不到**：必须 `export PATH="$HOME/.npm-global/bin:$PATH"` 再起
3. **pnpm 10+ ERR_PNPM_IGNORED_BUILDS 误判 frontend build 失败**：写 `~/.npmrc` 加 `verify-deps-before-run=never` 不解决（pnpm 自动 verify 独立）。**根治**：绕开 pnpm，进 `WebRTC_Demo/WebRTC_Demo/o45-frontend/` 跑 `VITE_CPP_MODE=duplex node_modules/.bin/vite build --mode prod-external`，再 `echo -n duplex > dist/.cpp_mode`。oneclick 检测 dist/ + .cpp_mode 后跳过 build 直接 `node serve-prod.mjs`
4. **嵌套目录陷阱**：oneclick 第一次跑会 sparse-clone 一份 `WebRTC_Demo/WebRTC_Demo/`，**手动 build 要去内层**，外层那份 dist 没用
5. **GB10 unified memory**：`nvidia-smi` 看不到显存，用 `free -h` + `tegrastats`。F16 实运行约 22-25G（含 KV cache），加载前需要 ≥ 30G available

## 性能基线（用户实测 2026-05-10）

| 配置 | TTFT | 单步 | 5min 视频全双工 |
|---|---|---|---|
| Q4_K_M | （未量化） | 不卡 | 通过；智能弱 |
| F16 | （用户："速度也很快"） | 不卡 | 通过；智能 ≈ HF BF16 原版 |

滑窗证据 cpp_server.log：`[SW] system_prompt registered: preserve_length=82`，n_keep=79, n_ctx=8192。

## 常用命令

```bash
# 状态/日志/停
ssh spark_704 'cd ~/workspace/MiniCPM-V-CookBook/demo/web_demo/WebRTC_Demo && bash oneclick.sh status'
ssh spark_704 'cd ~/workspace/MiniCPM-V-CookBook/demo/web_demo/WebRTC_Demo && bash oneclick.sh logs cpp'
ssh spark_704 'cd ~/workspace/MiniCPM-V-CookBook/demo/web_demo/WebRTC_Demo && bash oneclick.sh stop'

# 切量化（不重启 oneclick 也能切，重启时读 LLM_QUANT 变量）
LLM_QUANT=Q8_0 bash route-c-up.sh

# 看 spark 资源
ssh spark_704 'free -h; ps aux | grep -E "llama-server|node|livekit" | grep -v grep'
```

## Mac 本机镜像（可选）

24G GGUF 已 rsync 到 `~/Documents/workspace/spark-minicpm/models/MiniCPM-o-4_5-gguf/`，未来 mac 端用 Metal 编译 llama.cpp-omni 时可直接复用，不必再下。
