# Logs Pagination Performance Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 解决 `Logs` 页面进入时因日志链路取数、解码、状态更新、列表渲染叠加导致的卡顿问题，并在同一批次内完成 `fluxd`、原生端、Web 端、CLI、测试与文档的统一升级。

**Architecture:** 当前链路是“全局刷新直接拉 `/admin/logs` 固定数组，再把同一份 `logs` 同时喂给 Overview、Traffic、Connections、Topology、Logs 页面”。本次改造采用**同批次破坏式升级**：后端 `GET /admin/logs` 直接改为分页对象响应，所有客户端与测试同步迁移，不保留旧数组接口；原生端拆分 `dashboardLogs` 与 `logsPage`，首屏只拉轻量 recent logs，Logs 页面按需分页加载。

**Tech Stack:** Rust (`axum`, `sqlx`, SQLite), SwiftUI 原生端, React + TypeScript Web 端, Rust CLI (`fluxctl`), Admin API 契约文档。

---

## 审查后决策

### 决策 1：不做旧接口兼容
- `GET /admin/logs` 直接从“数组响应”升级为“分页对象响应”。
- 同一批次同时修改：
  - `fluxd`
  - `apps/desktop-macos-native`
  - `apps/desktop`
  - `crates/fluxctl`
  - 测试
  - 文档
- 不增加 `/admin/logs_v2`，也不保留旧数组 decoder。

### 决策 2：明确日志数据语义
- `dashboardLogs`：供 Overview / Traffic / Connections / Topology 使用，语义定义为“最近样本窗口”，默认 `limit=20`。
- `logsPage.items`：供 Logs 工作台使用，语义定义为“可继续翻页的请求明细列表”，默认第一页 `limit=50`。
- 这意味着原生监控类页面展示的是“最近样本监控”，不是数据库全量历史聚合；该语义要写入文档与页面文案。

### 决策 3：筛选项来源不再依赖当前日志页
- `gatewayOptions` 来自已加载的 gateways。
- `providerOptions` 来自已加载的 providers。
- `statusOptions` 使用固定集合：`All / 2xx / 4xx / 5xx`，如仍保留精确码筛选，再由服务端负责。
- 不再从当前日志页 `items` 去重生成筛选项，避免分页后筛选器缺项。

### 决策 4：错误过滤口径统一
- `errors_only=true` 的服务端定义统一为：`status_code >= 400 OR error IS NOT NULL`。
- Native / Web 的前端过滤文案与统计口径必须与此一致。

### 决策 5：分页排序必须稳定
- 排序使用：`ORDER BY created_at DESC, request_id DESC`。
- cursor 由：
  - `cursor_created_at`
  - `cursor_request_id`
 组成。
- 不允许只按 `created_at` 翻页，避免同秒请求顺序漂移。

---

## 方案对比

### 方案 A：仅把后端 `LIMIT 200` 改成更小值
- 优点：改动小，止血快。
- 缺点：仍然是“全量请求 + 全量解码 + 全量状态更新”，只是把上限往下压，问题会复发。

### 方案 B：只改前端渲染数量，不改后端接口
- 优点：前端改动最少。
- 缺点：客户端依旧先下载完整数组，网络与解码成本不变，不能根治。

### 方案 C：后端分页 + 原生端解耦 + Web/CLI/测试/文档同步升级（推荐）
- 优点：从接口、客户端状态、列表渲染、测试契约四层一起解决。
- 缺点：改动面最大，但这次用户已明确接受同批次统一升级。

**推荐选择：方案 C。**

---

## 影响矩阵

- **后端 `fluxd`**：`/admin/logs` 返回形状改变；需新增 query 解析、分页 SQL、过滤 SQL、稳定 cursor。
- **原生端 native**：`AdminApiClient` decoder 变更；`ContentView` 状态拆分；`LogsWorkbenchView` 增加分页加载；Overview/Traffic/Connections/Topology 改用 `dashboardLogs`。
- **Web 端**：`listLogs()` 返回类型改变；`refreshAll()` 不再默认把完整 logs 混入 dashboard 刷新语义；Logs 页面只消费分页 `items`。
- **CLI `fluxctl`**：`logs --limit` 真正下发到接口；输出响应对象而不是假设旧数组。
- **测试**：后端、native、web、CLI 契约测试全部同步迁移。
- **文档**：`docs/contracts/admin-api-v1.md`、`docs/USAGE.md`、本计划文档需同步更新。

---

### Task 1: 定义破坏式升级后的 `/admin/logs` 新契约

