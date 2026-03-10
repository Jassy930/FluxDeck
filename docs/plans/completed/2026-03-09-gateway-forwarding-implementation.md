# Gateway Forwarding Implementation Plan

## Execution Status

- Date: 2026-03-09
- Batch: Tasks 1-8
- Status: completed and locally verified
- Note: plan-step `git commit` actions were intentionally not executed in this session

## Verification Results

- `cargo test -q`：PASS
- `cd apps/desktop && bun run test`：PASS（22 tests）
- `./scripts/e2e/smoke.sh`：PASS，输出包含 `cli-desktop consistency ok`、`anthropic compat ok`、`smoke ok`

## Completion Notes

- Task 1：已完成 `forwarding` 基础类型与测试
- Task 2：已完成 `TargetResolver` 与标准上游客户端抽象
- Task 3：已完成 `request_logs` 扩展字段与落库逻辑
- Task 4：已完成 OpenAI 入站共享执行器接入与流式转发
- Task 5：已完成 Anthropic -> OpenAI 共享核心接入与结构化日志/usage 记录
- Task 6：已完成 Anthropic -> Anthropic 原生上游普通/流式转发
- Task 7：已完成 Admin API logs 字段扩展与文档更新
- Task 8：已完成全项目验证与计划文档回填

## Deferred Behavior

- 本阶段仍未实现 `OpenAI inbound -> Anthropic upstream`
- 流式请求当前已记录 `stream` 与首包耗时入口，但未对流式 usage 做完整增量聚合
- `usage_json` 在 Admin API 中当前仍以字符串返回，后续若改为对象需要升级契约版本


> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a shared single-gateway forwarding core for FluxDeck that supports `OpenAI inbound -> OpenAI upstream`, `Anthropic inbound -> OpenAI upstream`, and `Anthropic inbound -> Anthropic upstream` with structured logging and usage extraction hooks.

**Architecture:** Introduce a protocol-agnostic forwarding core between inbound route decoding and upstream protocol clients. Keep gateway behavior limited to standard OpenAI/Anthropic protocols, and move target resolution, model resolution, observations, and usage hooks into shared modules.

**Tech Stack:** Rust, Axum, SQLx SQLite, reqwest, serde_json, existing FluxDeck admin/runtime/test stack

---

### Task 1: Add forwarding domain primitives

**Files:**
- Create: `crates/fluxd/src/forwarding/mod.rs`
- Create: `crates/fluxd/src/forwarding/types.rs`
- Modify: `crates/fluxd/src/lib.rs`
- Test: `crates/fluxd/tests/forwarding_types_test.rs`

**Step 1: Write the failing test**

```rust
use fluxd::forwarding::types::{ForwardObservation, UsageSnapshot};

#[test]
fn observation_and_usage_default_to_empty_optional_metrics() {
    let observation = ForwardObservation::new("req_1", "gw_1");
    let usage = UsageSnapshot::default();

    assert_eq!(observation.request_id, "req_1");
    assert_eq!(observation.gateway_id, "gw_1");
    assert_eq!(usage.input_tokens, None);
    assert_eq!(usage.output_tokens, None);
}
```

**Step 2: Run test to verify it fails**

Run: `cargo test -q -p fluxd --test forwarding_types_test`
Expected: FAIL with missing module or missing type errors

**Step 3: Write minimal implementation**

```rust
pub struct ForwardObservation {
    pub request_id: String,
    pub gateway_id: String,
    pub provider_id: Option<String>,
    pub inbound_protocol: Option<String>,
    pub upstream_protocol: Option<String>,
    pub model_requested: Option<String>,
    pub model_effective: Option<String>,
    pub is_stream: bool,
    pub status_code: Option<i64>,
    pub latency_ms: Option<i64>,
    pub first_byte_ms: Option<i64>,
    pub error_stage: Option<String>,
    pub error_type: Option<String>,
}

impl ForwardObservation {
    pub fn new(request_id: impl Into<String>, gateway_id: impl Into<String>) -> Self {
        Self {
            request_id: request_id.into(),
            gateway_id: gateway_id.into(),
            provider_id: None,
            inbound_protocol: None,
            upstream_protocol: None,
            model_requested: None,
            model_effective: None,
            is_stream: false,
            status_code: None,
            latency_ms: None,
            first_byte_ms: None,
            error_stage: None,
            error_type: None,
        }
    }
}

#[derive(Default)]
pub struct UsageSnapshot {
    pub input_tokens: Option<i64>,
    pub output_tokens: Option<i64>,
    pub total_tokens: Option<i64>,
    pub usage_json: Option<serde_json::Value>,
}
```

