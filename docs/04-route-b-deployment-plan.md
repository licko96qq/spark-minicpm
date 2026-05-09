# 路线 B：在 Spark 部署 OpenBMB/MiniCPM-o-Demo 官方完整版

> 上次会话已跑通路线 A（简化版 webrtc_demo，half-duplex）。本计划在 spark 上**并存部署**官方完整版（4 模式 + full-duplex + Gateway/Worker 架构），不动现有简化版。

## Context

**目标**：在 spark GB10 上跑通官方 demo 的 `/omni`（视觉+音频全双工）和 `/audio_duplex`（音频实时全双工），让 Mac 浏览器通过 SSH tunnel 体验「模型自主决定何时说话」的 proactive interaction 能力。

**与现有的关系**：
- 现有路线 A：`/home/LChuang/workspace/minicpm/`（uvicorn:8765，仅 half-duplex）—— 不动
- 现有 mgi 学生版：`/home/mgi/minicpm/`（瘦客户端模式）—— 不动
- 新增路线 B：`/home/LChuang/workspace/MiniCPM-o-Demo-official/`（Gateway:8006 + Worker:22400）

## 已完成的环境探查（无需重做）

| 项 | 结论 | 来源 |
|---|---|---|
| 平台 | aarch64 (GB10 Grace Blackwell) | `uname -m` |
| 磁盘 | 3.1T 空闲 | `df -h /home/LChuang` |
| 现有 torch | 2.7.1+cu128 (vs 官方要求 2.8.0) | `python -c 'import torch'` |
| 端口 8006/22400/22401 | 全部空闲 | `ss -tnlp` |
| ffmpeg | 6.1.1 已装 | `ffmpeg -version` |
| 模型权重 | 18GB 已在 `/home/LChuang/workspace/minicpm/MiniCPM-o-4_5`（symlink 自 mgi） | 路线 A 已验证 |
| ref_audio | 仓库自带 `assets/ref_audio/ref_minicpm_signature.wav` (192KB) | github API |
| HF Hub 访问 | 不依赖（用本地权重） | — |

## 关键决策（已替用户做主）

| 决策点 | 选择 | 理由 |
|---|---|---|
| 部署目录 | `/home/LChuang/workspace/MiniCPM-o-Demo-official/` | 与简化版隔离，可并存 |
| Python env | install.sh 自建的 `.venv/base`（独立 venv） | 官方推荐路径；不污染现有 minicpm conda |
| HTTPS vs HTTP | `--http` + SSH tunnel | 与路线 A 一致；浏览器 `localhost` 视作 secure context，免自签证书 |
| torch.compile | **先关**（`compile: false`） | Blackwell sm_100 上 Triton 编译未验证；先跑通再优化 |
| 模型路径 | symlink 复用 `MiniCPM-o-4_5` | 不重下 18GB |
| GPU | 单 GPU，CUDA_VISIBLE_DEVICES=0 | spark 只有一块 GB10 |
| Gateway 端口 | 8006（默认） | 端口空闲，与路线 A 8765 不冲突 |
| Worker 端口 | 22400（默认） | 内部 HTTP，不暴露 |

## 实施步骤（按门控顺序，每步有 go/no-go）

### Step 1 · 拉代码 + 预备目录（5 min）
```bash
ssh spark_704
cd /home/LChuang/workspace
git clone https://github.com/OpenBMB/MiniCPM-o-Demo.git MiniCPM-o-Demo-official
cd MiniCPM-o-Demo-official
mkdir -p models
ln -s /home/LChuang/workspace/minicpm/MiniCPM-o-4_5 models/MiniCPM-o-4_5
```
**Gate**：`ls models/MiniCPM-o-4_5/config.json` 能读到 → 通过

### Step 2 · 安装 Python 依赖（**最高风险点**）
官方 `install.sh` 强制装 `torch==2.8.0`。aarch64 上 PyTorch 2.8.0 cu128 wheel 不一定在 PyPI。

**主路径**：直接跑 `bash install.sh`（venv 内自动安装）
```bash
bash install.sh 2>&1 | tee install.log
```

**门控判断**：检查 `install.log` 里 PyTorch 安装是否成功
- ✅ 若成功 → 继续 Step 3
- ❌ 若 `torch==2.8.0` 装不上（aarch64 无 wheel，要从源码编译几小时） → 回退方案 A

