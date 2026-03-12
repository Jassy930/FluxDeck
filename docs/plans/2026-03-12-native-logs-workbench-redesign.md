# Native Logs Workbench Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将原生端 Logs 页面从“请求列表 + 详情面板”改造成单列可展开日志卡片，并补齐后端与原生端对日志完整契约的支持，新增稳定字段 `cached_tokens`。

**Architecture:** 先在 `fluxd` 侧为 `request_logs`、Admin API 和测试引入稳定字段 `cached_tokens`，同时保持 `usage_json` 作为原始明细；再在 macOS 原生端补齐 `AdminLog` 解码模型与格式化规则，最后把 `LogsWorkbenchView` 重构为手风琴式单列日志流。`fluxctl` 保持原样打印 JSON，不改 CLI 行为，只同步文档与示例。

**Tech Stack:** Rust, SQLx/SQLite, SwiftUI, XCTest, Markdown docs

---

### Task 1: 扩展后端日志契约与存储字段

**Files:**
- Create: `crates/fluxd/migrations/006_request_logs_cached_tokens.sql`
- Modify: `crates/fluxd/src/forwarding/types.rs`
- Modify: `crates/fluxd/src/service/request_log_service.rs`
- Modify: `crates/fluxd/src/http/admin_routes.rs`
- Modify: `crates/fluxd/src/storage/migrate.rs`
- Modify: `crates/fluxd/tests/storage_migration_test.rs`
- Modify: `crates/fluxd/tests/request_log_service_test.rs`
- Modify: `crates/fluxd/tests/admin_api_test.rs`

**Step 1: 写失败测试，锁定 `cached_tokens` 作为稳定字段**

在以下测试中先加入断言：

- `crates/fluxd/tests/storage_migration_test.rs`
  - 断言 `request_logs` 包含 `cached_tokens`
- `crates/fluxd/tests/request_log_service_test.rs`
  - 插入日志后可读回 `cached_tokens`
- `crates/fluxd/tests/admin_api_test.rs`
  - `/admin/logs` 返回项包含 `cached_tokens`

**Step 2: 运行定向测试，确认失败**

Run: `cargo test -q --test storage_migration_test --test request_log_service_test --test admin_api_test`

Expected:
- migration 或解码断言失败
- 报错显示缺少 `cached_tokens` 列或字段

**Step 3: 写最小实现**

实现内容：

- 在 `UsageSnapshot` 增加 `cached_tokens: Option<i64>`
- 新增 migration `006_request_logs_cached_tokens.sql`
- 在 `request_log_service` 的插入与 `update_usage()` 回写路径写入 `cached_tokens`
- 在 `admin_routes.rs` 的查询结构与 JSON 输出中加入 `cached_tokens`
- 在 `storage/migrate.rs` 的 repair table 逻辑中同步加入 `cached_tokens`

**Step 4: 运行定向测试，确认通过**

Run: `cargo test -q --test storage_migration_test --test request_log_service_test --test admin_api_test`

Expected:
- 以上测试全部通过

**Step 5: 提交阶段成果**

```bash
git add crates/fluxd/migrations/006_request_logs_cached_tokens.sql crates/fluxd/src/forwarding/types.rs crates/fluxd/src/service/request_log_service.rs crates/fluxd/src/http/admin_routes.rs crates/fluxd/src/storage/migrate.rs crates/fluxd/tests/storage_migration_test.rs crates/fluxd/tests/request_log_service_test.rs crates/fluxd/tests/admin_api_test.rs
git commit -m "feat(logs): add cached tokens to admin logs"
```

### Task 2: 补齐原生端日志模型与格式化规则

**Files:**
- Modify: `apps/desktop-macos-native/FluxDeckNative/Networking/AdminApiClient.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`
- Optional Modify: `apps/desktop-macos-native/FluxDeckNative/Features/SettingsModels.swift`

**Step 1: 写失败测试，锁定原生端解码与展示规则**

在 `FluxDeckNativeTests.swift` 中新增或扩展测试：

- `decodeLogPage` 可解码：
  - `inbound_protocol`
  - `upstream_protocol`
  - `model_requested`
  - `model_effective`
  - `stream`
  - `first_byte_ms`
  - `input_tokens`
  - `output_tokens`
  - `cached_tokens`
  - `total_tokens`
  - `usage_json`
  - `error_stage`
  - `error_type`
- 新增格式化测试，断言模型显示优先级：
  - `requested != effective` 时显示 `requested -> effective`
  - 相同时只显示一个