**Files:**
- Modify: `docs/contracts/admin-api-v1.md`
- Modify: `docs/USAGE.md`
- Modify: `docs/plans/2026-03-07-logs-pagination-performance-plan.md`
- Reference: `crates/fluxd/src/http/admin_routes.rs:174`
- Reference: `crates/fluxd/migrations/001_init.sql:33`

**Step 1: 写出最终契约草案**

定义查询参数：
- `limit`：单次返回条数，默认 `50`，最大 `100`
- `cursor_created_at`：分页游标时间戳
- `cursor_request_id`：同时间戳下的稳定次级游标
- `gateway_id`：按 gateway 过滤
- `provider_id`：按 provider 过滤
- `status_code`：按精确状态码过滤
- `errors_only`：仅返回 `status_code >= 400 OR error != null`

定义响应结构：

```json
{
  "items": [
    {
      "request_id": "req_001",
      "gateway_id": "gw_1",
      "provider_id": "pv_1",
      "model": "gpt-4o-mini",
      "status_code": 200,
      "latency_ms": 123,
      "error": null,
      "created_at": "2026-03-08T10:00:00Z"
    }
  ],
  "next_cursor": {
    "created_at": "2026-03-08T09:59:00Z",
    "request_id": "req_000"
  },
  "has_more": true
}
```

**Step 2: 明确破坏式升级范围**
- 在文档中明确：`GET /admin/logs` 不再返回数组。
- 在文档中明确：本次为同批次升级，不提供旧接口兼容层。

**Step 3: 明确排序与语义**
- 文档写明服务端排序：`created_at DESC, request_id DESC`
- 文档写明 native 监控页使用“最近样本窗口”
- 文档写明 Logs 页面为“分页请求明细”

**Step 4: 补充 CLI / UI 使用说明**
- `fluxctl logs --limit 20`
- Logs 页面默认只加载第一页
- 更多数据通过 `Load More` 请求下一页

**Step 5: Commit**

```bash
git add docs/contracts/admin-api-v1.md docs/USAGE.md docs/plans/2026-03-07-logs-pagination-performance-plan.md
git commit -m "docs(logs): finalize paginated logs upgrade plan"
```

---

### Task 2: 为 `fluxd` 实现分页、过滤与稳定排序

**Files:**
- Modify: `crates/fluxd/src/http/admin_routes.rs:174`
- Test: `crates/fluxd/tests/admin_api_test.rs`
- Reference: `crates/fluxd/migrations/001_init.sql:33`

**Step 1: 写失败测试：响应体从数组升级为分页对象**

在 `crates/fluxd/tests/admin_api_test.rs` 增加测试：
- 插入 60 条日志
- 请求 `GET /admin/logs`
- 断言：
  - HTTP 200
  - JSON 为对象，不是数组
  - `items.len() == 50`
  - `has_more == true`
  - `next_cursor.created_at` 非空
  - `next_cursor.request_id` 非空

**Step 2: 跑测试，确认失败**

Run:
```bash
cargo test -q admin_api_test -- --nocapture
```

Expected: FAIL，因为当前接口仍返回数组且固定 `LIMIT 200`

**Step 3: 写失败测试：排序和 cursor 稳定**
- 插入多条 `created_at` 相同、`request_id` 不同的日志
- 拉第一页，再用返回的 cursor 拉第二页
- 断言无重复、无丢失、顺序稳定

**Step 4: 跑测试，确认失败**

Run:
```bash
cargo test -q admin_api_test -- --nocapture
```

Expected: FAIL

**Step 5: 写最小实现 `LogListQuery + LogListCursor + LogListResponse`**
- 新增 query DTO
- 新增 response DTO
- SQL 使用：
  - `ORDER BY created_at DESC, request_id DESC`
  - `LIMIT requested_limit + 1`
  - 根据是否多取到一条决定 `has_more`
- cursor 条件：
  - `created_at < ?`
  - 或 `(created_at = ? AND request_id < ?)`

**Step 6: 跑测试，确认通过**

Run:
```bash
cargo test -q admin_api_test -- --nocapture
```

Expected: PASS

**Step 7: 写失败测试：服务端过滤生效**
新增测试：
- `gateway_id` 过滤
- `provider_id` 过滤
- `status_code` 过滤
- `errors_only=true` 过滤（同时覆盖 `status >= 400` 与 `error != null`）
- `limit=10` 生效
- 非法 `limit` 被约束到最大值

**Step 8: 跑测试，确认失败**

Run:
```bash
cargo test -q admin_api_test -- --nocapture
```

Expected: FAIL

**Step 9: 写最小过滤实现**
- 拼接 WHERE 条件
- 统一 `errors_only` 逻辑
- 保持返回 DTO 字段稳定