**回退方案 A**（torch 2.8.0 不可用）：
```bash
# 从已验证的 minicpm conda env 克隆，再手动装其他依赖
source /home/LChuang/miniconda3/etc/profile.d/conda.sh
conda create --clone minicpm -n minicpmo-demo
conda activate minicpmo-demo
# 把 .venv/base 软链到 conda env，让 start_all.sh 找得到
mkdir -p .venv && ln -s /home/LChuang/miniconda3/envs/minicpmo-demo .venv/base
# 安装非 torch 依赖（torch 2.7.1 应该兼容大多数）
.venv/base/bin/pip install -r requirements.txt --no-deps
.venv/base/bin/pip install "minicpmo-utils[all]>=1.0.5" "fastapi>=0.128.0" "websockets>=16.0" "pydantic>=2.11.0"
```

**回退方案 B**（minicpmo-utils 装不上）：
- 单独装组件：`pip install vocos s3tokenizer ChatTTS librosa soundfile`
- 看 minicpmo-utils 的 setup.py extras_require[all]，逐个对应

### Step 3 · 配置 config.json（2 min）
```bash
cp config.example.json config.json
# 用 python 改写 model_path
python3 -c "
import json
with open('config.json') as f: c = json.load(f)
c['model']['model_path'] = '/home/LChuang/workspace/MiniCPM-o-Demo-official/models/MiniCPM-o-4_5'
c['service']['compile'] = False  # 先关 torch.compile
c['service']['gateway_port'] = 8006
c['service']['worker_base_port'] = 22400
with open('config.json', 'w') as f: json.dump(c, f, indent=4, ensure_ascii=False)
"
cat config.json
```
**Gate**：`config.json` 内 `model_path` 是绝对路径，文件存在

### Step 4 · 启动服务（关键验证点，~3 min 模型加载）
```bash
CUDA_VISIBLE_DEVICES=0 bash start_all.sh --http  # 强制 HTTP，配合 SSH tunnel
```
脚本流程：
1. 起 Worker 0（GPU=0，port 22400），加载模型 ~30-90s
2. `curl http://localhost:22400/health` 等到 `model_loaded:true`
3. 起 Gateway（port 8006），代理 WS 到 Worker
4. `curl http://localhost:8006/health` 验证

**Gate**：`tmp/worker_0.log` 出现 "Model loaded" 且 `/health` 返回正常 → 通过

**典型失败排查**：
- aarch64 缺 wheel → 看 `tmp/worker_0.log` 找 `ImportError`，按方案 B 单装
- CUDA OOM → GB10 unified memory 100GB+ 应该不会，看 `nvidia-smi`
- `cosyvoice2`/`token2wav` 模型加载失败 → 看 `chat_vocoder` 改成 `cosyvoice2` 或反之
- Triton 报错 → 确认 `compile: false`

### Step 5 · Mac 端 SSH tunnel + 浏览器验证（5 min）
```bash
# Mac 本机
ssh -L 8006:127.0.0.1:8006 -N spark_704 &
open http://localhost:8006/  # 注意是 http 不是 https
```

**测试矩阵**：
| URL | 模式 | 验证项 |
|---|---|---|
| `http://localhost:8006/` | Turn-based Chat | 文本+语音对话，按钮触发 |
| `http://localhost:8006/half_duplex` | Half-Duplex Audio | VAD 自动检测 |
| `http://localhost:8006/omni` | **Omni Full-Duplex** | 视觉+音频，模型主动说话 |
| `http://localhost:8006/audio_duplex` | Audio Full-Duplex | 实时音频双工，可打断 |
| `http://localhost:8006/admin` | Dashboard | 看 worker 状态 |
| `http://localhost:8006/docs` | API docs | FastAPI swagger |

**Gate**：`/omni` 模式能跑（即使有卡顿）→ 路线 B 跑通

### Step 6 · 性能调优（可选，跑通后再做）
若 omni 模式延迟 > 1s 卡顿明显：
```bash
# 一次性预编译（~15 min）
CUDA_VISIBLE_DEVICES=0 TORCHINDUCTOR_CACHE_DIR=./torch_compile_cache .venv/base/bin/python precompile.py
# 然后 config.json 设 "compile": true，重启服务
```
GB10 上 Triton 是否能编译成功是未知数。失败的话保持 sdpa + compile:false。

