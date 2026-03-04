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
- `base_url: string`
- `api_key: string`
- `models: string[]`
- `enabled: boolean`

### `POST /admin/providers`

请求体与响应体字段同上；创建成功返回 `201`.

## 2) Gateway

### `GET /admin/gateways`

返回数组，元素字段（稳定字段）：

- `id: string`
- `name: string`
- `listen_host: string`
- `listen_port: number`
- `inbound_protocol: string`
- `upstream_protocol: string`
- `protocol_config_json: object`
- `default_provider_id: string`
- `default_model: string | null`
- `enabled: boolean`

### `POST /admin/gateways`

请求体与响应体字段同上；创建成功返回 `201`.

### `POST /admin/gateways/{id}/start`
### `POST /admin/gateways/{id}/stop`

返回对象：

- `ok: boolean`

## 3) Logs

### `GET /admin/logs`

返回数组（最多 200 条），元素字段（稳定字段）：

- `request_id: string`
- `gateway_id: string`
- `provider_id: string`
- `model: string | null`
- `status_code: number`
- `latency_ms: number`
- `error: string | null`
- `created_at: string`

## 版本策略

- 本文档定义的字段视为前端契约；新增字段允许，删除/重命名字段需升级版本。
- 契约回归由 `crates/fluxd/tests/admin_api_test.rs::admin_api_response_shape_is_stable` 保障。
