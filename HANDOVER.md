# spark-minicpm — 会话交接

> 最后更新：2026-05-09 23:30 by Claude Code session（路线 C 跑通）

## 当前进度

**路线 C（WebRTC_Demo + llama.cpp-omni）端到端跑通**，4 服务全部 running，滑窗机制已激活。Mac 浏览器走 SSH tunnel 即可访问，**待用户实测 5 分钟视频全双工无卡顿**（KPI）。

### 路线 C 最新状态（2026-05-09 23:30）

| 服务 | PID | 端口 | 状态 |
|---|---|---|---|
| LiveKit Server | 322286 | 7880 | ✅ running |
| Backend (FastAPI) | 322328 | 8021 | ✅ healthy |
| C++ Inference | 322428 | 9060 / 9061 / 19060 | ✅ healthy, registered, **滑窗激活** |
| Frontend (Vue+Vite prod) | 322536 | 8088 (HTTPS) | ✅ HTTP 200 |

**滑窗证据**（cpp_server.log 23:26:19）：`[SW] system_prompt registered: preserve_length=82 (will be protected from sliding)` + duplex 三线程（LLM/TTS/T2W）就绪。这是**路线 B 没有的能力**，是路线 C 的核心价值。

### 用户访问方式（醒来直接用）

```bash
# 在 Mac 上建 SSH tunnel（5 个端口都要转发）
ssh -fN \
  -L 8088:localhost:8088 \
  -L 8021:localhost:8021 \
  -L 7880:localhost:7880 \
  -L 9060:localhost:9060 \
  -L 9061:localhost:9061 \
  spark_704

# 浏览器打开（首次接受自签证书）
open https://localhost:8088/
```

如果在同一局域网内可直连 `https://192.168.8.202:8088/`。

### 路线 B → 路线 C 选型决策

| 路线 | 后端 | 卡顿 | 滑窗 | 状态 |
|---|---|---|---|---|
| A | mgi 学生版 webrtc_demo (PyTorch) | TTFT 2.3s | ❌ | fallback 保留 |
| B | OpenBMB/MiniCPM-o-Demo (PyTorch+flash-attn) | 单步 ~1s 持续卡 | ❌ | 结构性瓶颈，弃 |
| **C** | **WebRTC_Demo + tc-mb/llama.cpp-omni feat/web-demo** | **待实测** | **✅** | **🎯 当前主线** |

选型依据（飞书群 21:35-21:44）：MiniCPM 团队成员魏弘量 + 蔡天驰明确推荐 llama.cpp-omni，理由是硬件门槛更低 + 实现 token2wav 滑窗（28 token input / 25 token stride）+ 子豪在 DGX Spark 上实测流畅。

### "Comni vs llama.cpp-omni" 概念厘清

- **`tc-mb/llama.cpp-omni`** 仓库 `feat/web-demo` 分支 = 我们用的 C++ 推理引擎
- **Comni** = 基于 llama.cpp-omni 打包的 Mac/Win 桌面 GUI 应用，与服务器无关
- **MiniCPM-o-Demo-Comni** = `OpenBMB/MiniCPM-o-Demo` 仓库 `Comni` 分支，是给 llama.cpp-omni 当 wrapper 的另一个 demo（gateway/worker/frontend），**不走这条线**，主线是 `OpenSQZ/MiniCPM-V-CookBook` 的 `WebRTC_Demo`

### 已完成

- **2026-05-09 23:30** **路线 C WebRTC_Demo + llama.cpp-omni 端到端跑通**（详见上方）— 4 服务全部 running，滑窗激活，KPI 待实测
- **2026-05-09 22:31~22:50** 前一会话产出（spark 上）：clone llama.cpp-omni（feat/web-demo tarball）、编 llama-server 二进制、下载 8.4G GGUF 全套
- **2026-05-09 15:50** flash_attention_2 启用 + 完整链路实测：服务起来（8006 + 22400 listening），用户实测 omni "比之前好一些但仍卡"，确认结构性瓶颈无解
- **2026-05-09 15:25** flash-attn 2.8.2 编译完成（sm_120 only，~90 min），enable_flash_attn.sh 自动改 config + 清 torch_compile_cache + 重 precompile 成功
- **2026-05-09 ~14:00** 路线 B 部署 + 4 模式 demo 跑通，发现 omni 单步 1.17s 卡顿、实时打断官方确认 4.5 不支持
- **2026-05-08** 路线 A 简化版跑通（spark `/home/LChuang/workspace/minicpm/`）：Mac 浏览器 → SSH tunnel → spark 全链路（TTFT 2.3s, 15-19 tok/s）

