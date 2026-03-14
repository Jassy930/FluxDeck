# Traffic Trend Continuity Fix Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 修复 `/admin/stats/trend` 未补齐空时间桶的问题，保证 `Traffic` 趋势图横向时间轴连续，`1h / 6h / 24h` 在无请求时段也保留 0 值 bucket。

**Architecture:** 保持现有 Admin Stats API 契约不变，只在 `fluxd` 的 trend 聚合层补齐从起始时间到当前时间的连续 bucket。先写后端失败测试证明空桶缺失，再以最小实现生成完整时间桶并回填已有聚合值，最后回归相关 Rust/原生测试并同步进度文档。

**Tech Stack:** Rust, sqlx, axum, tokio, cargo test, XCTest

---

### Task 1: 固化连续时间桶的期望行为

**Files:**
- Modify: `crates/fluxd/tests/admin_api_test.rs`

**Step 1: Write the failing test**

新增一个 `GET /admin/stats/trend` 集成测试，构造两个相隔多个 bucket 的请求日志，断言返回：

- `data` 数组长度覆盖中间空档
- 中间空桶的 `request_count / error_count / input_tokens / output_tokens / cached_tokens` 都为 `0`
- 中间空桶的 `by_model` 为空数组

**Step 2: Run test to verify it fails**

Run: `cargo test -q -p fluxd admin_stats_trend_returns_continuous_buckets_with_zero_value_gaps`

Expected: FAIL，当前实现只返回有日志的 bucket，长度不足或不存在中间 0 值 bucket。

### Task 2: 在 trend 聚合层补齐空桶

**Files:**
- Modify: `crates/fluxd/src/http/admin_routes.rs`

**Step 1: Write minimal implementation**

在 `get_stats_trend` 中：

- 继续复用现有 SQL 聚合查询拿到非空 bucket 数据
- 新增连续 bucket 生成逻辑，从对齐后的起始 bucket 迭代到结束 bucket
- 用 map 回填已有聚合值；无数据的 bucket 返回全 0 字段与空 `by_model`

只修正时间轴连续性，不改返回字段名，不改 overview 接口，不改模型聚合排序。

**Step 2: Run test to verify it passes**

Run: `cargo test -q -p fluxd admin_stats_trend_returns_continuous_buckets_with_zero_value_gaps`

Expected: PASS

### Task 3: 回归验证与文档同步

**Files:**
- Modify: `docs/progress/2026-03-14-traffic-trend-continuity-fix.md`

**Step 1: Run focused regression tests**

Run: `cargo test -q -p fluxd admin_stats_trend`

Expected: PASS

Run: `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTrafficMonitorBuildsTokenTrendSeriesAndSummary -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTrafficMonitorGroupsTailModelsIntoOtherForTokenTrend -quiet`

Expected: PASS

**Step 2: Record progress**

记录根因、实现位置、验证命令和结果，说明本轮修复的是后端 trend 时间轴连续性，原生端图表逻辑无需新增插值补洞。

**Step 3: Check git status**

Run: `git status --short`

Expected: 包含本次计划文档、后端代码/测试与进度文档改动；保留用户现有未提交改动。
