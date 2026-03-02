# FluxDeck MVP 设计文档

## 1. 项目目标

在 macOS 本地交付一个最小可用闭环（MVP）的 LLM API 转发与管理工具，形态为：

- Tauri 桌面应用（管理界面）
- 独立本地网关服务 `fluxd`（负责 API 转发与管理 API）
- CLI 工具 `fluxctl`（通过管理 API 管理网关与 Provider）

第一版范围聚焦标准 OpenAI Provider，后续逐步扩展更多 Provider 与协议。

## 2. MVP 范围

### 2.1 必做能力

- 创建/编辑 OpenAI Provider：`name`、`base_url`、`api_key`、`models`
- 创建/启动/停止网关实例：支持多网关（不同端口）
- 网关入站接口：OpenAI 兼容，第一版先支持 `POST /v1/chat/completions`
- 请求转发：按网关绑定的默认 Provider 转发到上游
- 桌面 UI：查看网关运行状态与最近请求日志
- CLI：Provider/Gateway 的增删改查与启停

### 2.2 暂不做能力

- WebUI
- Anthropic 入站协议
- 高级路由（按模型/标签/权重分流）
- 密钥安全存储（第一版按需求明文）

## 3. 系统架构与数据流

### 3.1 进程与职责

- `FluxDeck Desktop (Tauri)`：UI 与本地控制入口
- `fluxd`：独立进程，负责数据面转发与控制面管理 API
- `fluxctl`：CLI 管理工具，调用 `fluxd` 管理 API

### 3.2 控制面（Control Plane）

- Desktop/CLI 调用 `fluxd` 的管理 API（本机回环地址）
- 管理对象：Provider、Gateway、网关启停、日志读取

### 3.3 数据面（Data Plane）

1. 客户端请求进入某个 Gateway 监听端口
2. Gateway 读取绑定默认 Provider 配置
3. `fluxd` 组装并转发上游 OpenAI 请求
4. 返回响应给客户端，并记录结构化日志

### 3.4 多网关

- 单个 `fluxd` 内可维护多个网关实例
- 每个网关具有独立生命周期（start/stop/reload）
- 每个网关拥有独立监听地址与默认 Provider 绑定

## 4. 数据模型与持久化

### 4.1 存储选型

- 第一版使用 SQLite 单文件数据库
- 路径：`~/.fluxdeck/fluxdeck.db`

### 4.2 核心数据表

- `providers`
  - `id`
  - `name`
  - `kind`（第一版固定 `openai`）
  - `base_url`
  - `api_key`（按需求第一版明文）
  - `enabled`
  - `created_at` / `updated_at`
- `provider_models`
  - `id`
  - `provider_id`
  - `model_name`
- `gateways`
  - `id`
  - `name`
  - `listen_host`（默认 `127.0.0.1`）
  - `listen_port`
  - `inbound_protocol`（第一版固定 `openai`）
  - `default_provider_id`
  - `default_model`（可选）
  - `enabled`
  - `created_at` / `updated_at`
- `request_logs`
  - `request_id`
  - `gateway_id`
  - `provider_id`
  - `model`
  - `status_code`
  - `latency_ms`
  - `error`
  - `created_at`

### 4.3 运行态说明

- 网关运行状态以内存态为准，不强依赖落库
- 数据库通过顺序 migration 管理（从 `001_init.sql` 起）

## 5. 错误处理与可观测性

### 5.1 错误分层

- 入站校验错误：返回 OpenAI 风格 `4xx`
- 上游 Provider 错误：透传核心状态码与错误摘要，并附本地 `request_id`
- 系统错误：统一 `500`，不暴露敏感信息

### 5.2 超时与重试

- 上游请求设置默认超时（建议 60s）
- 第一版不做自动重试，避免非幂等风险

### 5.3 日志与追踪

- 每请求生成唯一 `request_id`
- 记录结构化日志：网关、Provider、模型、状态码、耗时、错误摘要
- UI 展示最近 N 条日志（例如 200）
- CLI 支持按网关过滤日志

### 5.4 日志保留策略

- `request_logs` 采用滚动清理
- MVP 建议保留最近 10,000 条

## 6. 测试策略

### 6.1 测试分层

- 单元测试：配置校验、请求映射逻辑
- 集成测试：`fluxd + mock upstream` 验证完整转发链路
- 端到端测试：`fluxctl` 管理资源并通过 `curl` 调通网关

### 6.2 关键失败场景

- 无效 API Key
- 上游超时
- 请求模型不在 Provider 模型列表
- 网关端口冲突导致启动失败

## 7. MVP 验收标准

- 可创建至少 1 个 OpenAI Provider
- 可创建并启动至少 2 个网关（不同端口）
- 客户端可成功调用 `POST /v1/chat/completions`
- 桌面 UI 可查看网关状态与最近请求日志
- CLI 可完成 Provider/Gateway 的增删改查与启停
- 单元测试 + 集成测试 + 最小 e2e 测试通过

## 8. 后续演进（非 MVP）

- 增加 Anthropic 入站协议
- 扩展多 Provider 适配层
- 引入 API Key 安全存储（macOS Keychain）
- 支持 WebUI
- 支持高级路由策略（模型/标签/权重/故障转移）