**Step 10: 跑测试，确认通过**

Run:
```bash
cargo test -q admin_api_test -- --nocapture
```

Expected: PASS

**Step 11: Commit**

```bash
git add crates/fluxd/src/http/admin_routes.rs crates/fluxd/tests/admin_api_test.rs
git commit -m "feat(fluxd): paginate admin logs endpoint"
```

---

### Task 3: 原生端拆分 `dashboardLogs` 与 `logsPage`

**Files:**
- Modify: `apps/desktop-macos-native/FluxDeckNative/Networking/AdminApiClient.swift:170`
- Modify: `apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative/Features/OverviewDashboardView.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative/Features/LogsWorkbenchView.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative/Features/TrafficConnectionsModels.swift`
- Test: `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`

**Step 1: 写失败测试：分页对象解码成功**
- 给定 `AdminLogPage` JSON
- 断言 `items / has_more / next_cursor` 解码正确

**Step 2: 跑测试，确认失败**

Run:
```bash
env HOME=/tmp xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -destination 'platform=macOS' -derivedDataPath /tmp/fluxdeck-native-derived -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testDecodesPaginatedLogsPayload
```

Expected: FAIL，当前只支持 `[AdminLog]`

**Step 3: 实现网络层最小改造**
在 `AdminApiClient.swift` 增加：
- `AdminLogPage`
- `AdminLogCursor`
- `fetchLogs(limit:cursor:gatewayID:providerID:statusCode:errorsOnly:)`
- `fetchDashboardLogs(limit:)`

**Step 4: 跑测试，确认通过**

Run 同上。
Expected: PASS

**Step 5: 拆分 `ContentView` 状态**
- 删除“单一全局 `logs` 负责所有页面”的做法
- 新增：
  - `dashboardLogs: [AdminLog]`
  - `logsPageItems: [AdminLog]`
  - `logsPageCursor: AdminLogCursor?`
  - `logsPageHasMore: Bool`
  - `isLogsPageLoading: Bool`
  - `hasLoadedInitialLogsPage: Bool`
- Logs 过滤状态只作用于 Logs 页面请求，不再对 dashboardLogs 做本地二次筛选

**Step 6: 调整全局刷新语义**
`refreshAll()` 改为只拉：
- providers
- gateways
- `dashboardLogs(limit: 20)`

不要在首屏刷新和 create/update/start/stop 后顺手拉完整 Logs 工作台数据。

**Step 7: 调整监控类页面语义**
- `Overview` recent logs 使用 `dashboardLogs`
- `Traffic / Connections / Topology` 也明确改为使用 `dashboardLogs`
- 如页面文案涉及“all requests / full history”，同步改为“recent requests / recent sample”

**Step 8: Logs 页面按需加载第一页**
- 首次进入 `.logs` 时发起 `limit=50` 请求
- 首次载入默认选中第一条
- 切换筛选条件时清空旧分页并重新请求第一页

**Step 9: Logs 页面改为惰性列表并增加 `Load More`**
- 将 `VStack` 改为 `LazyVStack`
- 底部增加 `Load More` 按钮
- append 下一页时保持当前 `selectedRequestID`

**Step 10: 调整筛选项来源**
- `gatewayOptions` 来自 `gateways`
- `providerOptions` 来自 `providers`
- `statusOptions` 使用固定集合或明确精确码列表
- 不再从当前 `logsPageItems` 去重生成筛选项

**Step 11: 统一 `errorsOnly` 口径**
- native 端任何本地展示/标签逻辑都以 `status >= 400 || error != nil` 为准
- 与后端过滤条件一致

**Step 12: 跑原生测试，确认通过**

Run:
```bash
env HOME=/tmp xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -destination 'platform=macOS' -derivedDataPath /tmp/fluxdeck-native-derived
```

Expected: PASS

**Step 13: Commit**

```bash
git add apps/desktop-macos-native/FluxDeckNative/Networking/AdminApiClient.swift apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift apps/desktop-macos-native/FluxDeckNative/Features/OverviewDashboardView.swift apps/desktop-macos-native/FluxDeckNative/Features/LogsWorkbenchView.swift apps/desktop-macos-native/FluxDeckNative/Features/TrafficConnectionsModels.swift apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift
git commit -m "feat(native): paginate logs workbench data"
```

---

### Task 4: Web 端同步迁移到新日志 DTO

**Files:**
- Modify: `apps/desktop/src/api/admin.ts:60`
- Modify: `apps/desktop/src/App.tsx:37`
- Modify: `apps/desktop/src/App.test.tsx`
- Modify: `apps/desktop/src/ui/logs/LogSection.tsx`
- Modify: `apps/desktop/src/components/LogPanel.tsx`