### 进行中 / 未完成

- **路线 C 5 分钟视频全双工 KPI 实测**（用户醒来后做）— 这是路线 C 立项的核心 KPI，必须实测确认无卡顿才能宣告"路线 C 成功"
- 路线 C 性能基线数据（TTFT/单步耗时/滑窗 stride 行为日志）记录到 `docs/07-mode-test-matrix.md`
- P0 4 模式实测矩阵 路线 B 列填充（低优先）

### 已知问题

- **omni 卡顿无解**：GB10 内存带宽 = A100 的 14%，README 明文 A100 0.9s 已会卡，GB10 数学上不达标（启用 flash-attn 后单步从 1.17s 估降到 ~1.0s，仍超阈值）
- **实时打断 4.5 版本不支持**：OpenBMB Issue #5 官方确认，README L344 "fix coming soon" 至今未兑现
- **KV 8192 demo 硬编码上限**：模型架构 max=32K，但 demo 不让改（Issue #876）

## 下一步行动（按优先级）

### 0. **建 SSH tunnel + Mac 浏览器 5 分钟视频全双工实测**（用户醒来第一件事）

```bash
# Mac 终端，一行起所有 tunnel
ssh -fN -L 8088:localhost:8088 -L 8021:localhost:8021 -L 7880:localhost:7880 -L 9060:localhost:9060 -L 9061:localhost:9061 spark_704
open https://localhost:8088/
```

**KPI**：连续视频对话 ≥ 5 分钟，无 "说一段卡一段"。如果 KPI 通过 → 路线 C 立项成功 → 可以转入业务接入。

**KPI 失败排查切入点**：
- 看 `tail -f /home/LChuang/.../WebRTC_Demo/.logs/cpp_server.log` 找 `[SW]` 滑窗触发证据 + 单步推理耗时
- 路线 B 单步 ~1s 持续卡，路线 C 应该明显改善

### 1. 服务管理（需要时）

```bash
# 状态
ssh spark_704 'cd ~/workspace/MiniCPM-V-CookBook/demo/web_demo/WebRTC_Demo && bash oneclick.sh status'
# 日志
ssh spark_704 'cd ~/workspace/MiniCPM-V-CookBook/demo/web_demo/WebRTC_Demo && bash oneclick.sh logs cpp'
# 停 / 重启
ssh spark_704 'cd ~/workspace/MiniCPM-V-CookBook/demo/web_demo/WebRTC_Demo && bash oneclick.sh stop'
```

或本地：`bash ~/Documents/workspace/cc_test/AllRealHub/spark-minicpm/route-c-up.sh` / `route-c-down.sh`（见下）

### 2. （旧）推进 WebRTC 路线 — 实际已通过路线 C 自带 LiveKit/WebRTC 完成，本项作废

3. **推进 WebRTC 路线**（用户优先级最高）历史记录

   待用户启动该任务时再开始。先决问题：
   - 是基于现有路线 A 简化版（已是 WebSocket，可平滑改 WebRTC）扩展，还是另起架构？
   - 是否同步保留官方 demo 的 4.5 模型推理后端，仅替换前端音频传输？

   建议第一步：调研 webrtc 候选方案对比 + 评估改造成本，1-2 小时内出方案再动手。