**Step 4: Run test to verify it passes**

Run: `cargo test -q -p fluxd --test forwarding_types_test`
Expected: PASS

**Step 5: Commit**

```bash
git add crates/fluxd/src/forwarding/mod.rs crates/fluxd/src/forwarding/types.rs crates/fluxd/src/lib.rs crates/fluxd/tests/forwarding_types_test.rs
git commit -m "feat(fluxd): add forwarding domain primitives"
```

### Task 2: Add target resolution and upstream client abstraction

**Files:**
- Create: `crates/fluxd/src/forwarding/target_resolver.rs`
- Create: `crates/fluxd/src/upstream/anthropic_client.rs`
- Modify: `crates/fluxd/src/upstream/mod.rs`
- Modify: `crates/fluxd/src/upstream/openai_client.rs`
- Test: `crates/fluxd/tests/target_resolver_test.rs`

**Step 1: Write the failing test**

```rust
use fluxd::forwarding::target_resolver::TargetResolver;

#[tokio::test]
async fn resolves_gateway_target_with_upstream_protocol() {
    let resolver = build_test_resolver().await;
    let target = resolver.resolve("gw_anthropic_native").await.expect("resolve target");

    assert_eq!(target.upstream_protocol, "anthropic");
    assert_eq!(target.provider_id, "provider_anthropic");
}
```

**Step 2: Run test to verify it fails**

Run: `cargo test -q -p fluxd --test target_resolver_test`
Expected: FAIL with missing resolver or field errors

**Step 3: Write minimal implementation**

```rust
pub struct ResolvedTarget {
    pub provider_id: String,
    pub upstream_protocol: String,
    pub base_url: String,
    pub api_key: String,
    pub effective_model: Option<String>,
    pub protocol_config: serde_json::Value,
}

pub struct TargetResolver {
    pool: sqlx::SqlitePool,
}

impl TargetResolver {
    pub fn new(pool: sqlx::SqlitePool) -> Self {
        Self { pool }
    }

    pub async fn resolve(&self, gateway_id: &str) -> anyhow::Result<ResolvedTarget> {
        // query gateways + providers and map row into ResolvedTarget
        todo!()
    }
}
```

**Step 4: Run test to verify it passes**

Run: `cargo test -q -p fluxd --test target_resolver_test`
Expected: PASS

**Step 5: Commit**

```bash
git add crates/fluxd/src/forwarding/target_resolver.rs crates/fluxd/src/upstream/anthropic_client.rs crates/fluxd/src/upstream/mod.rs crates/fluxd/src/upstream/openai_client.rs crates/fluxd/tests/target_resolver_test.rs
git commit -m "feat(fluxd): add target resolver and upstream clients"
```

### Task 3: Enhance request log schema for observations and usage

**Files:**
- Create: `crates/fluxd/migrations/004_request_log_forwarding_fields.sql`
- Modify: `crates/fluxd/src/service/request_log_service.rs`
- Modify: `crates/fluxd/tests/storage_migration_test.rs`
- Test: `crates/fluxd/tests/request_log_service_test.rs`

**Step 1: Write the failing test**

```rust
#[tokio::test]
async fn request_logs_persist_forwarding_observation_fields() {
    let pool = setup_db().await;
    append_test_log(&pool).await;

    let row = fetch_latest_log(&pool).await;
    assert_eq!(row.model_requested.as_deref(), Some("claude-3-7-sonnet"));
    assert_eq!(row.model_effective.as_deref(), Some("claude-sonnet-4-5"));
    assert_eq!(row.input_tokens, Some(128));
}
```

**Step 2: Run test to verify it fails**

Run: `cargo test -q -p fluxd --test request_log_service_test`
Expected: FAIL with missing columns or struct fields

**Step 3: Write minimal implementation**

```sql
ALTER TABLE request_logs ADD COLUMN inbound_protocol TEXT;
ALTER TABLE request_logs ADD COLUMN upstream_protocol TEXT;
ALTER TABLE request_logs ADD COLUMN model_requested TEXT;
ALTER TABLE request_logs ADD COLUMN model_effective TEXT;
ALTER TABLE request_logs ADD COLUMN stream INTEGER NOT NULL DEFAULT 0;
ALTER TABLE request_logs ADD COLUMN first_byte_ms INTEGER;
ALTER TABLE request_logs ADD COLUMN input_tokens INTEGER;
ALTER TABLE request_logs ADD COLUMN output_tokens INTEGER;
ALTER TABLE request_logs ADD COLUMN total_tokens INTEGER;
ALTER TABLE request_logs ADD COLUMN usage_json TEXT;
ALTER TABLE request_logs ADD COLUMN error_stage TEXT;
ALTER TABLE request_logs ADD COLUMN error_type TEXT;
```

