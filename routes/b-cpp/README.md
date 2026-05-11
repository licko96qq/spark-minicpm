# 路线 B-cpp — MiniCPM-o Demo (Comni 分支) + llama.cpp-omni 后端

## 一句话定位

OpenBMB 官方 4 模式 demo（omni / audio-duplex / half-duplex / chat），后端切成 C++（`llama.cpp-omni`），功能最完整（含屏幕共享），但**无滑窗**——长会话 KV 爆后会 stop。

## 上游来源

```bash
git clone https://github.com/OpenBMB/MiniCPM-o-Demo
cd MiniCPM-o-Demo
git checkout Comni
```

- 分支：`Comni`
- spark 端部署路径：`/home/LChuang/workspace/MiniCPM-o-Demo-Comni/`
- 不引 submodule，`llama.cpp-omni` 已在 spark 另外 clone 到 `/home/LChuang/workspace/llama.cpp-omni/`

## 前置条件

- GPU：GB10（sm_120，unified memory 121G）或同级
- 可用内存 ≥ 30G（F16 模型 17G + KV 8G + runtime）——启动前建议 `docker stop` vLLM 类容器
- 系统依赖：`soundfile`, `PyYAML`, `Pillow`, `librosa`, `websockets`（已在 `.venv/base/` 装好，见 HANDOVER「依赖缺失修复完成」段）
- 模型：`MiniCPM-o-4_5-{F16,Q8_0,Q4_K_M}.gguf`，放 `/home/LChuang/workspace/MiniCPM-o-4_5-gguf/`
- 本机需配置 `spark_704` SSH 别名（见全局 `reference_ssh_hosts_inventory.md`）

## 部署步骤

1. spark 端 clone 仓库（如未部署）：
   ```bash
   ssh spark_704 'git clone https://github.com/OpenBMB/MiniCPM-o-Demo ~/workspace/MiniCPM-o-Demo-Comni && cd ~/workspace/MiniCPM-o-Demo-Comni && git checkout Comni'
   ```
2. 创建 venv 并装依赖（仓库自带 `requirements.txt`）：
   ```bash
   ssh spark_704 'cd ~/workspace/MiniCPM-o-Demo-Comni && python -m venv .venv/base && .venv/base/bin/pip install -r requirements.txt soundfile PyYAML Pillow librosa websockets'
   ```
3. 复制/链接 GGUF 模型到 `MODEL_DIR`。
4. 应用本路线 patch（屏幕共享 + sampling defaults + Q4_K_M 默认）：
   ```bash
   bash ../../scripts/apply-patches.sh b-cpp /home/LChuang/workspace/MiniCPM-o-Demo-Comni
   ```
5. 启动：`bash routes/b-cpp/up.sh`

## 启停

```bash
# 启
bash /Users/licko/Documents/workspace/cc_test/AllRealHub/spark-minicpm/routes/b-cpp/up.sh
# 停
bash /Users/licko/Documents/workspace/cc_test/AllRealHub/spark-minicpm/routes/b-cpp/down.sh
```

`up.sh` 会自动停掉路线 C（共享模型，内存只够一份），并建好本机 8040/22440 的 SSH tunnel。

## 端口表

| 服务 | 端口 | 备注 |
|---|---|---|
| gateway (HTTP) | 8040 | 浏览器入口 `http://localhost:8040/` |
| worker WS | 22440 | `ws://.../duplex_ws` 4 模式共用 |
| llama-server | 19080 | cpp backend 内部调用，不对外暴露 |

注意：`up.sh` 用 `--http` 模式启动 `start_all.sh`，是 HTTP 非 HTTPS。SSH tunnel 下浏览器视作 secure context，mic/camera/getDisplayMedia 均可用。

## 配置文件改动点

- `config.json` → `cpp_backend.llm_model`：量化档位文件名。默认 `MiniCPM-o-4_5-Q4_K_M.gguf`（path 固定在 patch 里），改档位后**重启服务**才生效。
  - F16：17G，智能最高，GB10 明显卡顿
  - Q8_0：8.2G，甜点档（路线 C2 / 用户实测验证）
  - Q4_K_M：4.7G，最流畅，智能略降
- `config.json` → `cpp_backend.ctx_size`：默认 8192。16K 反而会慢（attention 复杂度 ↑）。
- `static/omni/omni.html` 的 `stopOnKvShrink` 复选框默认已取消勾选（patch 0001 所做）——否则 KV 滑窗触发后前端会自动停会话。

## 该路线 patches 说明

见 `./patches/README.md`。一个 commit，5 个改动：sampling defaults（`lps=0.3 flc=0` 否则永远 LISTEN）、屏幕共享按钮、陪伴模式 prompt、Q4_K_M 默认档、备份文件 gitignore。

## 已知问题

- **模型永远 LISTEN 不 SPEAK**：根因是前端 preparePayload 未传 `listen_prob_scale` / `force_listen_count`，后端用默认值 `lps=1.0 flc=3`，F16/Q8/Q4 都 SPEAK 不出来。patch 0001 已修。详见 HANDOVER「真根因」段。
- **长会话 KV 滑窗停止**：Comni 分支本身的 KV pruning 实现会整个 stop session（没有滑窗保持 TTS/LLM 的能力）。patch 0001 默认去掉 `stopOnKvShrink`，但会话超长时仍可能炸。根治需改 C++ 源码（路线 D 规划包含 B-cpp + 自动 VAD，不包含滑窗；滑窗只有路线 C 有）。
- **打断 = 手动按钮**：Comni 分支的「Force Listen」按钮发 `force_listen: true` 让模型切回 listen。**没有自动 VAD**，说话不会自动打断。
- **Q8 + 高清视觉 + 屏幕共享 → 卡顿**：`max_slice_nums` 3 时每帧 256+ tokens，prefill +100ms。patch 0001 在 screen 模式强制 `max_slice_nums=1` + 自动关 HD。

上述问题详见 `docs/16-troubleshooting.md` 对应章节（若文档未建，参考 HANDOVER 路线 B-cpp 段）。

## 何时选这条路线

- 需要官方 4 模式界面（半双工 / 视频全双工 / 纯音频双工 / 文本）
- 需要**屏幕共享陪伴模式**（当前唯一实现）
- 会话时长 < 1 分钟可控，或测试场景不介意 KV 滑窗后停
- 不需要自动 VAD 打断（或接受手动按钮）
- 想快速试各量化档位（改 `config.json` 一行 + 重启）

**不选的场景**：长会话（> 1 分钟）视频全双工——用路线 C。需要自动 VAD 打断——等路线 D 实施完。
