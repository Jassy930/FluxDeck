# Native Traffic 模型 Token 趋势 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将原生端 Traffic 主图改为按模型堆叠的 token 趋势图，补充更高时间密度、图例与 tooltip，并由后端稳定返回 bucket 级模型 token 聚合数据。

**Architecture:** 先扩展 `fluxd` 的 `/admin/stats/trend` 契约，在每个 bucket 中返回按模型拆分的 token 聚合结果；再在原生端解码新结构、派生 Top 4 + `Other` 图表模型，并重写 SwiftUI 图表视图为堆叠面积图。全程保持 TDD，先写失败测试，再写最小实现，再跑主线验证。

**Tech Stack:** Rust、sqlx、SQLite、SwiftUI、XCTest、xcodebuild、Markdown

---

### Task 1: 锁定后端 trend 契约与聚合语义

**Files:**
- Modify: `crates/fluxd/tests/admin_api_test.rs`
- Modify: `docs/contracts/admin-api-v1.md`
- Modify: `docs/plans/active/2026-03-13-native-traffic-model-token-trend-design.md`

**Step 1: 写失败测试，要求 trend bucket 返回 `by_model`**

在 `crates/fluxd/tests/admin_api_test.rs` 新增测试，构造至少两个模型、同一 bucket 的日志数据，并断言：

- `data[0].by_model` 存在
- 每个元素包含 `model / total_tokens / input_tokens / output_tokens / cached_tokens / request_count / error_count`
- `NULL` 模型被归一为稳定占位值

**Step 2: 运行测试，确认因缺少字段失败**

Run:

```bash
cargo test -q admin_stats_trend_includes_bucket_model_token_breakdown --test admin_api_test
```

Expected: FAIL，错误应来自响应中缺少 `by_model` 或断言不成立。

**Step 3: 同步更新契约文档草案**

在 `docs/contracts/admin-api-v1.md` 补充 `GET /admin/stats/trend` 的 `by_model` 字段定义与聚合语义，避免实现阶段口径漂移。

**Step 4: 提交文档草案**

```bash
git add crates/fluxd/tests/admin_api_test.rs docs/contracts/admin-api-v1.md docs/plans/active/2026-03-13-native-traffic-model-token-trend-design.md
git commit -m "docs(traffic): define model token trend contract"
```

### Task 2: 实现 `fluxd` bucket 级模型 token 聚合

**Files:**
- Modify: `crates/fluxd/src/http/admin_routes.rs`
- Modify: `crates/fluxd/tests/admin_api_test.rs`

**Step 1: 写第二个失败测试，覆盖多 bucket 与 Unknown model**

新增一个测试，验证：

- 不同 bucket 数据不会串桶
- bucket 内 `by_model` 按 `total_tokens DESC, model ASC` 排序
- `model_effective` 优先于 `model`
- 空模型值被归一为 `Unknown model`

**Step 2: 运行测试，确认失败**

Run:

```bash
cargo test -q admin_stats_trend_groups_model_tokens_per_bucket --test admin_api_test
```

Expected: FAIL，错误来自聚合结果缺失或排序不对。

**Step 3: 写最小实现**

在 `crates/fluxd/src/http/admin_routes.rs`：

- 为 trend bucket 响应新增 `by_model` 结构体
- 在现有 bucket 查询之后补一段 bucket + model 聚合查询
- 将每个 bucket 的模型统计挂回对应 trend point
- 统一处理 `model_effective` / `model` / `Unknown model`

**Step 4: 运行定向测试**

Run:

```bash
cargo test -q admin_stats_trend_includes_bucket_model_token_breakdown admin_stats_trend_groups_model_tokens_per_bucket --test admin_api_test
```

Expected: PASS

**Step 5: 回归后端统计相关测试**

Run:

```bash
cargo test -q -p fluxd --test admin_api_test
```

Expected: PASS

**Step 6: 提交**

```bash
git add crates/fluxd/src/http/admin_routes.rs crates/fluxd/tests/admin_api_test.rs docs/contracts/admin-api-v1.md
git commit -m "feat(fluxd): add per-model token trend buckets"
```

### Task 3: 更新原生端解码模型与失败测试

**Files:**
- Modify: `apps/desktop-macos-native/FluxDeckNative/Networking/AdminApiClient.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`

**Step 1: 写失败测试，要求原生端可解码新的 `by_model`**

在 `FluxDeckNativeTests.swift` 增加 trend 解码测试，断言：

- `AdminStatsTrendPoint` 能解码 `by_model`
- 模型行包含 token 各子项与请求/错误计数
- 未提供 `by_model` 时解码行为符合契约要求

**Step 2: 运行测试，确认失败**

Run:

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testAdminStatsTrendDecodingIncludesByModelBuckets -derivedDataPath /tmp/fluxdeck-native-derived-tokentrend-red1 -quiet
```

Expected: FAIL，错误来自 `AdminStatsTrendPoint` 缺少 `by_model` 字段模型。

**Step 3: 写最小解码实现**

在 `AdminApiClient.swift` 新增：

- `AdminStatsTrendModelBucket`
- `AdminStatsTrendPoint.byModel`

并保持现有字段兼容。

**Step 4: 运行定向测试**

Run:

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testAdminStatsTrendDecodingIncludesByModelBuckets -derivedDataPath /tmp/fluxdeck-native-derived-tokentrend-green1 -quiet
```

