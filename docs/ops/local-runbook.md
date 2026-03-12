# FluxDeck 本地运行手册

## 启动 fluxd

```bash
FLUXDECK_DB_PATH="$HOME/.fluxdeck/fluxdeck.db" \
FLUXDECK_ADMIN_ADDR="127.0.0.1:7777" \
cargo run -p fluxd
```

## 使用 fluxctl 创建 Provider

```bash
cargo run -p fluxctl -- --admin-url http://127.0.0.1:7777 provider create \
  --id provider_main \
  --name "Main" \
  --kind openai \
  --base-url https://api.openai.com/v1 \
  --api-key sk-xxx \
  --models gpt-4o-mini,gpt-4.1
```

Provider `base_url` 说明：

- `openai` / `openai-response` / `azure-openai` / `new-api` 一般填写带 `/v1` 的 API 前缀
- `anthropic` 兼容两种写法：
  - `https://host/api/anthropic`
  - `https://host/api/anthropic/v1`
- 如果你更新了 Provider 配置，而对应 Gateway 已在运行，需要手动 `stop -> start` 才会加载新地址

删除 Provider：

```bash
cargo run -p fluxctl -- --admin-url http://127.0.0.1:7777 provider delete provider_main
```

说明：

- 默认会要求确认
- 可通过 `-y` / `--yes` 跳过确认
- 若仍被任一 Gateway 引用，服务端会拒绝删除，并返回引用它的 Gateway ID 列表
- 这是 Provider 侧的约束，不影响 Gateway 独立删除

## 创建并启动网关

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
  --default-model gpt-4o-mini \
  --auto-start true
```

### auto_start 说明

- `--auto-start true`：fluxd 启动后自动拉起该 Gateway
- `--auto-start false`（默认）：需要手动执行 `gateway start`
- 自动启动条件：`enabled=true && auto_start=true`
- 单个 Gateway 自动启动失败不会阻塞 fluxd 主进程

如果你使用原生桌面端配置 Gateway：

- `New Gateway` 与 `Edit Gateway` 已统一为工作台式编辑界面
- `Default Provider`、`Inbound Protocol`、`Upstream Protocol` 优先通过受控选择填写
- `Routing JSON` 会在保存前做 JSON object 校验
- 若 Gateway 当前处于运行中，且保存内容相对旧配置确实有变化，fluxd 会自动执行 `stop -> start`
- 原生桌面端与 `fluxctl gateway update` 都会展示自动重启结果提示

更新网关配置：

```bash
cargo run -p fluxctl -- --admin-url http://127.0.0.1:7777 gateway update gateway_main \
  --name "Gateway Main Updated" \
  --listen-host 127.0.0.1 \
  --listen-port 19090 \
  --inbound-protocol openai \
  --upstream-protocol provider_default \
  --protocol-config-json '{"compatibility_mode":"strict"}' \
  --default-provider-id provider_main \
  --default-model gpt-4.1-mini \
  --enabled true \
  --auto-start false
```

注意：

- 若 Gateway 当前未运行，`gateway update` 只保存配置，不会自动启动
- 若 Gateway 当前正在运行且配置发生变化，fluxd 会自动重启该实例以应用新配置
- `fluxctl` 会先输出完整 JSON，再额外输出一行 `Notice: ...` 提示

手动启动/停止网关：

```bash
cargo run -p fluxctl -- --admin-url http://127.0.0.1:7777 gateway start gateway_main
cargo run -p fluxctl -- --admin-url http://127.0.0.1:7777 gateway stop gateway_main
```

删除 Gateway：

```bash
cargo run -p fluxctl -- --admin-url http://127.0.0.1:7777 gateway delete gateway_main
```

说明：

- 默认会要求确认
- 可通过 `-y` / `--yes` 跳过确认
- 若 Gateway 当前正在运行，`fluxd` 会先自动执行 `stop -> delete`
- Gateway 删除不要求先删除关联 Provider；只要停机成功即可删除
- 删除成功后，`fluxctl` 会输出完整 JSON；若服务端提供 `user_notice`，还会额外输出 `Notice: ...`

## 调用网关

```bash
curl -X POST http://127.0.0.1:18080/v1/chat/completions \
  -H 'content-type: application/json' \
  -d '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"hello"}]}'
```

## Anthropic 原生上游网关示例

先创建 Anthropic Provider（以智谱 Claude 兼容端点为例）：

```bash
cargo run -p fluxctl -- --admin-url http://127.0.0.1:7777 provider create \
  --id provider_anthropic \
  --name "Anthropic Compatible" \
  --kind anthropic \
  --base-url https://open.bigmodel.cn/api/anthropic \
  --api-key sk-xxx \
  --models GLM-5
```

`--base-url` 也可以填写 `https://open.bigmodel.cn/api/anthropic/v1`，FluxDeck 会在运行时统一归一化。

```bash
cargo run -p fluxctl -- --admin-url http://127.0.0.1:7777 gateway create \
  --id gateway_anthropic_native \
  --name "Gateway Anthropic Native" \
  --listen-host 127.0.0.1 \
  --listen-port 18081 \
  --inbound-protocol anthropic \
  --upstream-protocol anthropic \
  --default-provider-id provider_main \
  --default-model claude-sonnet-4-5
```

## 查看转发日志字段

```bash
curl 'http://127.0.0.1:7777/admin/logs?limit=5'
```

重点检查这些字段：

- `inbound_protocol`：入站协议，例如 `openai` / `anthropic`
- `upstream_protocol`：上游协议，例如 `openai` / `anthropic`
- `model_requested`：客户端请求模型
- `model_effective`：实际发往上游的模型
- `input_tokens/output_tokens/total_tokens`：usage 统计
- `stream` 与 `first_byte_ms`：流式请求与首包耗时