**Step 4: Run test to verify it passes**

Run: `cargo test -q -p fluxd --test storage_migration_test --test request_log_service_test`
Expected: PASS

**Step 5: Commit**

```bash
git add crates/fluxd/migrations/004_request_log_forwarding_fields.sql crates/fluxd/src/service/request_log_service.rs crates/fluxd/tests/storage_migration_test.rs crates/fluxd/tests/request_log_service_test.rs
git commit -m "feat(fluxd): extend request logs for forwarding observations"
```

### Task 4: Migrate OpenAI inbound to shared forwarding core and add streaming

**Files:**
- Modify: `crates/fluxd/src/http/openai_routes.rs`
- Create: `crates/fluxd/src/forwarding/openai_inbound.rs`
- Create: `crates/fluxd/src/forwarding/executor.rs`
- Modify: `crates/fluxd/tests/openai_forwarding_test.rs`
- Create: `crates/fluxd/tests/openai_streaming_test.rs`

**Step 1: Write the failing test**

```rust
#[tokio::test]
async fn openai_chat_completions_streams_through_gateway() {
    let gateway = setup_openai_gateway_with_streaming_upstream().await;
    let body = call_openai_stream(gateway.addr).await;

    assert!(body.contains("chat.completion.chunk"));
    assert!(body.contains("[DONE]"));
}
```

**Step 2: Run test to verify it fails**

Run: `cargo test -q -p fluxd --test openai_streaming_test`
Expected: FAIL because OpenAI route does not stream yet

**Step 3: Write minimal implementation**

```rust
// decode request -> resolve target -> execute via OpenAiUpstreamClient
// branch on stream=true and proxy upstream byte stream back to client
// collect first_byte_ms and usage if present
```

**Step 4: Run test to verify it passes**

Run: `cargo test -q -p fluxd --test openai_forwarding_test --test openai_streaming_test`
Expected: PASS

**Step 5: Commit**

```bash
git add crates/fluxd/src/http/openai_routes.rs crates/fluxd/src/forwarding/openai_inbound.rs crates/fluxd/src/forwarding/executor.rs crates/fluxd/tests/openai_forwarding_test.rs crates/fluxd/tests/openai_streaming_test.rs
git commit -m "feat(fluxd): migrate openai forwarding to shared core"
```

### Task 5: Migrate Anthropic inbound to shared core for OpenAI upstream

**Files:**
- Modify: `crates/fluxd/src/http/anthropic_routes.rs`
- Create: `crates/fluxd/src/forwarding/anthropic_inbound.rs`
- Create: `crates/fluxd/src/forwarding/response_mapping.rs`
- Modify: `crates/fluxd/tests/anthropic_forwarding_test.rs`
- Modify: `crates/fluxd/tests/anthropic_streaming_test.rs`
- Modify: `crates/fluxd/tests/anthropic_count_tokens_test.rs`

**Step 1: Write the failing test**

```rust
#[tokio::test]
async fn anthropic_forwarding_records_effective_model_and_usage_fields() {
    let pool = setup_gateway_and_call_messages().await;
    let log = latest_request_log(&pool).await;

    assert_eq!(log.inbound_protocol.as_deref(), Some("anthropic"));
    assert_eq!(log.upstream_protocol.as_deref(), Some("openai"));
    assert!(log.model_effective.is_some());
}
```

**Step 2: Run test to verify it fails**

Run: `cargo test -q -p fluxd --test anthropic_forwarding_test`
Expected: FAIL with missing shared log fields or execution path

**Step 3: Write minimal implementation**

```rust
// reuse NormalizedRequest and executor
// keep Anthropic-specific decode/map logic in forwarding modules
// map response and usage into shared observation fields
```

**Step 4: Run test to verify it passes**

Run: `cargo test -q -p fluxd --test anthropic_forwarding_test --test anthropic_streaming_test --test anthropic_count_tokens_test --test compatibility_mode_test`
Expected: PASS

**Step 5: Commit**

```bash
git add crates/fluxd/src/http/anthropic_routes.rs crates/fluxd/src/forwarding/anthropic_inbound.rs crates/fluxd/src/forwarding/response_mapping.rs crates/fluxd/tests/anthropic_forwarding_test.rs crates/fluxd/tests/anthropic_streaming_test.rs crates/fluxd/tests/anthropic_count_tokens_test.rs
git commit -m "feat(fluxd): migrate anthropic to openai forwarding to shared core"
```

