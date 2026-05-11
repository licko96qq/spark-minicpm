# 路线 A（已弃用） — mgi 学生版 webrtc_demo 瘦客户端改造

## 一句话定位

基于 mgi 学生搞的 webrtc_demo 改造成瘦客户端（PyTorch + BF16 18G）：Mac 浏览器 getUserMedia → WebSocket → spark 推理。TTFT 2.3s，15-19 tok/s 可用，但**没有滑窗机制**，长会话必崩，已弃用。

## 状态

❌ **已弃用**（2026-05-08 上线，2026-05-09 路线 B 接手）。保留在 `archive/route-a/` 作为历史快照参考。
- 快照代码：`archive/route-a/snapshot/server.py`（267 行）+ `archive/route-a/snapshot/index.html`（456 行）
- 启停脚本当时版本：`scripts/start-spark-minicpm.sh` / `connect.sh` / `stop.sh`（历史路径）

## 上游来源

- 原项目：mgi 同学本地 `webrtc_demo`（非公开，不在任何 git remote）
- 模型：`MiniCPM-o-4_5`（PyTorch BF16 HF 原始权重，~18G）
- 运行位置（历史）：`spark_704:/home/LChuang/workspace/minicpm/`（当时挂在 LChuang 用户下，与 mgi 原部署 `/home/mgi/minicpm/` 并存但独立）

## 前置条件（历史）

- GPU：GB10 或同级，unified memory 足够 load 18G PyTorch 模型 + runtime
- conda env：`/home/LChuang/miniconda3/envs/minicpm/`
- 无额外 C++ 依赖（PyTorch 直推，不过 llama.cpp）

## 当时的部署步骤

1. clone mgi 学生版 webrtc_demo 的瘦客户端改造分支到 `spark_704:~/workspace/minicpm/`
2. 删除本地 IO：`sounddevice` / 扬声器输出 / `orbbec_camera`（深度摄像头）全部干掉
3. 改造成纯 WebSocket 音频上下行（Mac 浏览器 `getUserMedia` + AudioWorklet 16kHz PCM 上传）
4. `bash scripts/start-spark-minicpm.sh` 启动 spark 端
5. 本机 `bash scripts/connect.sh` 建 SSH tunnel + 打开浏览器

## 启停（历史）

```bash
# 快照位置
bash /Users/licko/Documents/workspace/cc_test/AllRealHub/spark-minicpm/archive/route-a/snapshot/*.sh
```

（脚本本身保留历史版本仅供参考，不保证现在能跑——依赖 mgi 原版仓库目录结构）

## 端口表（历史）

| 服务 | 端口 | 备注 |
|---|---|---|
| Mac 浏览器 | 任意本地端口 | WebSocket client |
| spark WS server | 内部端口（8xxx） | FastAPI + uvicorn |

（具体端口当时未在 HANDOVER 固定，以 `scripts/start-spark-minicpm.sh` 为准）

## 性能数据（实测）

- TTFT（Time To First Token）：2.3s
- 稳态吞吐：15-19 tok/s
- 连续对话：< 30s 还行，再长就 KV 爆无恢复机制

## 弃用原因

1. **没有滑窗机制**：PyTorch 推理 + demo 级代码，KV 上限撞到直接 OOM / 崩溃，长会话不可用
2. **PyTorch BF16 结构性慢**：GB10 内存带宽 = A100 的 14%，BF16 全量权重每步都要跑完整 attention，没有 GGUF 量化路线的带宽节省优势
3. **打断 / VAD 无**：纯 half-duplex + 用户手动结束，达不到产品化交互要求
4. **mgi 学生改的、没有 upstream 可回归**：代码质量和维护性都不如换成 OpenBMB 官方 demo（→ 路线 B）或 OpenSQZ CookBook（→ 路线 C）

## 踩过的坑（留作前车）

- **AudioContext autoplay policy**：Chrome 要求 `await audioContext.resume()` 在用户交互后调用，否则 WebSocket 送过来的 PCM 直接不放音——且没有报错
- **Float32Array 1 字节偏移**：`new Float32Array(buf, 1)` 因为偏移不是 4 字节对齐，V8 直接 throw；必须**先复制对齐**（`const aligned = new Float32Array(new Uint8Array(buf.slice(1)).buffer)`）

这两个坑已整理到全局 memory `feedback_audio_websocket_pitfalls.md`。

## 何时选这条路线

**不要选**。仅在下列场景翻 archive 查代码：
- 要看"浏览器 → WebSocket → spark"最小瘦客户端框架怎么搭
- 研究 AudioWorklet 16kHz PCM 采样前端实现
- 对比路线 B/C/D 的工程复杂度基线

后续任何长会话 / VAD / 量化需求请直接走：
- 路线 B-cpp（屏幕共享 + 多模式）
- 路线 C（视频全双工 + 滑窗 + VAD）
- 路线 D（B-cpp + VAD 融合，规划中）
