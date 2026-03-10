# FluxDeck MVP Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在 macOS 上交付可运行的本地 LLM API 转发与管理 MVP：支持 OpenAI Provider 配置、多网关启停、OpenAI Chat Completions 转发、桌面 UI 与 CLI 管理。

**Architecture:** 采用 `Tauri Desktop + 独立本地服务 fluxd + CLI fluxctl` 的分层架构。`fluxd` 同时承载控制面（Admin API）与数据面（OpenAI 入站转发），SQLite 负责持久化配置与日志。桌面端与 CLI 均通过 Admin API 管理资源，避免重复业务逻辑。

**Tech Stack:** Rust (`tokio`/`axum`/`serde`/`sqlx`/`clap`), SQLite, Tauri v2, React + TypeScript（`bun` 管理）, Python 工具链预留 `uv`。

---

### Task 1: 初始化仓库与工作区骨架

**Files:**
- Create: `Cargo.toml`
- Create: `crates/fluxd/Cargo.toml`
- Create: `crates/fluxd/src/main.rs`
- Create: `crates/fluxctl/Cargo.toml`
- Create: `crates/fluxctl/src/main.rs`
- Create: `apps/desktop/package.json`
- Create: `apps/desktop/src/main.tsx`
- Create: `README.md`
- Test: `crates/fluxd/src/main.rs`（最小 smoke 测试）

**Step 1: 写失败测试（Rust workspace 启动测试）**

```rust
#[test]
fn workspace_compiles() {
    assert!(true);
}
```

**Step 2: 运行测试并确认失败（骨架未建成前）**

Run: `cargo test -q`
Expected: FAIL（缺少 workspace/crates）

**Step 3: 写最小实现（工作区与最小入口）**

```rust
#[tokio::main]
async fn main() {
    println!("fluxd bootstrap");
}
```

**Step 4: 运行测试确认通过**

Run: `cargo test -q`
Expected: PASS

**Step 5: 提交**

```bash
git add Cargo.toml crates apps README.md
git commit -m "chore: bootstrap fluxdeck workspace skeleton"
```

### Task 2: 建立 SQLite 与 migration 基础设施

**Files:**
- Create: `crates/fluxd/migrations/001_init.sql`
- Create: `crates/fluxd/src/storage/mod.rs`
- Create: `crates/fluxd/src/storage/migrate.rs`
- Create: `crates/fluxd/tests/storage_migration_test.rs`

**Step 1: 写失败测试（migration 执行后表存在）**

```rust
#[tokio::test]
async fn migration_creates_core_tables() {
    // 连接临时 sqlite，运行 migration，断言 providers/gateways/request_logs 存在
}
```

**Step 2: 运行单测确认失败**

Run: `cargo test -p fluxd storage_migration_test -q`
Expected: FAIL（migration 模块缺失）

**Step 3: 写最小实现（加载 SQL 并执行）**

```rust
pub async fn run_migrations(pool: &SqlitePool) -> anyhow::Result<()> {
    sqlx::migrate!("./migrations").run(pool).await?;
    Ok(())
}
```

**Step 4: 再跑测试确认通过**

Run: `cargo test -p fluxd storage_migration_test -q`
Expected: PASS

**Step 5: 提交**

```bash
git add crates/fluxd/migrations crates/fluxd/src/storage crates/fluxd/tests
git commit -m "feat: add sqlite schema and migration runner"
```

### Task 3: Provider 数据模型与 CRUD（服务层）

**Files:**
- Create: `crates/fluxd/src/domain/provider.rs`
- Create: `crates/fluxd/src/repo/provider_repo.rs`
- Create: `crates/fluxd/src/service/provider_service.rs`
- Create: `crates/fluxd/tests/provider_service_test.rs`

**Step 1: 写失败测试（创建/查询 Provider）**

```rust
#[tokio::test]
async fn create_and_get_provider() {
    // create provider then fetch by id and assert base_url/models
}
```

**Step 2: 跑测试确认失败**

Run: `cargo test -p fluxd provider_service_test -q`
Expected: FAIL

**Step 3: 实现最小 CRUD**

```rust
pub async fn create_provider(&self, input: CreateProviderInput) -> anyhow::Result<Provider>;
pub async fn list_providers(&self) -> anyhow::Result<Vec<Provider>>;
```

**Step 4: 跑测试确认通过**

Run: `cargo test -p fluxd provider_service_test -q`
Expected: PASS

**Step 5: 提交**

