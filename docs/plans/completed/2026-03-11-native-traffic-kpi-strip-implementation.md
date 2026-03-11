# Native Traffic KPI Strip Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将 `apps/desktop-macos-native` 的 `Traffic` 页面 4 个 KPI 改造成一条连续指标栏，以提升首屏信息密度。

**Architecture:** 在 `TrafficAnalyticsModel` 中补充用于指标栏渲染的只读派生数据，在 `TrafficAnalyticsView` 中将现有两行 KPI 卡替换为单张 `SurfaceCard` 包裹的四段式 `metric strip`。保持现有数据流和监控逻辑不变。

**Tech Stack:** SwiftUI、Foundation、XCTest、xcodebuild。

---

### Task 1: 为 KPI strip 派生数据写失败测试

**Files:**
- Modify: `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative/Features/TrafficConnectionsModels.swift`

**Step 1: Write the failing test**

新增测试，断言：

- `TrafficAnalyticsModel` 暴露 4 个 KPI strip item
- 顺序固定为 `Requests / min`、`Success Rate`、`Avg Latency`、`Total Tokens`

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTrafficMonitorModelExposesKpiStripItems -quiet`
Expected: FAIL

**Step 3: Write minimal implementation**

- 在 `TrafficConnectionsModels.swift` 新增最小派生结构与访问器

**Step 4: Run test to verify it passes**

Run 同上
Expected: PASS

### Task 2: 实现连续指标栏布局

**Files:**
- Modify: `apps/desktop-macos-native/FluxDeckNative/Features/TrafficAnalyticsView.swift`

**Step 1: Replace KPI cards**

- 用单张 `SurfaceCard` 替换现有 `kpiGrid`
- 内部用单排四段式布局
- 使用轻分隔线

**Step 2: Add width fallback**

- 在必要时用 `ViewThatFits` 或等效方式回退为 `2 x 2`

**Step 3: Verify**

Run: `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`
Expected: PASS

### Task 3: 更新文档与验证

**Files:**
- Modify: `apps/desktop-macos-native/README.md`
- Modify or Create: `docs/progress/2026-03-11-native-traffic-density.md`

**Step 1: Update docs**

- 记录 KPI 已改为连续指标栏

**Step 2: Run verification**

Run:

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet
```

Expected: PASS
