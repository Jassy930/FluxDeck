# FluxDeck Admin API v1 契约

本文档锁定 `fluxd` Admin API 的 v1 返回结构，供 Tauri 主线与 macOS 原生壳共同消费。

## 通用约定

- Base URL：`http://<admin-host>`
- Content-Type：`application/json`
- 时间字段：UTC 字符串（SQLite `CURRENT_TIMESTAMP`）

## 1) Provider

### `GET /admin/providers`

返回数组，元素字段（稳定字段）：

- `id: string`
- `name: string`
- `kind: string`
  - 允许值：`openai | openai-response | gemini | anthropic | azure-openai | new-api | ollama`
- `base_url: string`
- `api_key: string`
- `models: string[]`
- `enabled: boolean`

`base_url` 语义补充：

- `kind=openai | openai-response | azure-openai | new-api` 时，`base_url` 应包含对应 API 版本前缀，例如 `https://api.openai.com/v1`
- `kind=anthropic` 时，FluxDeck 同时兼容以下两种写法：
  - `https://host/api/anthropic`
  - `https://host/api/anthropic/v1`
  - 运行时会自动规范化到 `/v1/messages` 与 `/v1/messages/count_tokens`

### `POST /admin/providers`

请求体与响应体字段同上；创建成功返回 `201`.

错误响应：

- 非法 `kind` 或其他校验失败：`400`，返回 `{ "error": string }`

### `PUT /admin/providers/{id}`

更新指定 Provider（`id` 由路径指定，不可变更）。

请求体字段：

- `name: string`
- `kind: string`
  - 允许值：`openai | openai-response | gemini | anthropic | azure-openai | new-api | ollama`
- `base_url: string`
- `api_key: string`
- `models: string[]`
- `enabled: boolean`

`base_url` 语义与 `POST /admin/providers` 保持一致。

响应：

- 成功：`200`，返回更新后的 Provider（字段同 `GET /admin/providers`）
- 非法 `kind` 或其他校验失败：`400`，返回 `{ "error": string }`
- 不存在：`404`

### `DELETE /admin/providers/{id}`

删除指定 Provider。

响应：

- 成功：`200`，返回：
  - `ok: boolean`
  - `id: string`
- 不存在：`404`
- 仍被 Gateway 引用：`409`，返回：
  - `error: "provider is referenced by gateways"`
  - `id: string`
  - `referenced_by_gateway_ids: string[]`

说明：

- 当任意 Gateway 的 `default_provider_id` 指向该 Provider 时，删除会被拒绝
- 删除成功时，会一并删除该 Provider 关联的 `provider_models`
- 这是单向约束：只有 Provider 删除会受 Gateway 引用关系限制；Gateway 删除本身不依赖 Provider 删除
- 历史 `request_logs` 不会阻止 Provider 删除；日志中的 `provider_id` 作为历史快照保留

## 2) Gateway

### `GET /admin/gateways`

返回数组，元素字段（稳定字段）：

- `id: string`
- `name: string`
- `listen_host: string`
- `listen_port: number`
- `inbound_protocol: string`
- 允许值：`openai | openai-response | gemini | anthropic | azure-openai | new-api | ollama`
- `upstream_protocol: string`
- 允许值：`provider_default | openai | openai-response | gemini | anthropic | azure-openai | new-api | ollama`
- `protocol_config_json: object`
- `default_provider_id: string`
- `default_model: string | null`
- `enabled: boolean`
- `auto_start: boolean`
- `runtime_status: "running" | "stopped" | string`
- `last_error: string | null`

### `POST /admin/gateways`

请求体与响应体字段同上；创建成功返回 `201`.

协议语义补充：

- `inbound_protocol` 与 `upstream_protocol` 的协议值集合与 Provider `kind` 对齐
- `upstream_protocol=provider_default` 表示运行时跟随默认 Provider 的 `kind`
- 当 `inbound_protocol == upstream_protocol` 且请求路径没有命中专门 handler 时，Gateway 会启用同协议 passthrough fallback
  - 默认透传原始方法、路径、查询串、请求头与请求体
  - 当前 OpenAI 系已兼容 `/responses` 与 `/v1/responses`

### `PUT /admin/gateways/{id}`

