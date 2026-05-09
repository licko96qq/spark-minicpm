# 路线 B-cpp 部署手册 — MiniCPM-o-Demo (Comni 分支) + llama.cpp-omni

> 路线 B 的 cpp 后端版本：4 模式 PyTorch demo UI + llama.cpp-omni 推理后端
> 最后更新：2026-05-10

## 这是什么

OpenBMB 官方 `MiniCPM-o-Demo` 仓库的 **Comni 分支**，**C++ 后端版本**。等同于"路线 B 的 PyTorch worker 换成 llama.cpp-omni（cpp_server）"。

**vs 路线 C**：
| | 路线 C (WebRTC_Demo) | 路线 B-cpp (Demo-Comni) |
|---|---|---|
| 推理后端 | llama.cpp-omni F16（同） | llama.cpp-omni F16（同） |
| 前端 | Vue + LiveKit WebRTC | OpenBMB demo（4 模式：Omni/Audio-Duplex/Turnbased/Half-Duplex） |
| 协议 | WebRTC SFU（LiveKit） | WebSocket + 自带帧 |
| UI 风格 | 视频通话单一界面 | 4 个模式入口可切换 |
| Mobile | LiveKit mobile build | React mobile + mobile-omni 页面 |
| 适合场景 | 简单视频全双工 | 想测 4 种模式对比 / 想要 mobile React 体验 |

**资源约束**：与路线 C **互斥**，因 F16 ~22G 内存只够一份。切换需 stop + start，约 2-3 min。

## TL;DR

```bash
# 启路线 B-cpp（自动停路线 C 释放内存）
bash route-b-cpp-up.sh

# 停路线 B-cpp
bash route-b-cpp-down.sh

# 切回路线 C
bash route-b-cpp-down.sh && bash route-c-up.sh F16
```

浏览器打开：
- `https://localhost:8040/` — desktop 4 模式入口
- `https://localhost:8040/mobile/` — mobile React
- `https://localhost:8040/mobile-omni/` — mobile Omni

## 配置

`spark:/home/LChuang/workspace/MiniCPM-o-Demo-Comni/config.json`：

```json
{
    "backend": "cpp",
    "cpp_backend": {
        "llamacpp_root": "/home/LChuang/workspace/llama.cpp-omni",
        "model_dir":     "/home/LChuang/workspace/MiniCPM-o-4_5-gguf",
        "llm_model":     "MiniCPM-o-4_5-F16.gguf",
        "cpp_server_port": 19080,
        "ctx_size": 8192,
        "n_gpu_layers": 99
    },
    "service": {
        "gateway_port": 8040,
        "worker_base_port": 22440,
        "num_workers": 1
    }
}
```

复用同一份 GGUF（`/home/LChuang/workspace/MiniCPM-o-4_5-gguf/`，全套）和同一个 llama.cpp-omni（`/home/LChuang/workspace/llama.cpp-omni/build/bin/llama-server`），不重复占磁盘。

## 端口（不与路线 C 冲突）

| 服务 | 端口 |
|---|---|
| gateway (HTTP/HTTPS) | 8040 |
| worker | 22440 |
| llama-server (内部 cpp_server) | 19080 |

**vs 路线 C 端口**（路线 C：7880/8021/8088/9060/9061/19060）：完全不冲突，配置上能并存（但内存不够）。

## 前端 build

mobile React 已 build：
- `frontend/mobile/dist/` → publish 到 `static/mobile/`
- desktop 模式（`/`、`/duplex`、`/half-duplex` 等）静态资源在 `static/` 目录已自带

build 命令（如要重 build）：
```bash
ssh spark_704 'cd /home/LChuang/workspace/MiniCPM-o-Demo-Comni/frontend/mobile && \
  PATH=$HOME/.local/bin:$HOME/.npm-global/bin:$PATH \
  npm install --registry=https://registry.npmmirror.com && \
  npm run build:static'
```

## Python venv

`.venv/base/` symlink 到 `~/miniconda3/envs/minicpm/`（同路线 C 复用 minicpm conda env）。`install.sh` 已跑过。**首次启动时会再装一些 Comni-specific 依赖（livekit-agents 等），约 2-3 min。**

## 已知约束

1. **fast_resume 限制（与路线 C 同）**：cpp_server 启动后第一次 init 之后，后续 prompt override 走 fast_resume 不重设。陪伴 prompt 这种场景需要在 cpp_server 启动时一次性指定（暂未实现）
2. **--http 模式跳过 HTTPS 自签证书**：本机 LAN 直连用 https 没必要，加 `--http` 启动免证书
3. **资源排他**：路线 B-cpp 跟路线 C 不可同时跑

## git 状态

- spark `MiniCPM-o-Demo-Comni/` baseline `f4ff763`，含 config.json 和 mobile dist 已 build

## 回退

```bash
# Demo-Comni 改坏
ssh spark_704 'cd ~/workspace/MiniCPM-o-Demo-Comni && git reset --hard f4ff763'
```