## 风险登记（每条都有应对）

| 风险 | 概率 | 影响 | 应对 |
|---|---|---|---|
| PyTorch 2.8.0 无 aarch64 wheel | 中 | 阻塞 | 回退方案 A，用 2.7.1（transformers 4.51 兼容） |
| minicpmo-utils[all] 部分依赖编译失败 | 中 | 阻塞 | 方案 B 单组件装 + 跳过 cosyvoice2 走 token2wav |
| Triton/torch.compile Blackwell 不支持 | 高 | 性能不达标 | `compile: false` 接受 ~0.9s/step，仍可用 |
| Worker 模型加载 > 90s 触发健康检查超时 | 低 | start_all.sh 报 FAILED | 改 start_all.sh 把 MAX_RETRIES=3000 → 6000 |
| HTTPS 强制要求未真正 `--http` 起来 | 低 | 浏览器报警 | 走 SSH tunnel + http://localhost 即可 |
| 与路线 A 资源冲突（同 GPU） | 低 | OOM | 跑 B 时确保 A 服务停了：`pkill -f 'uvicorn server:app'` |

## 验证协议（用户明天验收用）

跑通门槛（**任一条达到即算路线 B 落地**）：
- [ ] `http://localhost:8006/half_duplex` 能正常对话（语音→TTS 回复）
- [ ] `http://localhost:8006/omni` 能开摄像头+麦克风，模型有反应（不要求性能完美）

加分项（不强制）：
- [ ] `/audio_duplex` 模式实测可打断
- [ ] 启用 torch.compile 后延迟 < 0.6s

## 关键文件路径

### 远程 (spark)
| 路径 | 作用 |
|---|---|
| `/home/LChuang/workspace/MiniCPM-o-Demo-official/` | 路线 B 工作目录（新建） |
| `→/.venv/base/` | install.sh 创建的独立 Python venv |
| `→/config.json` | 服务配置（从 example copy 后改 model_path） |
| `→/models/MiniCPM-o-4_5` | symlink → `/home/LChuang/workspace/minicpm/MiniCPM-o-4_5` |
| `→/tmp/worker_0.log` | Worker 运行日志（最重要的排错入口） |
| `→/tmp/gateway.log` | Gateway 日志 |
| `→/torch_compile_cache/` | 可选，启用 compile 后存 Triton kernel |

### 本机文档
| 路径 | 用途 |
|---|---|
| `~/Documents/workspace/cc_test/AllRealHub/spark-minicpm/` | 现有归档（路线 A），路线 B 跑通后扩展为：
| `→/scripts/start-official.sh` | （待写）一键起官方版 |
| `→/scripts/connect-official.sh` | （待写）SSH tunnel 8006 |
| `→/docs/04-official-vs-simplified.md` | （待写）对比体验 |

## 回滚

完全失败的话：
```bash
ssh spark_704
pkill -f 'gateway.py|worker.py'      # 关服务
rm -rf /home/LChuang/workspace/MiniCPM-o-Demo-official  # 删目录
conda env remove -n minicpmo-demo 2>/dev/null  # 若用了方案A
```
路线 A 完全不受影响（独立目录、独立 conda env、独立端口）。

## 不在本次范围

- systemd 持久化（先手动 `start_all.sh`）
- 多 GPU（spark 只有一块）
- 反向代理 / 公网暴露（永远走 SSH tunnel）
- 修改 demo 源码（只改 config.json）

## 给明天醒来的我自己

进项目时直接：
```bash
ssh spark_704 "ls /home/LChuang/workspace/MiniCPM-o-Demo-official/ 2>/dev/null"
```
- 没有目录 → 从 Step 1 开始
- 有目录但 `tmp/` 没东西 → 从 Step 4 开始（已装好）
- 有 `tmp/` 日志 → 看日志判断卡哪儿

执行权限要点：
- `bash install.sh` 可能跑 5-15 分钟，去吃饭可以
- 模型加载 30-90s，不要急着 ctrl-c
- 失败先看 `tmp/worker_0.log` tail 50 行