更新指定 Gateway（`id` 由路径指定，不可变更）。

请求体字段：

- `name: string`
- `listen_host: string`
- `listen_port: number`
- `inbound_protocol: string`
- `upstream_protocol: string`
- `protocol_config_json: object`
- `default_provider_id: string`
- `default_model: string | null`
- `enabled: boolean`
- `auto_start: boolean`

响应：

- 成功：`200`，返回对象：
  - `gateway: Gateway`
  - `runtime_status: "running" | "stopped" | string`
  - `last_error: string | null`
  - `restart_performed: boolean`
  - `config_changed: boolean`
  - `user_notice: string | null`
- 不存在：`404`

### `DELETE /admin/gateways/{id}`

删除指定 Gateway。

响应：

- 成功：`200`，返回：
  - `ok: boolean`
  - `id: string`
  - `runtime_status_before_delete: "running" | "stopped" | string`
  - `stop_performed: boolean`
  - `user_notice: string | null`
- 不存在：`404`
- 停机失败或其他删除失败：`400`

说明：

- `auto_start=true` 表示 `fluxd` 进程启动时会自动尝试拉起该 Gateway
- 自动拉起只对 `enabled=true && auto_start=true` 的 Gateway 生效
- 若某个 Gateway 自动拉起失败，不会阻塞 `fluxd` 启动；错误会写入该 Gateway 的 `last_error`
- `PUT /admin/gateways/{id}` 会先持久化配置，再根据运行态决定是否自动重启
- 只有当“更新前实例处于 `running`”且“新旧配置确实发生变化”时，才会自动执行 `stop -> start`
- 若实例未运行，则只保存配置，不会自动启动
- 若自动重启失败，配置仍然会保存成功，错误会通过 `last_error` 与 `user_notice` 返回
- `DELETE /admin/gateways/{id}` 在 Gateway 运行中时会先执行 `stop -> delete`
- 若删除前自动停机失败，删除会中止，Gateway 配置保持不变
- Gateway 可独立删除；只要删除前停机成功（或本来就是停止态），就不会因为其关联 Provider 仍存在而被阻止
- 历史 `request_logs` 不会阻止 Gateway 删除；日志中的 `gateway_id` 作为历史快照保留
- 当 `inbound_protocol == upstream_protocol` 且路径未命中专门 handler 时，Gateway 会自动尝试同协议 passthrough fallback，而不是直接返回框架层 `404`

`protocol_config_json` 约定（当前已使用字段）：

- `compatibility_mode?: "strict" | "compatible" | "permissive"`
  - 默认：`"compatible"`
  - `strict`：禁用降级与扩展能力
  - `compatible`：优先兼容（必要时降级）
  - `permissive`：允许扩展字段透传
- `model_mapping?: object`
  - `enabled?: boolean`（可选，默认启用；显式 `false` 时关闭模型映射）
  - `rules?: Array<{ from: string, to: string }>`
    - `from` 支持 `*` 通配（例如 `claude-*`）
    - 命中首条规则后，入站请求 `model` 会重写为对应 `to`
  - `fallback_model?: string`
    - 当未命中任何 `rules` 时：
      - 若配置了 `fallback_model`，使用 `fallback_model`
      - 若未配置 `fallback_model`，保留原始 `model`
- `debug?: object`
  - `log_request_payload?: boolean`（默认 `false`）
  - `max_payload_chars?: number`（默认 `4000`，范围会被约束到 `64..=200000`）
  - 生效后会在 `fluxd` 进程标准输出打印 Anthropic 入站请求摘要（包含 `model/max_tokens/messages` 与截断后的 payload）

此外支持环境变量强制开启（优先级高于 `debug.log_request_payload`）：

- `FLUXDECK_DEBUG_ANTHROPIC_REQUEST_PAYLOAD=1|true|yes|on`

### `POST /admin/gateways/{id}/start`
### `POST /admin/gateways/{id}/stop`

返回对象：

- `ok: boolean`

## 3) Logs

### `GET /admin/logs`

查询参数：

- `limit?: number`：单次返回条数，默认 `50`，最大 `100`
- `cursor_created_at?: string`：分页游标时间戳
- `cursor_request_id?: string`：同时间戳下的稳定次级游标
- `gateway_id?: string`：按 gateway 过滤
- `provider_id?: string`：按 provider 过滤
- `status_code?: number`：按精确状态码过滤
- `errors_only?: boolean`：仅返回 `status_code >= 400` 或 `error != null` 的请求

