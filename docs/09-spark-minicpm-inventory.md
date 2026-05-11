# spark MiniCPM 项目 inventory（路线 A/B/C/C2 归档）

> 更新：2026-05-10 01:30
> 主机：`spark_704` = <SPARK_LAN_IP> (DGX Spark, GB10 unified memory 128G)
> 当前主线：**路线 C（F16）**，路线 C2 后端 prompt 字段已就绪

## TL;DR — 看这一张表就够

| 路线 | 状态 | 后端 | 前端 | 启动入口 | 用途 |
|---|---|---|---|---|---|
| **A** | 🟡 fallback | mgi 学生原版 webrtc_demo (PyTorch) | 自带 HTML | spark `/home/LChuang/workspace/minicpm/` | 远程算力服务 v1，简化版 |
| **B** | ❌ 弃 | OpenBMB/MiniCPM-o-Demo (PyTorch+flash-attn) | 官方 4 模式 | spark `/home/LChuang/workspace/MiniCPM-o-Demo-official/` `bash launch.sh` | 结构性卡顿无解 |
| **C** | ✅ **当前主线** | tc-mb/llama.cpp-omni feat/web-demo（C++）+ GGUF F16 | OpenSQZ/MiniCPM-V-CookBook WebRTC_Demo（Vue+LiveKit） | 本机 `bash route-c-up.sh F16` | 视频全双工，速度快不卡，滑窗激活 |
| **C2** | ✅ 屏幕共享生效 / ⚠️ 陪伴 prompt 受 fast_resume 限制 | 同 C；后端透传 voice_clone_prompt 但 cpp_server fast_resume 不重设 | C 前端 dist 已带 `localStorage.videoSource='screen'` getDisplayMedia 分支 + apis/index.js 自动注入陪伴 prompt 字段 | 同 C，浏览器 console `localStorage.setItem('videoSource','screen')` + 刷新 | 桌面陪伴（先用屏幕共享，prompt 完美生效需 cpp_server 启动时注入） |
| **B-cpp** | ✅ 已实测跑通 + 待用 | 同 C（llama.cpp-omni F16） | OpenBMB/MiniCPM-o-Demo Comni 分支（4 模式 demo + mobile React） | 本机 `bash route-b-cpp-up.sh`（自动停 C） | 4 模式入口（Omni/Audio-Duplex/Turnbased/Half-Duplex），对比测试 |

## spark 上目录全景

```
/home/LChuang/workspace/
├── minicpm/                          184K  路线A  瘦客户端 → 真分离改造版（fallback）
├── MiniCPM-o-Demo-official/          2.0G  路线B  PyTorch demo（git, 已停, fallback）
├── MiniCPM-o-Demo-Comni/             133M  ⚠️ 备选  OpenBMB/MiniCPM-o-Demo Comni 分支（同等于路线B+cpp 的另一种实现），未启用
├── MiniCPM-o-4_5-gguf/                24G  GGUF 全套 Q4_K_M+F16+audio+tts+vision+token2wav（路线C/C2 用）
├── MiniCPM-o-4_5-gguf-ms-test/        92K  ⚠️ 残留  modelscope 测试目录，仅 README.md，可删
├── MiniCPM-V-CookBook/                792M  路线C  含 demo/web_demo/WebRTC_Demo/（主线）+ deployment/llama.cpp-omni/换音色指南
├── MiniCPM-V-CookBook-main.zip         78M  ⚠️ 残留  上述 zip 包，已解压，可删
└── llama.cpp-omni/                    299M  路线C/C2  C++ 推理引擎源码 + build/bin/llama-server（git 已 baseline edef517）
```

### 待清理（不影响主线）
- `MiniCPM-o-4_5-gguf-ms-test/` — modelscope 测试残留，删
- `MiniCPM-V-CookBook-main.zip` — 已解压，删

### 不要删
- 4 个 fallback 目录（minicpm / Demo-official / Demo-Comni / 各自 README）
- llama.cpp-omni 源码（路线 C2 万一要改 prompt 还要重编）

---

## 路线 A — 瘦客户端真分离（fallback）

**位置**：`/home/LChuang/workspace/minicpm/`
**架构**：Mac 浏览器（getUserMedia）→ WebSocket → spark FastAPI（PyTorch transformers）→ Token2Wav
**模型**：symlink 自 `/home/mgi/minicpm/MiniCPM-o-4_5/`（18GB BF16 PyTorch 权重，**不在 GGUF 里**）

启动：
```bash
ssh spark_704
conda activate minicpm
export MINICPM_CONFIG=/home/LChuang/workspace/minicpm/deploy/config.yaml
cd /home/LChuang/workspace/minicpm/webrtc_demo
nohup python -m uvicorn server:app --host 127.0.0.1 --port 8765 > ../server.log 2>&1 &
# Mac 端建 tunnel
ssh -L 8765:127.0.0.1:8765 -N spark_704
open http://localhost:8765/
```

**用途**：路线 C 出问题时的 fallback；TTFT 2.3s, 15-19 tok/s。**当前不启用。**

