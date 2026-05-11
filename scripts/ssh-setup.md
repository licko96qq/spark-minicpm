# SSH 配置 & Tunnel 速查

本机（Mac）↔ spark_704（DGX Spark, GB10）走 SSH tunnel 的端口转发约定。

## 1. SSH key 准备

```bash
# 本机生成 key（已有就跳过）
ssh-keygen -t ed25519 -C "licko@mac-$(date +%Y%m%d)"

# 把 public key 推到远端（远端需已知密码或其他登录方式）
ssh-copy-id -i ~/.ssh/id_ed25519.pub LChuang@<spark-ip>
```

## 2. 本机 `~/.ssh/config` 示例

```
Host spark_704
    HostName 192.168.8.202
    User LChuang
    IdentityFile ~/.ssh/id_ed25519
    ServerAliveInterval 60
    ServerAliveCountMax 3
    # 同一 session 多 tunnel 复用，速度快
    ControlMaster auto
    ControlPath ~/.ssh/cm-%r@%h:%p
    ControlPersist 10m
```

加完后 `ssh spark_704` 免输 host/user。

## 3. 常用 tunnel 命令

所有 `-fN` = 后台 + 不执行远端命令，只保持端口转发。

### 路线 B-cpp (Comni 4 模式 demo, HTTP)

```bash
ssh -fN -L 8040:localhost:8040 -L 22440:localhost:22440 spark_704
# 浏览器: http://localhost:8040/
```

端口：
- `8040` gateway (HTTP, 4 模式入口)
- `22440` worker WS

### 路线 C (WebRTC_Demo + llama.cpp-omni, HTTPS 自签)

```bash
ssh -fN \
  -L 8088:localhost:8088 \
  -L 7880:localhost:7880 \
  -L 9060:localhost:9060 \
  -L 9061:localhost:9061 \
  spark_704
# 浏览器: https://localhost:8088/  (首次需接受自签证书)
```

端口：
- `8088` Vue 前端（HTTPS 自签）
- `7880` LiveKit Server
- `9060/9061` C++ inference + health

### 路线 D (MiniCPM-o-Demo-D, VAD 自动打断)

```bash
ssh -fN -L 8050:localhost:8050 -L 22450:localhost:22450 spark_704
# 浏览器: http://localhost:8050/
```

端口：
- `8050` gateway
- `22450` worker WS

## 4. 杀死所有已建 tunnel

```bash
pkill -f 'ssh.*-fN.*spark'
# 或精确到路线:
pkill -f 'ssh.*-L 8040:localhost:8040'
```

## 5. HTTPS 自签证书绕过（仅路线 C）

浏览器首次访问 `https://localhost:8088/` 会报 `NET::ERR_CERT_AUTHORITY_INVALID`，在错误页：

- Chrome/Edge: 点空白处键盘敲 `thisisunsafe`（无可视输入框）
- Safari: 高级 → 继续访问
- Firefox: Advanced → Accept the Risk and Continue

localhost tunnel 在浏览器里视为 secure context，麦克风/摄像头 / `getDisplayMedia` 都能用，无需真 TLS 证书。

## 6. 常见问题

- **端口已被占用**：先 `pkill -f 'ssh.*-fN.*spark'` 清干净
- **tunnel 建了但连不上**：先在 spark 上 `curl -sf http://localhost:<port>/health` 验证服务本身 ok，再排查 tunnel
- **断线后端口未释放**：`ControlMaster` 配置 + `ControlPersist 10m` 会自动清理；手动 `ssh -O exit spark_704`
- **macOS SSH agent 每次输密码**：`ssh-add --apple-use-keychain ~/.ssh/id_ed25519`（macOS 13+）