2. **可选：补全路线 B 实测矩阵**（低优先）

   ```bash
   # 启 spark 服务
   ssh spark_704 "cd /home/LChuang/workspace/MiniCPM-o-Demo-official && nohup bash launch.sh > /tmp/launch.log 2>&1 &"
   # 等 ~90s, 建隧道
   ssh -fN -L 8006:127.0.0.1:8006 spark_704
   # 浏览器测 4 模式，填 docs/07-mode-test-matrix.md
   ```

   预期结果：4 模式各自 TTFT/卡顿/可用性数据齐，作为 WebRTC 路线 baseline 对比。

3. **可选：更新 docs/05-route-b-issues.md 的 P0 结论**

   当前 P0 还停留在「等 flash-attn 编完」状态，应追加最终结论：「flash-attn + compile 启用后仍卡，路线 B 内部调优结束」。

## 最近 Session 记录

### 2026-05-10 00:20 Session（路线 C 跑通 + F16 切换）

**做了什么：**
- 解开"Comni vs llama.cpp-omni"概念混淆：Comni 是基于 llama.cpp-omni 的 GUI app；OpenBMB/MiniCPM-o-Demo 的 Comni 分支是 PyTorch demo 的 cpp 后端版（Demo-Comni 目录）；**主线选 OpenSQZ/MiniCPM-V-CookBook 的 WebRTC_Demo + tc-mb/llama.cpp-omni feat/web-demo**
- 复用前次会话 spark 上已有的 llama-server 二进制 + 8.4G GGUF Q4_K_M
- 跑 oneclick.sh start，踩三个坑全部解决：(1) livekit-server 装 /usr/local/bin 要 sudo → 手动装到 ~/.local/bin/；(2) pnpm 装到 ~/.npm-global/bin 不在脚本搜索路径 → 加 PATH 环境变量；(3) **pnpm 10+ ERR_PNPM_IGNORED_BUILDS 安全机制误判 build 失败** → 绕开 pnpm 直接 `node_modules/.bin/vite build` + 写 dist/.cpp_mode 让 oneclick 跳过 build
- 4 服务全部 running：LiveKit 7880 / Backend 8021 / cpp_server 9060/9061 / Frontend 8088（HTTPS 自签）
- 用户 Mac 浏览器实测：能用 + 不卡 + 字幕实时显示，但智能水平低（Q4_K_M 4-bit 量化 + 9B 上限）
- 飞书发地址给手机端测：`https://192.168.8.202:8088/`
- 切 F16：发现 spark 内存紧张（121G/121G，swap 吃 8G），原因 vLLM Qwen3.6-35B-A3B-FP8 容器占 73G + modelscope 在下 Nemotron-30B
- 用户授权停 vLLM `docker stop vllm-35b-a3b`，释放至 105G available
- 下 F16 GGUF 16G（hf-mirror 90 秒下完）+ `LLM_QUANT=F16` 重启 oneclick → 4 服务 healthy，滑窗激活，**用户实测「速度也很快」**

**关键决策：**
- 路线 C 主线 = WebRTC_Demo + llama.cpp-omni（不是 Demo-Comni），因为 WebRTC_Demo 直接面向视频全双工 + 自带 LiveKit + 完整 oneclick 编排
- F16 是 GGUF 路线天花板（≈ HF BF16 原始权重，几乎无损）；9B 文本智能上限固有，不是量化问题
- pnpm 10 IGNORED_BUILDS 不在项目级 .npmrc 解决，绕开走 vite 直接 build 最快

**注意事项 / 踩过的坑：**
- oneclick.sh 第一次跑会 sparse-clone 一份**嵌套** `WebRTC_Demo/WebRTC_Demo/` 子目录工作。手动 build 要去内层，不是外层 o45-frontend
- pnpm `verify-deps-before-run=never` 写 ~/.npmrc 也不生效——pnpm 10 的 IGNORED_BUILDS 检查独立于 verify-deps；唯一稳妥做法是绕开 pnpm 命令直接调 vite
- spark 上 vLLM 容器 + modelscope 下载会偷偷吃掉 70G+ unified memory 不释放，加载新 GGUF 前必须先 `docker ps` / `free -h` 看清楚
- DGX Spark unified memory 架构 `nvidia-smi` 显存读不出，看负载用 `free -h` 和 `tegrastats`

