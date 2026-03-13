# Native Traffic KPI Supplement Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为原生端 `Traffic` 页四个 KPI 增加附属指标，并将 tokens 的 `cached` 统计改为由 `fluxd` 直接提供的稳定字段。

**Architecture:** 在 `fluxd` 的 `/admin/stats/overview` 与 `/admin/stats/trend` 中新增 `cached_tokens` 聚合字段，并扩展维度统计结构；原生端 `AdminApiClient` 与 `TrafficAnalyticsModel` 改为直接消费这些稳定字段。`TrafficAnalyticsView` 保持现有连续 KPI 指标栏结构，仅渲染后端提供的附属指标。

**Tech Stack:** Rust、SQLx/SQLite、SwiftUI、Foundation、cargo test、xcodebuild、Markdown

---

### Task 1: 为 stats cached_tokens 契约写失败测试

**Files:**
- Modify: `crates/fluxd/tests/admin_api_test.rs`
- Modify: `crates/fluxd/src/http/admin_routes.rs`
- Modify: `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative/Networking/AdminApiClient.swift`

**Step 1: Write the failing test**

新增测试，断言：

- `GET /admin/stats/overview` 返回 `cached_tokens`
- `by_gateway` 维度返回 `cached_tokens`
- `GET /admin/stats/trend` 的每个 bucket 返回 `cached_tokens`
- 原生端可成功解码这些字段

**Step 2: Run test to verify it fails**

Run:

```bash
cargo test -q --test admin_api_test admin_api_stats_endpoints_return_cached_token_fields
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testAdminStatsOverviewAndTrendDecodeCachedTokens -derivedDataPath /tmp/fluxdeck-native-derived-kpi-cached -quiet
```

Expected: FAIL，提示缺少 `cached_tokens` 字段或解码失败

**Step 3: Write minimal implementation**

- 在 `fluxd` stats 聚合结构中加入 `cached_tokens`
- 扩展原生端解码模型

**Step 4: Run test to verify it passes**

Run 同上

Expected: PASS

### Task 2: 接入原生端模型消费并移除 cached 推导

**Files:**
- Modify: `apps/desktop-macos-native/FluxDeckNative/Features/TrafficConnectionsModels.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative/Features/TrafficAnalyticsView.swift`

**Step 1: Consume backend cached tokens**

- 保持 KPI 多行附属指标布局
- `Total Tokens` 改为直接显示后端返回的 `cached_tokens`
- 移除 `total_tokens - input - output` 的前端派生逻辑

**Step 2: Tune density**

- 使用较小字号与更紧凑行距
- 保证窄宽度下不出现明显截断

**Step 3: Verify**

Run:

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -derivedDataPath /tmp/fluxdeck-native-derived-kpi-cached -quiet
```

Expected: PASS

### Task 3: 同步契约与进度文档，做最终验证

**Files:**
- Modify: `docs/contracts/admin-api-v1.md`
- Modify: `docs/progress/2026-03-11-native-traffic-monitor.md`
- Optional Modify: `apps/desktop-macos-native/README.md`

**Step 1: Update docs**

- 更新 Stats API 契约中的 `cached_tokens`
- 记录 Traffic KPI 现已改为消费后端稳定 token 结构字段

**Step 2: Run final verification**

Run:

```bash
cargo test -q --test admin_api_test
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -derivedDataPath /tmp/fluxdeck-native-derived-kpi-full -quiet
```

Expected: PASS

**Step 3: Review workspace state**

Run: `git status --short`

Expected: 仅包含本次相关文件变更