---

## 路线 B — OpenBMB 官方 demo（已弃）

**位置**：`/home/LChuang/workspace/MiniCPM-o-Demo-official/`（git）
**架构**：PyTorch + flash-attn 2.8.2 + torch.compile + buffer 1500ms
**问题**：GB10 内存带宽 = A100 的 14%，结构性卡顿无解。详见 `docs/05-route-b-issues.md` `docs/03-pitfalls.md`

启动（**不推荐**，仅作 fallback 测试）：
```bash
ssh spark_704 "cd /home/LChuang/workspace/MiniCPM-o-Demo-official && nohup bash launch.sh > /tmp/launch.log 2>&1 &"
```

**用途**：历史参考 + 路线 C 性能对比基线。**当前不启用，残留日志在 tmp/。**

---

## 路线 C — WebRTC_Demo + llama.cpp-omni（**当前主线**）

**位置**：`/home/LChuang/workspace/MiniCPM-V-CookBook/demo/web_demo/WebRTC_Demo/WebRTC_Demo/`（注意嵌套子目录！oneclick 第一次跑会 sparse-clone 一份内层）
**架构**：详见 `docs/08-route-c-llama-cpp-omni.md`
**编译产物**：`~/workspace/llama.cpp-omni/build/bin/llama-server`（feat/web-demo 分支 tarball 编出，git baseline edef517）

启停（本机）：
```bash
bash route-c-up.sh F16        # 默认 F16
bash route-c-up.sh Q4_K_M     # 切回快但智能弱
bash route-c-down.sh
```

**端口**：7880(LiveKit) / 8021(Backend FastAPI) / 9060(cpp_server) / 9061(health) / 8088(Frontend HTTPS) / 19060(llama-server 内部)

**git 状态**（spark 端）：
- `MiniCPM-V-CookBook/demo/web_demo/WebRTC_Demo/WebRTC_Demo/` — git baseline `5968457`（路线 C 跑通快照）
- `llama.cpp-omni/` — git baseline `edef517`（C++ 源码原版）

---

## 路线 C2 — 屏幕共享 + 陪伴 prompt

> 路线 C 的扩展，不破坏 C。

**已完成（2026-05-10）**：
- ✅ 后端 prompt 透传：`cpp_server/minicpmo_cpp_http_server.py` 加 `voice_clone_prompt` + `assistant_prompt` 两个可选字段，调 omni_init 时透传给 C++（**C++ 端 server.cpp:5879-5891 原生支持**，**不用重编**）
- ✅ 默认值 None → 行为完全等同路线 C
- ✅ Python 语法 OK，已 patch

**待完成（用户休息中暂不动代码）**：

### A. 前端屏幕共享（spark `o45-frontend/src/hooks/useLiveKit.js`）

最小可用改动 — 5 处：

```js
// 改 1: 顶部 import 行 5 加入 LocalVideoTrack（已有 createLocalVideoTrack 同名空间）
// （若 livekit-client 未导出 LocalVideoTrack，则改用 createLocalScreenTracks）
import { ..., LocalVideoTrack, ... } from 'livekit-client';

// 改 2: state 定义（行 ~310）加字段
const state = reactive({
    ...,
    videoSource: 'camera',  // 'camera' | 'screen'
    ...
});

// 改 3: createLocalVideoTrackWithReadyCheck(...) 调用前包一层（行 3571 附近）
let videoTrack;
if (state.videoSource === 'screen') {
    const ds = await navigator.mediaDevices.getDisplayMedia({
        video: { frameRate: { ideal: 10, max: 15 } },  // 屏幕共享低帧率即可
        audio: false
    });
    const raw = ds.getVideoTracks()[0];
    videoTrack = new LocalVideoTrack(raw, undefined, false);  // LiveKit 包装
    // 用户停止屏幕共享时同步停 track
    raw.addEventListener('ended', () => { state.videoEnabled = false; videoTrack.stop(); });
} else {
    videoTrack = await createLocalVideoTrackWithReadyCheck({ ...原参数... });
}
tracks.push(videoTrack);
```

### B. 前端 UI 切换按钮（`VideoCall.vue` 行 30 `<div class="switch-camera">` 旁）

```vue
<div class="switch-source" @click="toggleVideoSource">
    {{ state.videoSource === 'screen' ? '📺 屏幕中' : '📷 摄像头' }}
</div>
```

```js
const toggleVideoSource = () => {
    state.videoSource = state.videoSource === 'camera' ? 'screen' : 'camera';
    // 重新 publish video track（断开旧 track + 走 createLocalVideoTrackWithReadyCheck）
    restartVideoTrack();  // 已有方法，搜 keyword "restartVideoTrack" 在 useLiveKit.js
};
```

### C. 陪伴 prompt 注入（前端调 init_sys_prompt 时带字段）

定位前端调 `/init_sys_prompt` 的位置（grep `init_sys_prompt` 或 `initSysPrompt`），在 request body 加：