- 新增 token 摘要测试，断言四类 token 文案可生成

**Step 2: 运行定向测试，确认失败**

Run: `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`

Expected:
- `AdminLog` 缺字段导致测试失败

**Step 3: 写最小实现**

实现内容：

- 扩展 `AdminLog` 模型字段与 `CodingKeys`
- 视需要新增日志展示辅助模型，例如：
  - `modelDisplayText`
  - `tokenBreakdownText`
  - `errorSummaryText`
- 若 `SettingsModels.swift` 中旧的 `LogDetailCardModel` 不再适用，删除或重构为日志项专用辅助模型

**Step 4: 运行定向测试，确认通过**

Run: `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`

Expected:
- 原生端测试通过

**Step 5: 提交阶段成果**

```bash
git add apps/desktop-macos-native/FluxDeckNative/Networking/AdminApiClient.swift apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift apps/desktop-macos-native/FluxDeckNative/Features/SettingsModels.swift
git commit -m "feat(native): decode full admin log fields"
```

### Task 3: 重构原生端 Logs 页面为可展开日志流

**Files:**
- Modify: `apps/desktop-macos-native/FluxDeckNative/Features/LogsWorkbenchView.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift`
- Optional Create: `apps/desktop-macos-native/FluxDeckNative/Features/LogStreamCard.swift`
- Optional Create: `apps/desktop-macos-native/FluxDeckNative/Features/LogExpandedDetail.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`

**Step 1: 写失败测试，锁定交互与文案结果**

优先写不依赖 UI 自动化的模型/辅助测试：

- 失败日志摘要优先显示错误文本
- 成功日志仍显示模型、路由、延迟、时间
- 手风琴模式下只允许一条展开
- 筛选变更或日志集合变化后，失效展开项会被重置

**Step 2: 运行定向测试，确认失败**

Run: `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`

Expected:
- 新增日志页行为测试失败

**Step 3: 写最小实现**

实现内容：

- 删除“Requests / Details” 双栏布局
- 将主体改为单列日志卡片列表
- 引入单一 `expandedRequestID` 状态
- 折叠态展示：
  - 状态
  - 路由
  - 模型/映射
  - 错误摘要
  - 延迟
  - 时间
- 展开态展示：
  - `request_id`
  - 协议字段
  - stream / first byte
  - 四类 token
  - error stage / error type
  - 完整错误文本
- 保持现有分页与筛选能力不变

**Step 4: 运行定向测试，确认通过**

Run: `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`

Expected:
- 原生端测试通过

**Step 5: 提交阶段成果**

```bash
git add apps/desktop-macos-native/FluxDeckNative/Features/LogsWorkbenchView.swift apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift
git commit -m "feat(native): redesign logs workbench stream"
```

### Task 4: 同步文档并确认 fluxctl 范围

**Files:**
- Modify: `docs/contracts/admin-api-v1.md`
- Modify: `docs/USAGE.md`
- Modify: `docs/ops/local-runbook.md`
- Optional Modify: `crates/fluxctl/src/main.rs`
- Optional Modify: `crates/fluxctl/tests/cli_smoke_test.rs`

**Step 1: 写失败检查项**

人工检查以下文档是否仍停留在旧描述：

- `Logs` 页面描述仍写成“请求列表 + 详情面板”
- 日志契约未包含 `cached_tokens`
- `fluxctl logs` 示例未体现新增日志字段

**Step 2: 更新文档**

更新内容：

- 契约文档增加 `cached_tokens`
- 使用说明更新日志页形态为“单列可展开日志卡片”
- `fluxctl` 章节说明其仍原样输出分页 JSON，不需要代码改动
- 示例 JSON 增加 `cached_tokens`

如果检查发现 `fluxctl` 内部存在对固定字段的额外格式化逻辑，再补代码与测试；否则只保留文档更新。

**Step 3: 运行最终验证**

Run: `cargo test -q`

Expected:
- Rust 测试通过

Run: `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`

Expected:
- 原生端测试通过

Run: `./scripts/e2e/smoke.sh`

Expected:
- 输出 `smoke ok`

**Step 4: 提交阶段成果**

```bash
git add docs/contracts/admin-api-v1.md docs/USAGE.md docs/ops/local-runbook.md crates/fluxctl/src/main.rs crates/fluxctl/tests/cli_smoke_test.rs
git commit -m "docs: sync logs workbench contract and usage"
```