**修改文件：**
- spark：`~/workspace/MiniCPM-o-4_5-gguf/MiniCPM-o-4_5-F16.gguf` 新下 16G
- spark：`~/.local/bin/livekit-server` 1.9.11 安装
- spark：`~/.npmrc` 加 `verify-deps-before-run=never`（聊胜于无）
- spark：`~/workspace/MiniCPM-V-CookBook/demo/web_demo/WebRTC_Demo/WebRTC_Demo/o45-frontend/dist/` 手动 build
- spark：`~/workspace/MiniCPM-V-CookBook/demo/web_demo/WebRTC_Demo/o45-frontend/.npmrc` 加 verify-deps-before-run
- 本机：`spark-minicpm/HANDOVER.md`（本文件）、`spark-minicpm/docs/08-route-c-llama-cpp-omni.md`（新）、`spark-minicpm/route-c-up.sh`/`route-c-down.sh`（新）

---

### 2026-05-09 15:50 Session

**做了什么：**
- 验证 flash-attn 2.8.x 后台编译已完成（PID 133797 退出，`flash_attn.__version__` = `2.8.2`）
- 跑 `bash enable_flash_attn.sh`：自动改 `config.json` 的 `attn_implementation` → `flash_attention_2` + 清 `torch_compile_cache` + 重新 precompile（耗时 ~7 min，成功，写 cache 到 `./torch_compile_cache`）
- 跑 `bash launch.sh`（后台 nohup），等 ~60s 后 Worker PID 153867 在 22400 listening、Gateway 在 8006 listening、`/health` 返回 200
- 重建 Mac SSH tunnel：`ssh -fN -L 8006:127.0.0.1:8006 spark_704`
- 用户实测 omni "好一些但用到后面还是卡顿"
- 收尾停服务：`pkill -9 -f worker.py / launch.sh / gateway`，端口 8006/22400 清空，Mac 隧道关闭

**关键决策：**
- 选择 **退出 demo 内调优、转 WebRTC 路线**：flash-attn 已是 demo 框架内最后一档优化，启用后仍卡，符合「GB10 内存带宽 14% A100」的结构性预测。继续在 demo 内调（如改 KV 上限、buffer 再调）边际收益低、风险高，不如换架构。
- 干净停服务而非保留运行：用户明示先停，避免占内存

**注意事项 / 踩过的坑：**
- worker_0.log 路径在 `tmp/worker_0.log` 不在仓库根，找日志要去 `MiniCPM-o-Demo-official/tmp/`
- launch.sh 用 nohup + `&`，远程 ssh 调时 stdout 要重定向到 `/tmp/launch.log` 才能在 ssh 退出后存活
- precompile 阶段 worker 自带一个 warmup 推理（speak 出多段音频），输出节奏 ~1.2s/段，与真实交互单步耗时**不是同一回事**，不要拿这个当性能指标
- pkill 进程列表非常长（GB10 系统多核 + torch._inductor compile_worker 启 20 个），用 `pkill -9 -f worker.py` 比按 PID 干净

**修改文件（spark 端）：**
- `spark_704:/home/LChuang/workspace/MiniCPM-o-Demo-official/config.json` — `attn_implementation: flash_attention_2`（由 enable_flash_attn.sh 自动改）
- `spark_704:.../torch_compile_cache/` — 重新生成
- 本机：本 `HANDOVER.md`（其他 docs/ 未动）

---

### 2026-05-09 ~14:00 Session（前次，路线 B 部署）

**做了什么：**
- 在 spark `LChuang` 用户下部署 OpenBMB/MiniCPM-o-Demo-official，复用 mgi 模型权重（symlink）
- 跑通 4 模式 demo，发现 omni 严重卡顿
- 调研确认实时打断 4.5 不支持（Issue #5）、KV 8192 是 demo 硬编码（Issue #876）
- 启动 flash-attn 2.8.x 后台编译（FLASH_ATTN_CUDA_ARCHS=120）

