# 路线 C — Patches 说明

## TL;DR

**路线 C 本身没有代码 patch 需要应用**。上游已 rebase 好所有必要改动，clone 对应 commit 即可运行。

## 为什么没有 patch

路线 C 的所有定制改动都已经合并进 spark 端上游仓库的两个 commit：

- `~/workspace/MiniCPM-V-CookBook/` baseline `5968457` → C2 定制 patch commit `c489953`（滑窗 + 陪伴 prompt warmup 注入）
- `~/workspace/llama.cpp-omni/` baseline `edef517` → gitignore patch commit `479cbc4`

本机 spark-minicpm 仓库 commit `58104b3` 保留了 snapshot 作 rollback。详见 HANDOVER「git 三层 baseline」段。

所以路线 C 的部署链路是：clone 上游到 spark（或同步已 checkout 的 commit）→ 直接 `up.sh` 启动。

## 启动脚本而非 patch 承载的改动

以下改动走**环境变量 / 启动脚本**实现，不靠 patch：

### 量化档位切换（commit 6c4c3a9 已包含在 `routes/c/up.sh` 里）

- `up.sh $1` 接收量化档位参数（`F16` / `Q8_0` / `Q4_K_M`）
- 通过 `LLM_MODEL=MiniCPM-o-4_5-<QUANT>.gguf` 环境变量透传给 `oneclick.sh` 和下游 `cpp_server`
- **不是**通过 `LLM_QUANT`（这是 oneclick.sh 的本地变量，**不会**透传到 cpp_server；cpp_server 走 `auto_detect` 优先 Q4_K_M）
- 这是踩过的坑：改 `LLM_QUANT=F16` 表面生效，实际 cpp_server 仍加载 Q4 模型

### 陪伴 prompt 注入

- `SYSTEM_PROMPT` 环境变量，短版 ~80 token（见 `routes/c/up.sh` 顶部 heredoc）
- 用 base64 透传避免 shell 对换行符转义失败
- `cpp_server` 在 warmup 阶段消费 `SYSTEM_PROMPT`，绕开 fast_resume 路径保证一定生效

### 5 端口 SSH tunnel

- `up.sh` 最后段建 `-L 8088 -L 7880 -L 9060 -L 9061` （外加 8021 由 livekit 内部暴露）
- Mac 浏览器访问 `https://localhost:8088/` 即可

## 什么情况下会出现 route-c patches

如果未来需要**改 spark 上游代码**（例如改 `tools/omni/omni.cpp` 的滑窗清 TTS KV 逻辑），则：

1. 在 spark 端改代码 + `git commit`
2. `git format-patch -1 HEAD` 导出到本目录，命名 `000X-<subject>.patch`
3. 在本 README 下补说明章节（应用顺序、影响文件、根因）
4. 修改 `scripts/apply-patches.sh` 支持 c 路线的 patch 链

当前阶段（2026-05-11）没有这个需求。

## 反向操作

不涉及。如果 `up.sh` 改崩了，`git log routes/c/up.sh` 可找到 6c4c3a9 等历史 commit 做 checkout。

## 相关文件

- `routes/c/up.sh`：启动脚本本体
- `routes/c/down.sh`：停止脚本
- `docs/08-route-c-llama-cpp-omni.md`：路线 C 架构文档
- `docs/11-user-feedback.md` / `docs/12-tuning-plan.md` / `docs/13-monitoring-tuning-results.md`：调优与监控记录
