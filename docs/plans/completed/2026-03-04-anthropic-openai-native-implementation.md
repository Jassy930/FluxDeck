# FluxDeck Native Anthropic-to-OpenAI Forwarding Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在 `fluxd` 内原生实现 Anthropics 协议（Messages API）入站转 OpenAI 兼容上游转发，支持高宽容度配置、流式与工具调用，并为后续多对多协议转换打基础。

**Architecture:** 采用 `Protocol IR + Adapter Registry` 分层：入站协议先解码到 IR，再编码为出站协议请求；响应反向同理。运行时由 `gateway_manager` 按 `inbound_protocol + upstream_protocol` 选择路由与适配器。能力差异通过 capability flags 与降级策略处理，避免协议耦合写死在路由层。

**Tech Stack:** Rust (`tokio`, `axum`, `serde`, `serde_json`, `sqlx`, `reqwest`), SQLite migrations, CLI (`clap`), Desktop UI (`React + TypeScript` via `bun`), E2E Python helpers via `uv run`.

---

### Task 1: 扩展网关数据模型与迁移（协议图配置）

**Files:**
- Create: `crates/fluxd/migrations/002_gateway_protocol_config.sql`
- Modify: `crates/fluxd/src/domain/gateway.rs`
- Modify: `crates/fluxd/src/repo/gateway_repo.rs`
- Modify: `crates/fluxd/tests/storage_migration_test.rs`
- Modify: `crates/fluxd/tests/admin_api_test.rs`

**Step 1: 写失败测试（新列存在且默认值正确）**

```rust
#[tokio::test]
async fn migration_adds_gateway_protocol_columns() {
    let pool = sqlx::SqlitePool::connect("sqlite::memory:").await.unwrap();
    run_migrations(&pool).await.unwrap();

    let row = sqlx::query("PRAGMA table_info(gateways)")
        .fetch_all(&pool)
        .await
        .unwrap();

    let names: Vec<String> = row.into_iter().map(|r| r.get("name")).collect();
    assert!(names.contains(&"upstream_protocol".to_string()));
    assert!(names.contains(&"protocol_config_json".to_string()));
}
```

**Step 2: 运行测试并确认失败**

Run: `cargo test -p fluxd storage_migration_test -q`  
Expected: FAIL（缺少新增列）

**Step 3: 写最小实现（迁移 + Repo 读写 + Domain 字段）**

```sql
ALTER TABLE gateways ADD COLUMN upstream_protocol TEXT NOT NULL DEFAULT 'provider_default';
ALTER TABLE gateways ADD COLUMN protocol_config_json TEXT NOT NULL DEFAULT '{}';
```

```rust
pub struct Gateway {
    pub inbound_protocol: String,
    pub upstream_protocol: String,
    pub protocol_config_json: serde_json::Value,
}
```

**Step 4: 运行测试并确认通过**

Run: `cargo test -p fluxd storage_migration_test -q`  
Expected: PASS

**Step 5: 提交**

```bash
git add crates/fluxd/migrations/002_gateway_protocol_config.sql crates/fluxd/src/domain/gateway.rs crates/fluxd/src/repo/gateway_repo.rs crates/fluxd/tests/storage_migration_test.rs crates/fluxd/tests/admin_api_test.rs
git commit -m "feat(fluxd): add gateway protocol graph config columns"
```

### Task 2: 建立 Protocol IR 与 Adapter Registry 骨架

**Files:**
- Create: `crates/fluxd/src/protocol/mod.rs`
- Create: `crates/fluxd/src/protocol/ir.rs`
- Create: `crates/fluxd/src/protocol/registry.rs`
- Create: `crates/fluxd/src/protocol/error.rs`
- Modify: `crates/fluxd/src/lib.rs`
- Create: `crates/fluxd/tests/protocol_registry_test.rs`

**Step 1: 写失败测试（可按协议名拿到 adapter）**

```rust
#[test]
fn registry_resolves_anthropic_to_openai_path() {
    let registry = ProtocolRegistry::default();
    let path = registry.resolve("anthropic", "openai");
    assert!(path.is_ok());
}
```

