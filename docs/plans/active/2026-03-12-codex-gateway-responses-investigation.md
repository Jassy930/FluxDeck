# Gateway Codex Responses 转发问题调查

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 调查 `gateway_codex` 无法正常转发 Codex 请求、访问 `http://127.0.0.1:18081/responses` 返回 `404 Not Found` 的根因，并明确修复入口。

**Architecture:** 先沿着 `Provider kind -> Gateway runtime -> Inbound route -> Upstream client` 链路做静态核对，确认问题发生在入站路由缺失还是上游适配错误。当前证据显示，问题发生在 Gateway 的 OpenAI 入站路由层，尚未实现 Responses API。

**Tech Stack:** Rust, Axum, reqwest, SQLite, FluxDeck gateway/runtime/admin stack

---

## 已确认现象

- 用户侧报错：`unexpected status 404 Not Found: Unknown error, url: http://127.0.0.1:18081/responses`
- Provider 层允许 `kind = openai-response`
- Gateway 层当前没有完整支持 OpenAI Responses API

## 证据链

### 1. Provider 类型只做了“可存储/可选择”，没有驱动运行时协议分发

- 文件：`crates/fluxd/src/domain/provider.rs`
- 现状：
  - `SUPPORTED_PROVIDER_KINDS` 包含 `openai-response`
  - 这是 Admin API 和配置层的白名单，不代表运行时一定支持对应协议

### 2. Gateway 启动时只按 `inbound_protocol` 选择 Router

- 文件：`crates/fluxd/src/runtime/gateway_manager.rs`
- 现状：
  - `openai` -> `build_openai_router(...)`
  - `anthropic` -> `build_anthropic_router(...)`
- 影响：
  - 即使 Provider 是 `openai-response`，只要 Gateway 的 `inbound_protocol` 还是 `openai`，最终也只会挂载 OpenAI Router 当前实现的那些路径

### 3. OpenAI Router 只注册了 `/v1/chat/completions`

- 文件：`crates/fluxd/src/http/openai_routes.rs`
- 现状：
  - 仅存在：
    - `route("/v1/chat/completions", post(forward_chat_completions))`
  - 不存在：
    - `/v1/responses`
    - `/responses`
- 影响：
  - 任何面向 Codex / Responses API 的请求打到 Gateway 时，都会在 Axum 路由层直接返回 `404`
  - 这和用户当前看到的 `http://127.0.0.1:18081/responses` 报错一致

### 4. 上游 OpenAI 客户端同样只实现了 `chat/completions`

- 文件：`crates/fluxd/src/upstream/openai_client.rs`
- 现状：
  - 只实现：
    - `chat_completions(...)`
    - `chat_completions_stream(...)`
    - `chat_completions_from_ir(...)`
  - URL 固定拼接为 `{base_url}/chat/completions`
- 影响：
  - 即便补齐了 Gateway `/responses` 入站路由，当前也没有对应的上游 `responses` 转发实现

### 5. 文档把 `openai-response` 当作 Provider 种类公开了，但没有声明 Gateway 仍缺 Responses 支持

- 文件：
  - `docs/contracts/admin-api-v1.md`
  - `docs/USAGE.md`
  - `docs/ops/local-runbook.md`
- 现状：
  - 文档声明 `openai-response` 是合法 Provider `kind`
  - `base_url` 也被描述为 OpenAI 风格 `/v1` 前缀
  - 但没有明确写出：Gateway 当前仅支持 `/v1/chat/completions`，未支持 Responses API

## 根因结论

`gateway_codex` 失败不是配置值无法保存，而是运行时能力不完整：

- Provider 层“支持 `openai-response`”只停留在枚举和配置校验
- Gateway OpenAI 入站路由没有实现 `/responses`
- 上游 OpenAI 客户端也没有实现 `responses` 端点调用

因此当前 `gateway_codex` 对 Codex/Responses 风格请求必然返回 `404`，这是产品能力缺口，不是单纯的地址填错。

## 影响范围

- 所有发往 Gateway 的 OpenAI Responses API 请求
- 典型路径：
  - `/responses`
  - `/v1/responses`
- 典型客户端：
  - Codex CLI / SDK（若以 Responses API 为默认入口）
  - 任何依赖新 OpenAI Responses API 的上游客户端

## 修复方向（已确认）

采用“协议网关优先 + 同协议透传兜底”：

- 保留现有专门实现的协议 handler
- 补齐 Gateway 协议类型集合，使其与 Provider 完整类型对齐
- 当 `inbound_protocol == upstream_protocol` 且未命中专门 handler 时，自动执行 passthrough
- 对 OpenAI 系优先兼容：
  - `/responses`
  - `/v1/responses`

这样可以解决当前 `gateway_codex` 的直接不可用问题，同时不打断现有日志和协议增强主线。

## 待讨论 Issue

- 是否在后续版本演进到“通用代理优先 + 协议增强附加”的方案 C
- 当前结论：不作为本轮实现方向，但已正式记录到设计文档
- 参考文档：
  - `docs/plans/completed/2026-03-12-gateway-protocol-fallback-design.md`