```bash
git add crates/fluxd/src/domain crates/fluxd/src/repo crates/fluxd/src/service crates/fluxd/tests
git commit -m "feat: implement provider service and repository"
```

### Task 4: Gateway 数据模型与多网关运行时管理

**Files:**
- Create: `crates/fluxd/src/domain/gateway.rs`
- Create: `crates/fluxd/src/repo/gateway_repo.rs`
- Create: `crates/fluxd/src/runtime/gateway_manager.rs`
- Create: `crates/fluxd/tests/gateway_manager_test.rs`

**Step 1: 写失败测试（两个网关不同端口可并存）**

```rust
#[tokio::test]
async fn starts_multiple_gateways_on_different_ports() {
    // create two gateway configs and assert both running
}
```

**Step 2: 跑测试确认失败**

Run: `cargo test -p fluxd gateway_manager_test -q`
Expected: FAIL

**Step 3: 最小实现（启动/停止/状态查询）**

```rust
pub async fn start_gateway(&self, gateway_id: Uuid) -> anyhow::Result<()>;
pub async fn stop_gateway(&self, gateway_id: Uuid) -> anyhow::Result<()>;
pub fn status(&self, gateway_id: Uuid) -> GatewayStatus;
```

**Step 4: 跑测试确认通过**

Run: `cargo test -p fluxd gateway_manager_test -q`
Expected: PASS

**Step 5: 提交**

```bash
git add crates/fluxd/src/domain crates/fluxd/src/repo crates/fluxd/src/runtime crates/fluxd/tests
git commit -m "feat: add multi-gateway runtime manager"
```

### Task 5: OpenAI 入站接口与上游转发

**Files:**
- Create: `crates/fluxd/src/http/openai_routes.rs`
- Create: `crates/fluxd/src/upstream/openai_client.rs`
- Create: `crates/fluxd/tests/openai_forwarding_test.rs`

**Step 1: 写失败测试（/v1/chat/completions 端到端转发）**

```rust
#[tokio::test]
async fn forwards_chat_completions_to_upstream() {
    // mock upstream + call gateway endpoint + assert mapped response
}
```

**Step 2: 跑测试确认失败**

Run: `cargo test -p fluxd openai_forwarding_test -q`
Expected: FAIL

**Step 3: 最小实现（请求映射 + header 注入 + 透传响应）**

```rust
let resp = upstream_client.chat_completions(provider, payload).await?;
Ok(Json(resp))
```

**Step 4: 跑测试确认通过**

Run: `cargo test -p fluxd openai_forwarding_test -q`
Expected: PASS

**Step 5: 提交**

```bash
git add crates/fluxd/src/http crates/fluxd/src/upstream crates/fluxd/tests
git commit -m "feat: support openai chat completions forwarding"
```

### Task 6: Admin API（Provider/Gateway 管理与日志查询）

**Files:**
- Create: `crates/fluxd/src/http/admin_routes.rs`
- Create: `crates/fluxd/src/http/dto.rs`
- Create: `crates/fluxd/tests/admin_api_test.rs`

**Step 1: 写失败测试（创建 Provider/Gateway、启停、查日志）**

```rust
#[tokio::test]
async fn admin_api_manages_resources() {
    // POST provider, POST gateway, start, stop, GET logs
}
```

**Step 2: 跑测试确认失败**

Run: `cargo test -p fluxd admin_api_test -q`
Expected: FAIL

**Step 3: 最小实现（REST 路由 + service 调用）**

```rust
Router::new()
  .route("/admin/providers", post(create_provider).get(list_providers))
  .route("/admin/gateways", post(create_gateway).get(list_gateways));
```

**Step 4: 跑测试确认通过**

Run: `cargo test -p fluxd admin_api_test -q`
Expected: PASS

**Step 5: 提交**

```bash
git add crates/fluxd/src/http crates/fluxd/tests
git commit -m "feat: add admin api for providers gateways and logs"
```

### Task 7: CLI 工具 fluxctl

**Files:**
- Create: `crates/fluxctl/src/cli.rs`
- Create: `crates/fluxctl/src/client.rs`
- Modify: `crates/fluxctl/src/main.rs`
- Create: `crates/fluxctl/tests/cli_smoke_test.rs`

**Step 1: 写失败测试（provider/gateway 命令可调用）**

```rust
#[test]
fn parses_provider_create_command() {
    // clap parse should succeed
}
```

**Step 2: 跑测试确认失败**