**Step 2: 运行测试并确认失败**

Run: `cargo test -p fluxd protocol_registry_test -q`  
Expected: FAIL（模块/类型不存在）

**Step 3: 写最小实现（IR + Registry + FluxError）**

```rust
pub struct ProtocolRegistry {
    routes: std::collections::HashMap<(String, String), AdapterPath>,
}

impl ProtocolRegistry {
    pub fn resolve(&self, inbound: &str, outbound: &str) -> Result<&AdapterPath, FluxError> {
        self.routes
            .get(&(inbound.to_string(), outbound.to_string()))
            .ok_or_else(|| FluxError::capability("adapter_not_found"))
    }
}
```

**Step 4: 运行测试并确认通过**

Run: `cargo test -p fluxd protocol_registry_test -q`  
Expected: PASS

**Step 5: 提交**

```bash
git add crates/fluxd/src/protocol crates/fluxd/src/lib.rs crates/fluxd/tests/protocol_registry_test.rs
git commit -m "feat(fluxd): scaffold protocol ir and adapter registry"
```

### Task 3: 实现 Anthropics 请求解码器（非流式）

**Files:**
- Create: `crates/fluxd/src/protocol/adapters/mod.rs`
- Create: `crates/fluxd/src/protocol/adapters/anthropic/mod.rs`
- Create: `crates/fluxd/src/protocol/adapters/anthropic/request_decoder.rs`
- Create: `crates/fluxd/tests/anthropic_decoder_test.rs`

**Step 1: 写失败测试（messages + system + tool_use 解析到 IR）**

```rust
#[test]
fn decodes_messages_payload_into_ir() {
    let payload = serde_json::json!({
        "model": "claude-3-7-sonnet",
        "system": "you are helpful",
        "messages": [{"role": "user", "content": "hello"}],
        "tools": [{"name": "weather", "input_schema": {"type":"object"}}]
    });

    let ir = decode_anthropic_request(&payload).unwrap();
    assert_eq!(ir.model.as_deref(), Some("claude-3-7-sonnet"));
    assert_eq!(ir.system_parts.len(), 1);
    assert_eq!(ir.tools.len(), 1);
}
```

**Step 2: 运行测试并确认失败**

Run: `cargo test -p fluxd anthropic_decoder_test -q`  
Expected: FAIL

**Step 3: 写最小实现（宽容解析 + extensions 收集）**

```rust
pub fn decode_anthropic_request(payload: &serde_json::Value) -> Result<IrRequest, FluxError> {
    let model = payload.get("model").and_then(|v| v.as_str()).map(ToOwned::to_owned);
    if model.is_none() {
        return Err(FluxError::decode("missing_model"));
    }
    // 解析 system/messages/tools，未知字段写入 extensions
    Ok(IrRequest { model, ..IrRequest::default() })
}
```

**Step 4: 运行测试并确认通过**

Run: `cargo test -p fluxd anthropic_decoder_test -q`  
Expected: PASS

**Step 5: 提交**

```bash
git add crates/fluxd/src/protocol/adapters crates/fluxd/tests/anthropic_decoder_test.rs
git commit -m "feat(fluxd): add anthropic request decoder to ir"
```

### Task 4: 实现 OpenAI 请求编码器与上游调用抽象

**Files:**
- Create: `crates/fluxd/src/protocol/adapters/openai/mod.rs`
- Create: `crates/fluxd/src/protocol/adapters/openai/request_encoder.rs`
- Modify: `crates/fluxd/src/upstream/openai_client.rs`
- Create: `crates/fluxd/tests/openai_encoder_test.rs`

**Step 1: 写失败测试（IR 编码为 OpenAI chat.completions payload）**

```rust
#[test]
fn encodes_ir_to_openai_chat_payload() {
    let ir = IrRequest::from_user_text("gpt-4o-mini", "hello");
    let payload = encode_openai_chat_request(&ir).unwrap();
    assert_eq!(payload["model"], "gpt-4o-mini");
    assert_eq!(payload["messages"][0]["role"], "user");
}
```

