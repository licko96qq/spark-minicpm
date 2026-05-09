# 06 — 回滚快照

> 每次大改 config / 装新包前，留一份 working state 快照。出问题可秒回滚。

---

## SNAPSHOT-01 · 2026-05-09 13:30 · compile=true + buffer 800ms（**已知能起服务，omni 仍卡**）

**对应实测状态**：用户实测 omni 严重卡顿、audio 几乎流畅、打断不可用

### config.json
```json
{
  "model": {
    "model_path": "/home/LChuang/workspace/MiniCPM-o-Demo-official/models/MiniCPM-o-4_5",
    "pt_path": null,
    "attn_implementation": "auto"
  },
  "audio": {
    "ref_audio_path": "assets/ref_audio/ref_minicpm_signature.wav",
    "playback_delay_ms": 800,
    "chat_vocoder": "token2wav"
  },
  "service": {
    "gateway_port": 8006,
    "worker_base_port": 22400,
    "max_queue_size": 1000,
    "request_timeout": 300.0,
    "compile": true,
    "data_dir": "data"
  },
  "duplex": {"pause_timeout": 60.0}
}
```

### 实际运行时 attn
- `attn_implementation: auto` → `sdpa`（PyTorch 内置，无 flash-attn）
- log: `Base model loaded in 6.1s, attn_implementation=sdpa, quantized=False`

### 包版本（spark `/home/LChuang/miniconda3/envs/minicpm/`）
```
accelerate    1.12.0
fastapi       0.135.3
minicpmo-utils 1.0.5
torch         2.11.0+cu130
torchaudio    2.11.0+cu130
torchcodec    0.11.1+cu130
torchvision   0.26.0+cu130
transformers  4.51.0
triton        3.6.0
websockets    16.0
```

### torch_compile_cache
- 大小：209 MB
- 路径：`/home/LChuang/workspace/MiniCPM-o-Demo-official/torch_compile_cache/`
- 状态：✅ 已生成（precompile.py 跑了 430s，warmup 完成）

### 回滚命令（如果后续装包炸了）
```bash
ssh spark_704
cd /home/LChuang/workspace/MiniCPM-o-Demo-official

# 1. 恢复 config
cat > config.json <<'EOF'
{
  "model": {
    "model_path": "/home/LChuang/workspace/MiniCPM-o-Demo-official/models/MiniCPM-o-4_5",
    "pt_path": null,
    "attn_implementation": "auto"
  },
  "audio": {
    "ref_audio_path": "assets/ref_audio/ref_minicpm_signature.wav",
    "playback_delay_ms": 800,
    "chat_vocoder": "token2wav"
  },
  "service": {
    "gateway_port": 8006,
    "worker_base_port": 22400,
    "compile": true
  },
  "duplex": {"pause_timeout": 60.0}
}
EOF

# 2. 如果包被升级炸了，回到当前版本
.venv/base/bin/pip install --force-reinstall \
  torch==2.11.0 torchvision==0.26.0 torchaudio==2.11.0 torchcodec==0.11.1 \
  transformers==4.51.0 accelerate==1.12.0

# 3. 如果 flash-attn 装坏了 LLM，卸了即可
.venv/base/bin/pip uninstall -y flash-attn

# 4. 重启
bash launch.sh
```

---

## 准备实施的改动（SNAPSHOT-02 待生成）

1. `playback_delay_ms` 800 → **1500**
2. 装 `flash-attn>=2.6`（aarch64 wheel 可能没有，预备源码编译）
3. 若装成功：`attn_implementation` auto/sdpa → **flash_attention_2**
4. 重启服务，实测 omni 是否流畅

**预期收益**：
- buffer 多 700ms → 掩盖更多偶发超阈值
- flash-attn → 单步从 1.17s 降 5-15% → ~1.0-1.1s（仍可能 >1s 但更接近阈值）