```js
const COMPANION_PROMPT = "<|im_start|>system\nStreaming Duplex Conversation! 你是用户的桌面陪伴助手。你能看到他屏幕上的内容（视频、游戏、网页、文档），主动评论、解说、给建议。回应要简短、轻松、有温度。\n<|audio_start|>";

await fetch('/api/inference/.../init_sys_prompt', {
    method: 'POST',
    body: JSON.stringify({
        media_type: 'omni',
        ...(state.videoSource === 'screen' ? { voice_clone_prompt: COMPANION_PROMPT } : {})
    })
});
```

### D. 改完后

```bash
# 在 spark 内层 frontend 重 build（绕开 pnpm IGNORED_BUILDS）
ssh spark_704 'cd /home/LChuang/workspace/MiniCPM-V-CookBook/demo/web_demo/WebRTC_Demo/WebRTC_Demo/o45-frontend && \
  PATH=$HOME/.local/bin:$HOME/.npm-global/bin:$PATH VITE_CPP_MODE=duplex node_modules/.bin/vite build --mode prod-external && \
  echo -n duplex > dist/.cpp_mode'

# 重启 frontend（其他 3 服务不动）
ssh spark_704 "cd /home/LChuang/workspace/MiniCPM-V-CookBook/demo/web_demo/WebRTC_Demo && pkill -f 'node serve-prod' && \
  cd WebRTC_Demo/o45-frontend && nohup node serve-prod.mjs --port 8088 --backend 8021 --livekit 7880 > ../../.logs/frontend.log 2>&1 & disown"
```

### E. 备份 + 回退

改前先：
```bash
ssh spark_704 'cd ~/workspace/MiniCPM-V-CookBook/demo/web_demo/WebRTC_Demo/WebRTC_Demo && cp o45-frontend/src/hooks/useLiveKit.js o45-frontend/src/hooks/useLiveKit.js.before-c2 && cp o45-frontend/src/views/home/components/VideoCall.vue o45-frontend/src/views/home/components/VideoCall.vue.before-c2'
```

改坏了：`git reset --hard 5968457`（baseline）或 `git reset --hard c489953`（C2 后端 prompt 已 commit 后的状态）

**陪伴 prompt 示例**（duplex 模式）：
```
voice_clone_prompt = "<|im_start|>system\nStreaming Duplex Conversation! 你是用户的桌面陪伴助手。你能看到他屏幕上的内容（视频、游戏、网页、文档），主动评论、解说、给建议。回应要简短、轻松、有温度。\n<|audio_start|>"
assistant_prompt = "<|audio_end|><|im_end|>\n"   # 保持原值
```

**测试方法**（屏幕共享前端没改时也能测后端 prompt）：
```bash
# 直接 curl backend 调 init_sys_prompt 带自定义 prompt
ssh spark_704 'curl -X POST http://localhost:8021/api/inference/<SPARK_LAN_IP>:9060/init_sys_prompt \
  -H "Content-Type: application/json" \
  -d "{\"media_type\":\"omni\",\"voice_clone_prompt\":\"<|im_start|>system\nStreaming Duplex Conversation! 你是用户的桌面陪伴助手。\n<|audio_start|>\"}"'
```

---

## 通用环境（spark 端）

| 资源 | 路径 / 版本 |
|---|---|
| Python venv（路线 C/C2） | `/home/LChuang/miniconda3/envs/minicpm/bin/python` 3.10.20 |
| Python venv（路线 A） | 同上 minicpm env |
| livekit-server | `~/.local/bin/livekit-server` v1.9.11 |
| Node | v24.14.1（系统） |
| pnpm | `~/.npm-global/bin/pnpm`（须 export PATH） |
| llama.cpp-omni 编译产物 | `~/workspace/llama.cpp-omni/build/bin/llama-server` |

## 本机镜像（Mac）

| 资源 | 本机路径 |
|---|---|
| GGUF 全套 24G | `~/Documents/workspace/spark-minicpm/models/MiniCPM-o-4_5-gguf/` |
| 项目文档 + 启停脚本 | `~/Documents/workspace/cc_test/AllRealHub/spark-minicpm/`（git，commit `58104b3`） |
| llama.cpp-omni 源码 | ❌ 未镜像（如要 mac Metal 编译，从 `https://github.com/tc-mb/llama.cpp-omni.git` clone feat/web-demo 分支） |

## 紧急回退命令

```bash
# 路线 C 后端 prompt patch 回退（C2 改坏路线 C）
ssh spark_704 'cd ~/workspace/MiniCPM-V-CookBook/demo/web_demo/WebRTC_Demo/WebRTC_Demo && git reset --hard 5968457'

# llama.cpp-omni 源码回退
ssh spark_704 'cd ~/workspace/llama.cpp-omni && git reset --hard edef517'

# 单文件回退（粒度更细）
ssh spark_704 'cd ~/workspace/MiniCPM-V-CookBook/demo/web_demo/WebRTC_Demo/WebRTC_Demo && cp cpp_server/minicpmo_cpp_http_server.py.baseline cpp_server/minicpmo_cpp_http_server.py'
```
