# Native Traffic Input Display Fix Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将原生桌面端 `Traffic` 页 `Total Tokens` KPI 中的 `Input` 展示值改为排除 `cached_tokens` 后的净输入 token。

**Architecture:** 保持后端 Stats API 契约与原生端解码模型不变，只在 `TrafficAnalyticsModel` 的 KPI 派生层调整展示口径。通过先写失败测试，再以最小实现修正 `kpiStripItems` 的 `Input` 行，最后同步更新计划/进度文档，避免影响趋势图、日志页和其他统计视图。

**Tech Stack:** Swift, XCTest, xcodebuild

---

### Task 1: 固化 Traffic KPI 的新展示口径

**Files:**
- Modify: `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`

**Step 1: Write the failing test**

在现有 `testTrafficMonitorModelExposesKpiSupplementRows` 基础上，将 `Input` 期望值从包含缓存命中的原始输入改为净输入值：

```swift
XCTAssertEqual(
    model.kpiStripItems[3].detailRows,
    [
        TrafficKpiSupplementRow(label: "Input", value: "1,300"),
        TrafficKpiSupplementRow(label: "Output", value: "3,300"),
        TrafficKpiSupplementRow(label: "Cached", value: "900")
    ]
)
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTrafficMonitorModelExposesKpiSupplementRows -quiet`

Expected: FAIL，断言显示当前 `Input` 仍为 `2,200`，证明测试覆盖到了旧行为。

### Task 2: 以最小实现修正 KPI 派生值

**Files:**
- Modify: `apps/desktop-macos-native/FluxDeckNative/Features/TrafficConnectionsModels.swift`

**Step 1: Write minimal implementation**

在 `TrafficAnalyticsModel` 的 `kpiStripItems` 中，`Total Tokens` 的 `Input` 行改为：

```swift
TrafficKpiSupplementRow(
    label: L10n.string("traffic.kpi.input", locale: locale),
    value: formatInteger(max(totalInputTokens - totalCachedTokens, 0))
)
```

仅修改该展示值，不新增 API 字段，不改趋势 bucket，不影响 `totalInputTokens` 原始累计值。

**Step 2: Run test to verify it passes**

Run: `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTrafficMonitorModelExposesKpiSupplementRows -quiet`

Expected: PASS

### Task 3: 回归验证与文档同步

**Files:**
- Modify: `docs/progress/2026-03-14-native-traffic-input-display-fix.md`

**Step 1: Run focused regression tests**

Run: `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTrafficMonitorModelExposesKpiSupplementRows -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTrafficMonitorModelExposesKpiStripItems -quiet`

Expected: PASS

**Step 2: Record progress**

记录变更范围、测试命令和结果，明确本次仅调整原生端 `Traffic` 页 KPI 展示口径，不修改后端契约。

**Step 3: Check git status**

Run: `git status --short`

Expected: 仅包含本次计划文档、进度文档和原生端代码/测试改动。
