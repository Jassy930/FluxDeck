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

## 2.1 启动桌面前端（开发模式）

在另一个终端进入前端目录：

```bash
cd apps/desktop
bun install
bun run dev
```

说明：

- 开发服务器默认地址：`http://127.0.0.1:5173`
- 已配置 Vite 代理：`/admin -> http://127.0.0.1:7777`
- 因此前端会通过同源路径 `/admin/*` 访问 Admin API，避免浏览器跨域拦截

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
  --upstream-protocol provider_default \
  --protocol-config-json '{"compatibility_mode":"compatible"}' \
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

### 5.1 Anthropics 入站与兼容模式示例

创建 Anthropics 入站网关（转发到 OpenAI 兼容上游）：

```bash
cargo run -p fluxctl -- --admin-url http://127.0.0.1:7777 gateway create \
  --id gateway_anthropic \
  --name "Gateway Anthropic" \
  --listen-host 127.0.0.1 \
  --listen-port 18081 \
  --inbound-protocol anthropic \
  --upstream-protocol openai \
  --protocol-config-json '{"compatibility_mode":"compatible"}' \
  --default-provider-id provider_main \
  --default-model claude-3-7-sonnet
```

兼容模式说明：

- `strict`：遇到不兼容能力直接返回 `capability_error`
- `compatible`：优先保证可用（例如 `count_tokens` 降级为本地估算）
- `permissive`：允许扩展字段透传到上游

模型映射（用于将 Claude Code 的多模型请求统一到目标模型）：

```bash
cargo run -p fluxctl -- --admin-url http://127.0.0.1:7777 gateway create \
  --id gateway_anthropic_map \
  --name "Gateway Anthropic Map" \
  --listen-host 127.0.0.1 \
  --listen-port 18082 \
  --inbound-protocol anthropic \
  --upstream-protocol openai \
  --default-provider-id provider_main \
  --default-model qwen3-coder-plus \
  --protocol-config-json '{
    "compatibility_mode":"compatible",
    "model_mapping":{
      "rules":[
        {"from":"claude-*","to":"qwen3-coder-plus"},
        {"from":"sonnet","to":"qwen3-coder-plus"}
      ],
      "fallback_model":"qwen3-coder-plus"
    }
  }'
```

语义说明：

- 规则按顺序匹配，命中后将 `model` 重写为 `to`
- 未命中规则且配置了 `fallback_model`：使用 `fallback_model`
- 未命中规则且未配置 `fallback_model`：保留原始 `model`

请求调试日志（定位“回复过短/提前结束”时建议开启）：

```bash
cargo run -p fluxctl -- --admin-url http://127.0.0.1:7777 gateway create \
  --id gateway_anthropic_debug \
  --name "Gateway Anthropic Debug" \
  --listen-host 127.0.0.1 \
  --listen-port 18083 \
  --inbound-protocol anthropic \
  --upstream-protocol openai \
  --default-provider-id provider_main \
  --default-model qwen3-coder-plus \
  --protocol-config-json '{
    "compatibility_mode":"compatible",
    "debug":{
      "log_request_payload":true,
      "max_payload_chars":8000
    }
  }'
```

也可用环境变量全局强制开启（重启 `fluxd` 后生效）：

```bash
FLUXDECK_DEBUG_ANTHROPIC_REQUEST_PAYLOAD=1 cargo run -p fluxd
```

开启后，`fluxd` 控制台会输出类似日志：

```text
[fluxd][anthropic-debug] gateway_id=... request_id=... route=/v1/messages model=... stream=... max_tokens=... messages=... payload=...
```

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
cd apps/desktop && bun run test
./scripts/e2e/smoke.sh
```

`smoke.sh` 输出 `smoke ok` 表示核心链路正常。

Anthropic 兼容模式专项验证：

```bash
uv run python scripts/e2e/anthropic_compat.py \
  --admin-url http://127.0.0.1:7777 \
  --upstream-base-url http://127.0.0.1:18000/v1
```

更多说明见：

- [docs/testing/anthropic-compat-e2e.md](./testing/anthropic-compat-e2e.md)

并行交付验收清单见：

- [docs/testing/frontend-parallel-checklist.md](./testing/frontend-parallel-checklist.md)

## 9. 常见问题

1. `Connection refused`  
先确认 `fluxd` 是否在运行，以及 `FLUXDECK_ADMIN_ADDR` 是否与 `fluxctl --admin-url` 一致。

2. 网关端口启动失败  
通常是端口占用，换一个 `--listen-port`。

3. 上游调用失败  
检查 Provider 的 `--base-url`、`--api-key`、`--models` 是否正确。

4. 数据库文件问题  
确认 `FLUXDECK_DB_PATH` 所在目录有写权限。

5. `cargo test` 出现 `E0463 can't find crate`  
通常是工具链切换后遗留了不兼容构建产物。执行：

```bash
cargo clean
```

再重跑总验收命令。

## 10. Admin API 契约

前端（Tauri 与 macOS 原生壳）统一依赖以下稳定契约：

- [docs/contracts/admin-api-v1.md](./contracts/admin-api-v1.md)

如需调整 `provider / gateway / logs` 返回字段，请先更新契约文档并补齐对应测试。
