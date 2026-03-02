# FluxDeck 使用文档（MVP）

本文档面向本地使用者，目标是让你在几分钟内跑通：

1. 启动本地管理服务 `fluxd`
2. 用 `fluxctl` 配置 Provider 与 Gateway
3. 通过 Gateway 调用 OpenAI 兼容接口

## 1. 前置要求

- macOS（当前优先支持）
- Rust 工具链（`cargo` 可用）
- `uv`（用于脚本与 e2e）
- `bun`（用于桌面端测试）

可选检查：

```bash
cargo --version
uv --version
bun --version
```

## 2. 启动服务

在项目根目录执行：

```bash
FLUXDECK_DB_PATH="$HOME/.fluxdeck/fluxdeck.db" \
FLUXDECK_ADMIN_ADDR="127.0.0.1:7777" \
cargo run -p fluxd
```

说明：

- `FLUXDECK_DB_PATH`：SQLite 数据库路径
- `FLUXDECK_ADMIN_ADDR`：管理 API 地址（默认 `127.0.0.1:7777`）

启动后可用以下命令检查：

```bash
curl http://127.0.0.1:7777/admin/providers
```

## 3. 配置 Provider

当前 MVP 先支持标准 OpenAI Provider。

```bash
cargo run -p fluxctl -- --admin-url http://127.0.0.1:7777 provider create \
  --id provider_main \
  --name "Main Provider" \
  --kind openai \
  --base-url https://api.openai.com/v1 \
  --api-key sk-xxx \
  --models gpt-4o-mini,gpt-4.1
```

查看 Provider 列表：

```bash
cargo run -p fluxctl -- --admin-url http://127.0.0.1:7777 provider list
```

## 4. 配置并启动 Gateway

创建 Gateway：

```bash
cargo run -p fluxctl -- --admin-url http://127.0.0.1:7777 gateway create \
  --id gateway_main \
  --name "Gateway Main" \
  --listen-host 127.0.0.1 \
  --listen-port 18080 \
  --inbound-protocol openai \
  --default-provider-id provider_main \
  --default-model gpt-4o-mini
```

启动 Gateway：

```bash
cargo run -p fluxctl -- --admin-url http://127.0.0.1:7777 gateway start gateway_main
```

查看 Gateway 列表：

```bash
cargo run -p fluxctl -- --admin-url http://127.0.0.1:7777 gateway list
```

停止 Gateway：

```bash
cargo run -p fluxctl -- --admin-url http://127.0.0.1:7777 gateway stop gateway_main
```

## 5. 调用转发 API

Gateway 启动后，调用本地 OpenAI 兼容接口：

```bash
curl -X POST http://127.0.0.1:18080/v1/chat/completions \
  -H 'content-type: application/json' \
  -d '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"hello"}]}'
```

如果配置正确，会返回上游模型响应（JSON）。

## 6. 查看请求日志

```bash
cargo run -p fluxctl -- --admin-url http://127.0.0.1:7777 logs
```

说明：

- 日志来自 `request_logs` 表
- 系统会按条数自动滚动清理（当前保留最近 10,000 条）

## 7. 多网关示例

你可以绑定同一个 Provider，开多个 Gateway（不同端口）：

```bash
cargo run -p fluxctl -- --admin-url http://127.0.0.1:7777 gateway create \
  --id gateway_alt \
  --name "Gateway Alt" \
  --listen-host 127.0.0.1 \
  --listen-port 18081 \
  --inbound-protocol openai \
  --default-provider-id provider_main \
  --default-model gpt-4.1

cargo run -p fluxctl -- --admin-url http://127.0.0.1:7777 gateway start gateway_alt
```

## 8. 一键自检（推荐）

在项目根目录执行：

```bash
cargo test -q
bun run test --cwd apps/desktop
./scripts/e2e/smoke.sh
```

`smoke.sh` 输出 `smoke ok` 表示核心链路正常。

## 9. 常见问题

1. `Connection refused`  
先确认 `fluxd` 是否在运行，以及 `FLUXDECK_ADMIN_ADDR` 是否与 `fluxctl --admin-url` 一致。

2. 网关端口启动失败  
通常是端口占用，换一个 `--listen-port`。

3. 上游调用失败  
检查 Provider 的 `--base-url`、`--api-key`、`--models` 是否正确。

4. 数据库文件问题  
确认 `FLUXDECK_DB_PATH` 所在目录有写权限。

## 10. Admin API 契约

前端（Tauri 与 macOS 原生壳）统一依赖以下稳定契约：

- [docs/contracts/admin-api-v1.md](./contracts/admin-api-v1.md)

如需调整 `provider / gateway / logs` 返回字段，请先更新契约文档并补齐对应测试。