Run: `cargo test -p fluxctl -q`
Expected: FAIL

**Step 3: 最小实现（clap 子命令 + Admin API client）**

```rust
#[derive(clap::Subcommand)]
enum Commands { Provider(ProviderCmd), Gateway(GatewayCmd), Logs(LogsCmd) }
```

**Step 4: 跑测试确认通过**

Run: `cargo test -p fluxctl -q`
Expected: PASS

**Step 5: 提交**

```bash
git add crates/fluxctl
git commit -m "feat: add fluxctl admin commands"
```

### Task 8: Tauri 桌面端最小管理界面

**Files:**
- Create: `apps/desktop/src/App.tsx`
- Create: `apps/desktop/src/api/admin.ts`
- Create: `apps/desktop/src/components/ProviderPanel.tsx`
- Create: `apps/desktop/src/components/GatewayPanel.tsx`
- Create: `apps/desktop/src/components/LogPanel.tsx`
- Create: `apps/desktop/src/App.test.tsx`

**Step 1: 写失败测试（渲染 Provider/Gateway/Logs 三面板）**

```tsx
it('renders core management panels', () => {
  render(<App />)
  expect(screen.getByText('Providers')).toBeInTheDocument()
})
```

**Step 2: 跑测试确认失败**

Run: `bun run test`
Expected: FAIL

**Step 3: 最小实现（调用 Admin API + 列表展示 + 启停按钮）**

```tsx
useEffect(() => { void loadProviders(); void loadGateways(); void loadLogs(); }, [])
```

**Step 4: 跑测试确认通过**

Run: `bun run test`
Expected: PASS

**Step 5: 提交**

```bash
git add apps/desktop
git commit -m "feat: add desktop mvp management ui"
```

### Task 9: 请求日志记录与滚动清理策略

**Files:**
- Create: `crates/fluxd/src/service/request_log_service.rs`
- Modify: `crates/fluxd/src/http/openai_routes.rs`
- Create: `crates/fluxd/tests/request_log_retention_test.rs`

**Step 1: 写失败测试（超上限时仅保留最近 N 条）**

```rust
#[tokio::test]
async fn trims_old_logs_by_count_limit() {
    // insert N+K logs then assert only latest N remains
}
```

**Step 2: 跑测试确认失败**

Run: `cargo test -p fluxd request_log_retention_test -q`
Expected: FAIL

**Step 3: 最小实现（写日志 + 定额清理）**

```rust
pub async fn append_and_trim(&self, entry: RequestLog, keep: i64) -> anyhow::Result<()>;
```

**Step 4: 跑测试确认通过**

Run: `cargo test -p fluxd request_log_retention_test -q`
Expected: PASS

**Step 5: 提交**

```bash
git add crates/fluxd/src/service crates/fluxd/src/http crates/fluxd/tests
git commit -m "feat: add request log retention policy"
```

### Task 10: 端到端验证、文档与发布说明

**Files:**
- Create: `scripts/e2e/smoke.sh`
- Create: `docs/testing/mvp-e2e.md`
- Modify: `README.md`
- Create: `docs/ops/local-runbook.md`

**Step 1: 写失败验证脚本（未满足前返回非 0）**

```bash
#!/usr/bin/env bash
set -euo pipefail
# start fluxd, create provider/gateway via fluxctl, curl chat endpoint
```

**Step 2: 运行脚本确认失败（功能尚未闭环前）**

Run: `./scripts/e2e/smoke.sh`
Expected: FAIL

**Step 3: 补齐最小脚本与文档**

```markdown
1. 启动 fluxd
2. 用 fluxctl 创建 provider/gateway
3. curl 调用 /v1/chat/completions
```

**Step 4: 回归验证全部通过**

Run: `cargo test -q && bun run test && ./scripts/e2e/smoke.sh`
Expected: PASS

**Step 5: 提交**

```bash
git add scripts docs README.md
git commit -m "docs: add mvp e2e runbook and verification"
```

## 执行约束（必须遵守）

- 每个 Task 均采用 TDD：先失败测试，再最小实现，再验证通过。
- 每个 Task 完成后都要更新文档与 `git status`。
- JavaScript/TypeScript 依赖与脚本统一使用 `bun`。
- Python 相关工具（若引入）统一使用 `uv`。
- 不在 MVP 内提前引入 WebUI 与多协议适配。

## MVP 最终验收命令（汇总）

```bash
cargo test -q
bun run test
./scripts/e2e/smoke.sh
```