**Step 2: 运行测试并确认失败**

Run: `cargo test -p fluxd openai_encoder_test -q`  
Expected: FAIL

**Step 3: 写最小实现（请求编码 + client 调用保持透明）**

```rust
pub fn encode_openai_chat_request(ir: &IrRequest) -> Result<serde_json::Value, FluxError> {
    Ok(serde_json::json!({
        "model": ir.model,
        "messages": ir.messages,
        "tools": ir.tools
    }))
}
```

**Step 4: 运行测试并确认通过**

Run: `cargo test -p fluxd openai_encoder_test -q`  
Expected: PASS

**Step 5: 提交**

```bash
git add crates/fluxd/src/protocol/adapters/openai crates/fluxd/src/upstream/openai_client.rs crates/fluxd/tests/openai_encoder_test.rs
git commit -m "feat(fluxd): add openai request encoder from ir"
```

### Task 5: 新增 Anthropics 路由（非流式 messages）

**Files:**
- Create: `crates/fluxd/src/http/anthropic_routes.rs`
- Modify: `crates/fluxd/src/http/mod.rs`
- Create: `crates/fluxd/tests/anthropic_forwarding_test.rs`

**Step 1: 写失败测试（/v1/messages 非流式端到端转发）**

```rust
#[tokio::test]
async fn forwards_anthropic_messages_to_openai_upstream() {
    // 1) 启 mock openai upstream
    // 2) 配 gateway inbound=anthropic, upstream=openai
    // 3) POST /v1/messages
    // 4) 断言 anthropic 风格响应 shape
}
```

**Step 2: 运行测试并确认失败**

Run: `cargo test -p fluxd anthropic_forwarding_test -q`  
Expected: FAIL

**Step 3: 写最小实现（decode->ir->encode->upstream->decode->encode）**

```rust
let ir_req = anthropic::decode_request(&payload)?;
let upstream_payload = openai::encode_request(&ir_req)?;
let (status, upstream_body) = client.chat_completions(base_url, api_key, &upstream_payload).await?;
let ir_resp = openai::decode_response(&upstream_body)?;
let anthropic_body = anthropic::encode_response(&ir_resp)?;
```

**Step 4: 运行测试并确认通过**

Run: `cargo test -p fluxd anthropic_forwarding_test -q`  
Expected: PASS

**Step 5: 提交**

```bash
git add crates/fluxd/src/http/anthropic_routes.rs crates/fluxd/src/http/mod.rs crates/fluxd/tests/anthropic_forwarding_test.rs
git commit -m "feat(fluxd): add anthropic messages non-stream forwarding"
```

### Task 6: 实现流式 SSE 事件映射（Anthropic <-> OpenAI）

**Files:**
- Create: `crates/fluxd/src/protocol/stream/mod.rs`
- Create: `crates/fluxd/src/protocol/adapters/anthropic/stream_encoder.rs`
- Create: `crates/fluxd/src/protocol/adapters/openai/stream_decoder.rs`
- Modify: `crates/fluxd/src/http/anthropic_routes.rs`
- Create: `crates/fluxd/tests/anthropic_streaming_test.rs`

**Step 1: 写失败测试（stream=true 返回 Anthropics SSE 事件序列）**

```rust
#[tokio::test]
async fn maps_openai_sse_to_anthropic_sse_events() {
    // 构造 openai delta 事件流，断言输出包含 message_start/content_block_delta/message_stop
}
```

**Step 2: 运行测试并确认失败**

Run: `cargo test -p fluxd anthropic_streaming_test -q`  
Expected: FAIL

**Step 3: 写最小实现（统一事件 IR + SSE 编解码）**

```rust
pub enum IrStreamEvent {
    MessageStart,
    TextDelta(String),
    ToolDelta(serde_json::Value),
    MessageStop,
    Error(String),
}
```

**Step 4: 运行测试并确认通过**

Run: `cargo test -p fluxd anthropic_streaming_test -q`  
Expected: PASS

**Step 5: 提交**