返回对象：

- `items: LogItem[]`
- `next_cursor: { created_at: string, request_id: string } | null`
- `has_more: boolean`

其中 `LogItem` 字段（稳定字段）：

- `request_id: string`
- `gateway_id: string`
- `provider_id: string`
- `model: string | null`
- `inbound_protocol: string | null`
- `upstream_protocol: string | null`
- `model_requested: string | null`
- `model_effective: string | null`
- `status_code: number`
- `latency_ms: number`
- `stream: boolean`
- `first_byte_ms: number | null`
- `input_tokens: number | null`
- `output_tokens: number | null`
- `cached_tokens: number | null`
- `total_tokens: number | null`
- `usage_json: string | null`
- `error_stage: string | null`
- `error_type: string | null`
- `error: string | null`
- `created_at: string`

排序与语义：

- 服务端按 `created_at DESC, request_id DESC` 排序
- `cursor_created_at + cursor_request_id` 共同保证翻页稳定
- Native 监控页消费“最近样本窗口”
- Logs 工作台消费“可继续分页的单列可展开紧凑日志行”

说明：

- `error` 字段在兼容模式相关路径下可能附带维度标签，格式示例：
  - `dimensions={"compatibility_mode":"compatible","event":"degraded_to_estimate"}`
- `inbound_protocol / upstream_protocol` 用于区分真实转发链路，例如 `anthropic -> openai`、`anthropic -> anthropic`
- `model_requested / model_effective` 用于区分入站请求模型与最终发往上游的模型（例如发生了模型映射）
- `cached_tokens` 是稳定聚合字段，用于表达缓存命中的 token；原始 provider usage 明细仍保留在 `usage_json`
- `usage_json` 当前以字符串形式返回原始 usage JSON，便于前端先稳定消费；后续如改为对象需升级契约版本

## 4) Stats

### `GET /admin/stats/overview`

查询参数：

- `period?: string`
  - 支持如 `1h`、`6h`、`24h`、`7d`
  - 默认 `1h`

返回对象：

- `total_requests: number`
- `successful_requests: number`
- `error_requests: number`
- `success_rate: number`
- `requests_per_minute: number`
- `total_tokens: number`
- `cached_tokens: number`
- `by_gateway: Array<{ gateway_id: string, request_count: number, success_count: number, error_count: number, total_tokens: number, cached_tokens: number, avg_latency: number }>`
- `by_provider: Array<{ provider_id: string, request_count: number, success_count: number, error_count: number, total_tokens: number, cached_tokens: number, avg_latency: number }>`
- `by_model: Array<{ model: string, request_count: number, success_count: number, error_count: number, total_tokens: number, cached_tokens: number, avg_latency: number }>`

语义：

- 所有统计都从 `request_logs` 聚合得出
- 时间窗口基于服务端当前 UTC 时间回看 `period`
- `avg_latency` 当前以整数毫秒返回
- `cached_tokens` 直接聚合自 `request_logs.cached_tokens`
- 当源日志的 `cached_tokens` 为空时，按 `0` 参与聚合

### `GET /admin/stats/trend`

查询参数：

- `period?: string`
  - 支持如 `1h`、`6h`、`24h`、`7d`
  - 默认 `1h`
- `interval?: string`
  - 支持如 `5m`、`15m`、`1h`
  - 默认 `5m`

返回对象：

- `period: string`
- `interval: string`
- `data: Array<{ timestamp: string, request_count: number, avg_latency: number, error_count: number, input_tokens: number, output_tokens: number, cached_tokens: number }>`

语义：

- `timestamp` 为服务端聚合后的 UTC bucket 时间
- `avg_latency` 当前以整数毫秒返回
- `input_tokens / output_tokens / cached_tokens` 在源日志缺失时聚合为 `0`

## 版本策略

- 本文档定义的字段视为前端契约；新增字段允许，删除/重命名字段需升级版本。
- 契约回归由 `crates/fluxd/tests/admin_api_test.rs::admin_api_response_shape_is_stable` 保障。
