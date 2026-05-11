# 路线 B-cpp — Patches 说明

本目录存放应用到 spark 端 `MiniCPM-o-Demo-Comni` 的 patch 文件。

## 应用方式

```bash
bash /Users/licko/Documents/workspace/cc_test/AllRealHub/spark-minicpm/scripts/apply-patches.sh b-cpp /home/LChuang/workspace/MiniCPM-o-Demo-Comni
```

脚本会 `git am` 或 `git apply` 按数字前缀顺序应用本目录下全部 `.patch` 文件。

## 应用顺序

当前只有一份 patch。序号预留给未来扩展（0002+）。

| 序号 | 文件 | 用途 |
|---|---|---|
| 0001 | `0001-screen-share-companion-mode.patch` | 屏幕共享 + sampling defaults + Q4_K_M + gitignore |

## patch 详情

### `0001-screen-share-companion-mode.patch`

1 个 commit（`596d1af` from licko@spark, 2026-05-11 21:06），合并了 5 个独立改动。合成一个 commit 便于一次性 revert。

#### 改动 1：sampling defaults（核心 bug 修复）

- **影响文件**：
  - `static/omni/omni-app.js`（第 1591 行附近，`startSession()` 构建 `preparePayload.config`）
  - `static/audio-duplex/audio-duplex-app.js`（第 958 行附近）
- **改动**：前端构建 `preparePayload.config` 时在 `length_penalty` 之外加：
  ```
  listen_prob_scale: 0.3,
  force_listen_count: 0,
  ```
- **为什么必须**：Comni 分支后端 `DuplexConfig` 默认值 `lps=1.0 flc=3`，在这个 sampling 分布下 F16/Q8/Q4 模型**永远输出 LISTEN** token，用户说话进来模型全程不 SPEAK。`lps=0.3 + flc=0` 是实测唯一稳定可用组合（`lps=0.4/0.5/0.6` 也失败，cliff 很尖）。详见 HANDOVER「真根因」段 + `/tmp/test_duplex_v6.py` CLI 验证结果。

#### 改动 2：屏幕共享按钮 + getDisplayMedia

- **影响文件**：
  - `static/omni/omni.html`（第 60 行附近，新增 `#screenShareBtn` 按钮）
  - `static/omni/omni-app.js`（新增 `_videoSource` 状态、`_openVideoStream` 的 `screen` 分支、`switchVideoSource()` 方法、帧率节流逻辑、按钮 wiring block 在文件末尾）
- **改动**：在 omni 视频栏加屏幕图标按钮，点击在 摄像头 ↔ 屏幕共享（`getDisplayMedia`）之间切换。screen 模式视频元素不 mirror，帧率节流到 ~0.5 fps（通过 `_frameSkipCounter % 2`，每两个 audio chunk 才抽 1 帧）。
- **为什么**：陪伴场景看屏幕解读论文/网页，摄像头用不上；全帧率对 GB10 带宽压力大。

#### 改动 3：屏幕模式自动注入陪伴 prompt

- **影响文件**：`static/omni/omni-app.js`（第 1633-1670 行附近，`startSession()` 内）
- **改动**：当 `window._globalVideoSource === "screen"` 时：
  - 自动关「高清视觉」复选框 + `setHDBtnState(false)`（避免 `max_slice_nums > 1` 的 prefill 卡顿）
  - 强制 `max_slice_nums = 1`
  - 用官网默认陪伴 prompt（`扮演一个具有以上声音特征的助手...`）覆盖用户自定义 systemPrompt
- **为什么**：用户实测 Q8 + 高清视觉 + 屏幕共享三合一时明显卡顿。屏幕共享陪伴模式默认简化视觉处理是合理默认。
- **历史**：v1 用长篇陪伴分析师 prompt 被用户反馈「太能说」，v2 改回官网默认 prompt。

#### 改动 4：config.json 量化档位

- **影响文件**：`config.json`
- **改动**：`cpp_backend.llm_model` 从 `MiniCPM-o-4_5-F16.gguf` 改成 `MiniCPM-o-4_5-Q4_K_M.gguf`
- **为什么**：用户偏好「流畅性 baseline」时想一启动就是 Q4。Q8 / F16 用户可以自己改回来，不强制。
- **注意**：跟用户口味相关，可改。改完**必须重启服务**加载新模型。

#### 改动 5：`.gitignore` 增加备份文件

- **影响文件**：`.gitignore`
- **改动**：加 `*.bak-*` 规则 + `tmp/` + `static/mobile/` + `frontend/mobile/package-lock.json`
- **为什么**：之前手改代码留的 `.bak-20260511` / `.bak-screen-share-20260511` 备份文件不应该入库污染 diff。

## 反向操作

```bash
# 在 spark 端 Demo-Comni 目录
cd /home/LChuang/workspace/MiniCPM-o-Demo-Comni
git revert 596d1af   # 如果已 git am
# 或
git checkout HEAD~1 -- config.json static/omni static/audio-duplex
```

## 后续如加 patch

序号 0002+，一个 patch 一个 commit，主题前缀 `feat(B-cpp):` / `fix(B-cpp):`。本 README 下同步补 `改动 N` 章节。