```bash
git add crates/fluxd/src/protocol/stream crates/fluxd/src/protocol/adapters/anthropic/stream_encoder.rs crates/fluxd/src/protocol/adapters/openai/stream_decoder.rs crates/fluxd/src/http/anthropic_routes.rs crates/fluxd/tests/anthropic_streaming_test.rs
git commit -m "feat(fluxd): support anthropic streaming event mapping"
```

### Task 7: 实现 `/v1/messages/count_tokens` 与降级策略

**Files:**
- Modify: `crates/fluxd/src/http/anthropic_routes.rs`
- Create: `crates/fluxd/src/protocol/token_count.rs`
- Create: `crates/fluxd/tests/anthropic_count_tokens_test.rs`

**Step 1: 写失败测试（有上游能力与本地估算两条路径）**

```rust
#[tokio::test]
async fn count_tokens_uses_upstream_or_fallback_estimator() {
    // 场景A: upstream 返回 token count
    // 场景B: upstream 不支持，返回 estimated=true
}
```

**Step 2: 运行测试并确认失败**

Run: `cargo test -p fluxd anthropic_count_tokens_test -q`  
Expected: FAIL

**Step 3: 写最小实现（能力探测 + fallback estimator）**

```rust
pub async fn count_tokens(ir: &IrRequest, ctx: &CountContext) -> Result<CountResult, FluxError> {
    if let Some(v) = ctx.upstream_counter.count(ir).await? {
        return Ok(CountResult { input_tokens: v, estimated: false });
    }
    Ok(CountResult { input_tokens: estimate_tokens(ir), estimated: true })
}
```

**Step 4: 运行测试并确认通过**

Run: `cargo test -p fluxd anthropic_count_tokens_test -q`  
Expected: PASS

**Step 5: 提交**

```bash
git add crates/fluxd/src/http/anthropic_routes.rs crates/fluxd/src/protocol/token_count.rs crates/fluxd/tests/anthropic_count_tokens_test.rs
git commit -m "feat(fluxd): add anthropic count_tokens with fallback estimator"
```

### Task 8: 改造网关运行时按协议图选择路由

**Files:**
- Modify: `crates/fluxd/src/runtime/gateway_manager.rs`
- Modify: `crates/fluxd/src/http/openai_routes.rs`
- Modify: `crates/fluxd/tests/gateway_manager_test.rs`

**Step 1: 写失败测试（inbound=openai 与 inbound=anthropic 都可启动）**

```rust
#[tokio::test]
async fn gateway_manager_builds_router_by_inbound_protocol() {
    // 创建两个 gateway，分别 openai/anthropic，断言都可 Running
}
```

**Step 2: 运行测试并确认失败**

Run: `cargo test -p fluxd gateway_manager_test -q`  
Expected: FAIL

**Step 3: 写最小实现（match inbound_protocol 选择 router）**

```rust
let app = match gateway.inbound_protocol.as_str() {
    "openai" => build_openai_router(openai_state),
    "anthropic" => build_anthropic_router(anthropic_state),
    _ => return Err(anyhow!("unsupported inbound protocol")),
};
```

**Step 4: 运行测试并确认通过**

Run: `cargo test -p fluxd gateway_manager_test -q`  
Expected: PASS

**Step 5: 提交**

```bash
git add crates/fluxd/src/runtime/gateway_manager.rs crates/fluxd/src/http/openai_routes.rs crates/fluxd/tests/gateway_manager_test.rs
git commit -m "feat(fluxd): route gateway runtime by protocol graph"
```

### Task 9: 扩展 Admin/CLI/Desktop 配置入口

**Files:**
- Modify: `crates/fluxd/src/domain/gateway.rs`
- Modify: `crates/fluxd/src/http/admin_routes.rs`
- Modify: `crates/fluxd/tests/admin_api_test.rs`
- Modify: `crates/fluxctl/src/cli.rs`
- Modify: `crates/fluxctl/src/main.rs`
- Modify: `crates/fluxctl/tests/cli_smoke_test.rs`
- Modify: `apps/desktop/src/api/admin.ts`
- Modify: `apps/desktop/src/components/GatewayForm.tsx`
- Modify: `apps/desktop/src/App.test.tsx`