**Step 1: 写失败测试：`listLogs` 解码分页对象**
- mock `GET /admin/logs` 返回分页对象
- 断言 Web 端 API 层解码成功
- 断言 Logs 页面仍能渲染第一页 `items`

**Step 2: 跑测试，确认失败**

Run:
```bash
cd apps/desktop && bun run test
```

Expected: FAIL，当前 `listLogs()` 仍期待数组

**Step 3: 实现最小 DTO 迁移**
在 `admin.ts` 中新增：
- `RequestLogCursor`
- `RequestLogPage`
- `listLogs(params?): Promise<RequestLogPage>`

**Step 4: 调整 dashboard 刷新语义**
- `listDashboardLists()` 不再依赖完整 Logs 工作台分页数据
- 如 Web 仍需展示首页日志，只拉第一页少量 `items`
- `App.tsx` 中页面状态与 header 计数改为消费新结构

**Step 5: 调整 Logs 页面消费方式**
- `LogSection` 先只消费 `items`
- 如当前 Web 未实现完整分页交互，也至少确保契约与 decoder 已同步升级

**Step 6: 跑测试，确认通过**

Run:
```bash
cd apps/desktop && bun run test
```

Expected: PASS

**Step 7: Commit**

```bash
git add apps/desktop/src/api/admin.ts apps/desktop/src/App.tsx apps/desktop/src/App.test.tsx apps/desktop/src/ui/logs/LogSection.tsx apps/desktop/src/components/LogPanel.tsx
git commit -m "feat(web): adopt paginated admin logs response"
```

---

### Task 5: CLI 同步接入分页参数

**Files:**
- Modify: `crates/fluxctl/src/cli.rs:23`
- Modify: `crates/fluxctl/src/main.rs:86`
- Test: `crates/fluxctl` 现有测试文件或新增 CLI 参数测试
- Modify: `docs/USAGE.md:241`

**Step 1: 写失败测试或最小回归用例**
- 覆盖 `fluxctl logs --limit 20` 会把 `limit=20` 传给 `/admin/logs`
- 覆盖 CLI 能正确打印分页对象

**Step 2: 跑测试，确认失败**

Run:
```bash
cargo test -q -p fluxctl
```

Expected: FAIL，当前 `limit` 参数没有下发到接口

**Step 3: 实现最小修复**
- 在 `main.rs` 中拼接 `/admin/logs?limit=...`
- 如需要，补充后续 filter 参数扩展点

**Step 4: 跑测试，确认通过**

Run:
```bash
cargo test -q -p fluxctl
```

Expected: PASS

**Step 5: Commit**

```bash
git add crates/fluxctl/src/cli.rs crates/fluxctl/src/main.rs docs/USAGE.md
git commit -m "feat(fluxctl): pass logs pagination params"
```

---

### Task 6: 全量回归与性能验收

**Files:**
- Reference: `docs/contracts/admin-api-v1.md`
- Reference: `docs/USAGE.md`
- Reference: `docs/plans/2026-03-07-logs-pagination-performance-plan.md`

**Step 1: 运行后端测试**

Run:
```bash
cargo test -q admin_api_test -- --nocapture
```

Expected: PASS

**Step 2: 运行 `fluxctl` 测试**

Run:
```bash
cargo test -q -p fluxctl
```

Expected: PASS

**Step 3: 运行 Web 测试**

Run:
```bash
cd apps/desktop && bun run test
```

Expected: PASS

**Step 4: 运行原生端测试**

Run:
```bash
env HOME=/tmp xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -destination 'platform=macOS' -derivedDataPath /tmp/fluxdeck-native-derived
```

Expected: PASS

**Step 5: 运行仓库建议验收命令**

Run:
```bash
cargo test -q
```

Expected: PASS

Run:
```bash
cd apps/desktop && bun run test
```

Expected: PASS

**Step 6: 手工验收要点**
- 首次进入原生首页不再加载完整 Logs 工作台数据
- 首次切换到 Logs 页面只请求第一页
- 点击 `Load More` 能正确追加且无重复
- 改变筛选条件会重置分页并重新加载第一页
- `errorsOnly` 与后端返回结果口径一致
- Web / CLI / Native 都能消费同一个新契约

**Step 7: 最终 Commit**

```bash
git add docs/contracts/admin-api-v1.md docs/USAGE.md docs/plans/2026-03-07-logs-pagination-performance-plan.md
git commit -m "docs(logs): record pagination rollout and verification"
```
