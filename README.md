# dsh-relay

ds-harness-remote **server（中继）** 的单文件预构建版。上游 `apps/server`（v0.5.21）用 esbuild 打成一个 ESM 文件，只依赖 Node 内置模块，无需 npm install、无需 Docker。

- 产物：`relay-server.mjs`（约 956 KB），`node relay-server.mjs` 即可
- 已内置：`ws@8.23.0`、`zod@4.6.7`、`@dsh-remote/protocol`
- 协议：WebSocket 路径固定 `/ws/v1/connect`；REST 在 `/api/v1/*`；健康检查 `/health`

## 环境变量

| 变量 | 必填 | 说明 |
|---|---|---|
| `DSH_SERVER_ACCOUNT` | 是 | 账号（用户名） |
| `DSH_SERVER_PASSWORD` | 是 | 密码，**至少 12 位** |
| `DSH_SERVER_PUBLIC_URL` | 是 | 对外 origin，例如 `https://jndnbd.asia`（不能带路径） |
| `DSH_SERVER_PORT` | 否 | 默认 8080 |
| `DSH_SERVER_HOST` | 否 | 默认 127.0.0.1（只让本机反代进来，安全） |
| `DSH_SERVER_DATA_FILE` | 否 | 状态文件，默认 `data/store.json` |
| `DSH_SERVER_STUN_URLS` / `DSH_SERVER_TURN_URLS` | 否 | 留空 = Relay-only（不打洞，最稳） |
| `LOG_LEVEL` | 否 | `info` / `debug` |

## 反向代理要求

- `/ws/v1/connect` 必须支持 WebSocket Upgrade，idle timeout > 75 秒
- 关闭响应缓冲（Caddy: `flush_interval -1`）
- 中继服务本身**不开公网端口**，只监听 127.0.0.1，由 Caddy 转发

Caddy 片段（放在站点块最前面，早于博客/静态路由）：

```
@relay_ws path /ws/v1/*
handle @relay_ws {
    reverse_proxy 127.0.0.1:8080 {
        flush_interval -1
    }
}
@relay_api path /api/v1/*
handle @relay_api {
    reverse_proxy 127.0.0.1:8080 {
        flush_interval -1
    }
}
handle /health {
    reverse_proxy 127.0.0.1:8080
}
```

## 验证

```powershell
curl.exe -s https://jndnbd.asia/health          # {"status":"ok"}
curl.exe -s -o NUL -w "%{http_code}" https://jndnbd.asia/api/v1/auth/me   # 401
```

WebSocket 握手（PowerShell + Node）：

```powershell
node -e "const W=require('ws');const w=new W('ws://127.0.0.1:8080/ws/v1/connect');w.on('open',()=>{console.log('open');process.exit(0)});w.on('error',e=>{console.log('err',e.message);process.exit(0)})"
```

## 客户端怎么填

- 家里插件（ds-harness-remote，role=host）`serverUrl` 填 `https://jndnbd.asia`
- 手机 DSH Go：「自建服务器 · 邮箱登录」→ 服务器地址 `https://jndnbd.asia`，账号/密码同上

> 说明：同一台机器上 `/molly/*` 是另一个服务（MollyRelay，127.0.0.1:19393），与 8080 的中继互不影响。