### Task 6: Add Anthropic upstream path for native Anthropic forwarding

**Files:**
- Modify: `crates/fluxd/src/http/anthropic_routes.rs`
- Modify: `crates/fluxd/src/upstream/anthropic_client.rs`
- Modify: `crates/fluxd/src/forwarding/executor.rs`
- Create: `crates/fluxd/tests/anthropic_native_forwarding_test.rs`
- Create: `crates/fluxd/tests/anthropic_native_streaming_test.rs`

**Step 1: Write the failing test**

```rust
#[tokio::test]
async fn forwards_anthropic_messages_to_anthropic_upstream() {
    let gateway = setup_anthropic_native_gateway().await;
    let response = call_anthropic_messages(gateway.addr).await;

    assert_eq!(response["type"], "message");
    assert_eq!(response["role"], "assistant");
}
```

**Step 2: Run test to verify it fails**

Run: `cargo test -q -p fluxd --test anthropic_native_forwarding_test`
Expected: FAIL because anthropic upstream path does not exist yet

**Step 3: Write minimal implementation**

```rust
// implement anthropic messages and count_tokens clients
// choose anthropic upstream branch when target.upstream_protocol == "anthropic"
// preserve native anthropic response semantics where possible
```

**Step 4: Run test to verify it passes**

Run: `cargo test -q -p fluxd --test anthropic_native_forwarding_test --test anthropic_native_streaming_test`
Expected: PASS

**Step 5: Commit**

```bash
git add crates/fluxd/src/http/anthropic_routes.rs crates/fluxd/src/upstream/anthropic_client.rs crates/fluxd/src/forwarding/executor.rs crates/fluxd/tests/anthropic_native_forwarding_test.rs crates/fluxd/tests/anthropic_native_streaming_test.rs
git commit -m "feat(fluxd): add anthropic native upstream forwarding"
```

### Task 7: Verify gateway runtime and admin surfaces remain stable

**Files:**
- Modify: `crates/fluxd/tests/admin_api_test.rs`
- Modify: `crates/fluxd/tests/gateway_manager_test.rs`
- Modify: `docs/USAGE.md`
- Modify: `docs/contracts/admin-api-v1.md`
- Modify: `docs/ops/local-runbook.md`

**Step 1: Write the failing test**

```rust
#[tokio::test]
async fn admin_logs_expose_forwarding_protocol_and_usage_fields() {
    let response = fetch_admin_logs().await;
    let first = &response["items"][0];

    assert!(first.get("inbound_protocol").is_some());
    assert!(first.get("upstream_protocol").is_some());
    assert!(first.get("input_tokens").is_some());
}
```

**Step 2: Run test to verify it fails**

Run: `cargo test -q -p fluxd --test admin_api_test`
Expected: FAIL with missing response fields

**Step 3: Write minimal implementation**

```rust
// extend admin log DTO and query mapping for new forwarding fields
// update usage docs and contract docs to describe new fields
```

**Step 4: Run test to verify it passes**

Run: `cargo test -q -p fluxd --test admin_api_test --test gateway_manager_test`
Expected: PASS

**Step 5: Commit**

```bash
git add crates/fluxd/tests/admin_api_test.rs crates/fluxd/tests/gateway_manager_test.rs docs/USAGE.md docs/contracts/admin-api-v1.md docs/ops/local-runbook.md
git commit -m "docs(fluxd): document gateway forwarding protocols and log fields"
```

### Task 8: Run full project verification

**Files:**
- Modify: `docs/plans/2026-03-09-gateway-forwarding-design.md`
- Modify: `docs/plans/2026-03-09-gateway-forwarding-implementation.md`

**Step 1: Run Rust verification**

Run: `cargo test -q`
Expected: PASS

**Step 2: Run frontend verification**

Run: `cd apps/desktop && bun run test`
Expected: PASS

**Step 3: Run end-to-end smoke verification**

Run: `./scripts/e2e/smoke.sh`
Expected: output contains `smoke ok`

**Step 4: Update documentation checkpoints**

```markdown
- Mark completed tasks
- Record verification command outputs
- Note any deferred protocol behavior explicitly
```

**Step 5: Commit**

```bash
git add docs/plans/2026-03-09-gateway-forwarding-design.md docs/plans/2026-03-09-gateway-forwarding-implementation.md
git commit -m "docs(plans): finalize gateway forwarding implementation plan"
```