Expected: PASS

**Step 5: 提交**

```bash
git add apps/desktop-macos-native/FluxDeckNative/Networking/AdminApiClient.swift apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift
git commit -m "feat(native): decode model token trend buckets"
```

### Task 4: 派生图表模型与 token 摘要

**Files:**
- Modify: `apps/desktop-macos-native/FluxDeckNative/Features/TrafficConnectionsModels.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`

**Step 1: 写失败测试，锁定 Top 4 + Other 与摘要口径**

新增测试覆盖：

- period 总 token 前 4 模型保留，剩余合并为 `Other`
- 缺失 bucket 的模型值补 `0`
- 图下摘要变为 `Peak Total Tokens` / `Top Model Share` / `Peak Bucket Errors`
- tooltip 行按当前 bucket token 降序

**Step 2: 运行测试，确认失败**

Run:

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative \
  -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTrafficMonitorBuildsTokenTrendSeriesAndSummary \
  -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTrafficMonitorGroupsTailModelsIntoOther \
  -derivedDataPath /tmp/fluxdeck-native-derived-tokentrend-red2 -quiet
```

Expected: FAIL，错误来自模型结构或摘要字段尚未存在。

**Step 3: 写最小实现**

在 `TrafficConnectionsModels.swift`：

- 新增 token 趋势序列、tooltip、摘要结构
- 将 `TrafficAnalyticsModel` 从旧 `trendPoints` 派生改为同时暴露新 token 图表模型
- 保留现有 KPI、breakdown、alerts 逻辑

**Step 4: 运行定向测试**

Run:

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative \
  -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTrafficMonitorBuildsTokenTrendSeriesAndSummary \
  -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTrafficMonitorGroupsTailModelsIntoOther \
  -derivedDataPath /tmp/fluxdeck-native-derived-tokentrend-green2 -quiet
```

Expected: PASS

**Step 5: 提交**

```bash
git add apps/desktop-macos-native/FluxDeckNative/Features/TrafficConnectionsModels.swift apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift
git commit -m "feat(native): derive token trend chart model"
```

### Task 5: 重写 SwiftUI 主图为堆叠面积图并加入图例与 tooltip

**Files:**
- Modify: `apps/desktop-macos-native/FluxDeckNative/Features/TrafficAnalyticsView.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`

**Step 1: 写失败测试，锁定 period -> interval 映射**

新增测试，要求：

- `1h -> 1m`
- `6h -> 5m`
- `24h -> 15m`

**Step 2: 运行测试，确认失败**

Run:

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTrafficTrendIntervalUsesDenserBuckets -derivedDataPath /tmp/fluxdeck-native-derived-tokentrend-red3 -quiet
```

Expected: FAIL

**Step 3: 写最小实现**

在 `TrafficAnalyticsView.swift`：

- 将旧 `TrafficTrendChart` 改为堆叠面积图绘制
- 添加图例区
- 添加 hover 追踪、bucket 高亮线和 tooltip 容器
- 图下摘要改为 token 语义

在 `ContentView.swift`：

- 更新 `trafficTrendInterval(for:)`

**Step 4: 运行图表相关原生测试**

Run:

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -derivedDataPath /tmp/fluxdeck-native-derived-tokentrend-chart -quiet
```

Expected: PASS

**Step 5: 提交**

```bash
git add apps/desktop-macos-native/FluxDeckNative/Features/TrafficAnalyticsView.swift apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift
git commit -m "feat(native): render stacked model token trend chart"
```

### Task 6: 文档收尾与全量验证

**Files:**
- Modify: `docs/contracts/admin-api-v1.md`
- Modify: `docs/progress/2026-03-13-native-traffic-model-token-trend.md`

**Step 1: 记录实现结果**

在 `docs/progress/2026-03-13-native-traffic-model-token-trend.md` 记录：

- 新增/修改的契约字段
- 原生端图表语义变化
- 验证命令与结果

**Step 2: 跑主线验证**

Run:

```bash
cargo test -q
./scripts/e2e/smoke.sh
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet
```

Expected: 全部 PASS；`smoke.sh` 输出 `smoke ok`

**Step 3: 整理 git 状态并提交**

```bash
git status --short
git add docs/contracts/admin-api-v1.md docs/progress/2026-03-13-native-traffic-model-token-trend.md
git commit -m "docs(traffic): record model token trend rollout"
```

Plan complete and saved to `docs/plans/active/2026-03-13-native-traffic-model-token-trend.md`. Two execution options:

**1. Subagent-Driven (this session)** - I dispatch fresh subagent per task, review between tasks, fast iteration

**2. Parallel Session (separate)** - Open new session with executing-plans, batch execution with checkpoints

Which approach?