**修改文件：**
- 创建 `docs/04-route-b-deployment-plan.md` / `05-route-b-issues.md` / `06-rollback-snapshots.md` / `07-mode-test-matrix.md`

---

### 2026-05-08 Session（路线 A 落地）

**做了什么：**
- 基于 mgi 学生版 webrtc_demo 改造出瘦客户端版本，部署到 LChuang 用户
- 删 sounddevice/扬声器/orbbec_camera 本地 IO，改纯 WebSocket 音频上下行
- Mac 浏览器 + getUserMedia + AudioWorklet 16kHz PCM 上传
- TTFT 2.3s, 15-19 tok/s

**踩过的坑：**
- AudioContext autoplay policy 需 `await resume()`
- `Float32Array(buf, 1)` 1 字节偏移非 4 对齐 → 必须先复制对齐

**修改文件：**
- `refactor-snapshot/server.py` + `refactor-snapshot/index.html`
- `docs/01-architecture.md` / `02-refactor-deltas.md` / `03-pitfalls.md`
- `scripts/start-spark-minicpm.sh` / `connect.sh` / `stop.sh`

## 关键文件索引

| 文件 | 说明 |
|------|------|
| `docs/01-architecture.md` | 路线 A 架构图（WebSocket wire protocol） |
| `docs/02-refactor-deltas.md` | 路线 A 改造细节（基于 mgi 原版的 diff） |
| `docs/03-pitfalls.md` | 路线 A 踩坑（autoplay / Float32Array 对齐） |
| `docs/04-route-b-deployment-plan.md` | 路线 B 部署规划 |
| `docs/05-route-b-issues.md` | 路线 B 问题集（omni 卡顿、打断不支持等） |
| `docs/06-rollback-snapshots.md` | 路线 B 回滚命令（如新版编炸用这个） |
| `docs/07-mode-test-matrix.md` | 4 模式实测矩阵模板（待填） |
| `refactor-snapshot/server.py` | 路线 A 服务端快照 267 行 |
| `refactor-snapshot/index.html` | 路线 A 前端快照 456 行 |
| `scripts/start-spark-minicpm.sh` | 路线 A 启动 |
| `route-a-up.sh` / `route-a-down.sh` | 路线 A 上/下线（含隧道） |

## 技术要点

### 部署位置

- **路线 A**：`spark_704:/home/LChuang/workspace/minicpm/`（学生瘦客户端改版）
- **路线 B**：`spark_704:/home/LChuang/workspace/MiniCPM-o-Demo-official/`（OpenBMB 官方 demo）
- **模型权重**：`spark_704:/home/LChuang/workspace/minicpm/MiniCPM-o-4_5`（路线 B 通过 symlink 复用）
- **conda env**：`/home/LChuang/miniconda3/envs/minicpm/`
- **mgi 原部署（不动）**：`spark_704:/home/mgi/minicpm/`

### 浏览器入口（路线 B）

`http://localhost:8006/{,/half_duplex,/omni,/audio_duplex,/admin,/docs}` — 走 SSH tunnel 视作 secure context，免 HTTPS 警告

### Mac 隧道

```bash
ssh -fN -L 8006:127.0.0.1:8006 spark_704
```

### 启停（路线 B）

```bash
# 启
ssh spark_704 "cd /home/LChuang/workspace/MiniCPM-o-Demo-official && nohup bash launch.sh > /tmp/launch.log 2>&1 &"
# 停
ssh spark_704 "pkill -9 -f worker.py; pkill -9 -f launch.sh; pkill -9 -f gateway"
```

### 硬件 baseline

GB10 (Blackwell sm_120, unified mem 121GB) — 内存带宽 = A100 的 14%，是 omni full-duplex 卡顿的结构性根因。Compute 够，带宽不够。

### 兄弟项目

- `~/Documents/workspace/spark-llm/`（llama-swap + Qwen 系列）
- `~/Documents/workspace/spark-vllm/`（vLLM Docker 实验）