**Step 1: 写失败测试（可创建 anthropic 入站网关并带协议配置）**

```ts
it('submits anthropic gateway protocol config', async () => {
  const input = {
    inbound_protocol: 'anthropic',
    upstream_protocol: 'openai',
    protocol_config_json: { compatibility_mode: 'compatible' }
  };
  // expect api payload contains new fields
});
```

**Step 2: 运行测试并确认失败**

Run: `cargo test -p fluxctl -q && (cd apps/desktop && bun run test)`  
Expected: FAIL（新字段未暴露）

**Step 3: 写最小实现（Admin DTO + CLI 参数 + UI 表单）**

```rust
#[arg(long = "upstream-protocol", default_value = "provider_default")]
upstream_protocol: String,
```

```ts
export type CreateGatewayInput = {
  inbound_protocol: string;
  upstream_protocol: string;
  protocol_config_json: Record<string, unknown>;
};
```

**Step 4: 运行测试并确认通过**

Run: `cargo test -p fluxctl -q && (cd apps/desktop && bun run test)`  
Expected: PASS

**Step 5: 提交**

```bash
git add crates/fluxd/src/domain/gateway.rs crates/fluxd/src/http/admin_routes.rs crates/fluxd/tests/admin_api_test.rs crates/fluxctl/src/cli.rs crates/fluxctl/src/main.rs crates/fluxctl/tests/cli_smoke_test.rs apps/desktop/src/api/admin.ts apps/desktop/src/components/GatewayForm.tsx apps/desktop/src/App.test.tsx
git commit -m "feat(admin): expose protocol graph fields across api cli desktop"
```

### Task 10: 增加兼容模式、日志维度与文档

**Files:**
- Modify: `crates/fluxd/src/service/request_log_service.rs`
- Modify: `crates/fluxd/tests/request_log_retention_test.rs`
- Create: `crates/fluxd/tests/compatibility_mode_test.rs`
- Modify: `docs/contracts/admin-api-v1.md`
- Modify: `docs/USAGE.md`
- Create: `docs/testing/anthropic-compat-e2e.md`
- Create: `scripts/e2e/anthropic_compat.py`
- Modify: `scripts/e2e/smoke.sh`

**Step 1: 写失败测试（strict/compatible/permissive 行为差异）**

```rust
#[tokio::test]
async fn compatibility_mode_controls_degrade_or_reject() {
    // strict: capability_error
    // compatible: downgrade_with_notice
    // permissive: extension passthrough
}
```

**Step 2: 运行测试并确认失败**

Run: `cargo test -p fluxd compatibility_mode_test -q`  
Expected: FAIL

**Step 3: 写最小实现（模式选择 + 日志新增字段 + e2e 脚本）**

```rust
let mode = ProtocolMode::from_json(&gateway.protocol_config_json).unwrap_or(ProtocolMode::Compatible);
```

```bash
uv run scripts/e2e/anthropic_compat.py --admin-url http://127.0.0.1:7777
```

**Step 4: 运行全量验证并确认通过**

Run: `cargo test -q && (cd apps/desktop && bun run test) && ./scripts/e2e/smoke.sh`  
Expected: PASS，包含 anthropic 兼容链路通过标识

**Step 5: 提交**

```bash
git add crates/fluxd/src/service/request_log_service.rs crates/fluxd/tests/request_log_retention_test.rs crates/fluxd/tests/compatibility_mode_test.rs docs/contracts/admin-api-v1.md docs/USAGE.md docs/testing/anthropic-compat-e2e.md scripts/e2e/anthropic_compat.py scripts/e2e/smoke.sh
git commit -m "feat(anthropic): add compatibility modes logging and e2e docs"
```

## 实施要求（执行期）

- 严格按 TDD：先写失败测试，再写最小实现，再回归。
- 小步提交，每个 Task 一个 commit。
- 每个 Task 结束后更新文档与 `git status --short`。
- 执行时优先遵循：`@superpowers:test-driven-development`、`@superpowers:verification-before-completion`、`@superpowers:requesting-code-review`。
