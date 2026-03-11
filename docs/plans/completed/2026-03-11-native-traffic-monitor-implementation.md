# Native Traffic Monitor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为 `apps/desktop-macos-native` 的 `Traffic` 页面接入真实统计监控数据，并以现有原生工作台风格展示关键指标、趋势与维度分布。

**Architecture:** 在 `AdminApiClient` 中新增 Stats API 解码与请求方法，在 `ContentView` 中增加 `Traffic` 统计状态与按页面加载逻辑，再通过新的派生模型驱动 `TrafficAnalyticsView` 渲染。测试先覆盖统计解码与派生模型，再写最小实现使其通过。

**Tech Stack:** SwiftUI、Foundation、URLSession、XCTest、xcodebuild。

---

### Task 1: 为原生 Stats API 写失败测试

**Files:**
- Modify: `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative/Networking/AdminApiClient.swift`

**Step 1: Write the failing test**

在 `FluxDeckNativeTests.swift` 增加两个测试：

- `testAdminStatsOverviewDecodingUsesAdminContract`
- `testAdminStatsTrendDecodingUsesAdminContract`

断言内容：

- overview 能解码 `total_requests`、`success_rate`、`by_gateway`、`by_provider`、`by_model`
- trend 能解码 `period`、`interval`、`data[*].avg_latency`

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`
Expected: FAIL，因原生端尚未定义 stats 模型与解码方法。

**Step 3: Write minimal implementation**

- 在 `AdminApiClient.swift` 新增 stats 解码结构
- 新增 `decodeStatsOverview(from:)` 与 `decodeStatsTrend(from:)`

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/desktop-macos-native/FluxDeckNative/Networking/AdminApiClient.swift apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift
git commit -m "feat(native): add stats api decoding"
```

### Task 2: 为 Traffic 派生模型写失败测试

**Files:**
- Modify: `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative/Features/TrafficConnectionsModels.swift`

**Step 1: Write the failing test**

新增测试：

- `testTrafficMonitorModelBuildsKpisAlertsAndBreakdowns`

断言内容：

- 能计算 `requestsPerMinuteText`
- 能生成 `successRateText`
- 高错误率或高延迟时会生成 warning / error 级别摘要
- 能识别 top gateway / top provider / top model

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`
Expected: FAIL，因现有 `TrafficAnalyticsModel` 只支持日志本地聚合。

**Step 3: Write minimal implementation**

- 扩展 `TrafficConnectionsModels.swift`
- 定义 stats 驱动的 `TrafficAnalyticsModel.make(overview:trend:period:)`
- 保留原 `make(logs:)` 仅用于兼容或回退

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/desktop-macos-native/FluxDeckNative/Features/TrafficConnectionsModels.swift apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift
git commit -m "feat(native): derive traffic monitor view model from stats"
```

### Task 3: 在客户端接入 Stats API 请求

**Files:**
- Modify: `apps/desktop-macos-native/FluxDeckNative/Networking/AdminApiClient.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift`

**Step 1: Write the failing test**

用现有解码与模型测试作为保护，先不额外写 UI 测试，直接依赖编译与单元测试失败提示推进。

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`
Expected: 现有测试仍不能覆盖 `ContentView` 新状态，编译阶段会提示缺少对应接线。

**Step 3: Write minimal implementation**

- 新增：
  - `fetchStatsOverview(period:)`
  - `fetchStatsTrend(period:interval:)`
- 在 `ContentView` 中新增：
  - `selectedTrafficPeriod`
  - `trafficOverview`
  - `trafficTrend`
  - `trafficLoading`
  - `trafficError`
- 当 `selectedSection == .traffic` 时触发加载

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/desktop-macos-native/FluxDeckNative/Networking/AdminApiClient.swift apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift
git commit -m "feat(native): load traffic stats in content view"
```

### Task 4: 重写 TrafficAnalyticsView 为监控工作台

**Files:**
- Modify: `apps/desktop-macos-native/FluxDeckNative/Features/TrafficAnalyticsView.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative/Features/TrafficConnectionsModels.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift`

**Step 1: Write the failing test**

依赖前述模型测试先锁定行为，不额外补截图测试。

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`
Expected: 视图层改造后编译期会暴露参数不匹配或缺失状态。

**Step 3: Write minimal implementation**

- 增加顶部时间范围切换与刷新入口
- 渲染 KPI 卡片
- 渲染趋势摘要与简易图形
- 渲染 gateway/provider/model breakdown
- 渲染 alerts / empty / error 状态

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/desktop-macos-native/FluxDeckNative/Features/TrafficAnalyticsView.swift apps/desktop-macos-native/FluxDeckNative/Features/TrafficConnectionsModels.swift apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift
git commit -m "feat(native): turn traffic page into stats monitor"
```

### Task 5: 同步文档与验证

**Files:**
- Modify: `apps/desktop-macos-native/README.md`
- Create or Modify: `docs/progress/2026-03-11-native-traffic-monitor.md`

**Step 1: Update docs**

- 在 README 记录 `Traffic` 页面已接入真实 stats 监控
- 在 progress 记录本次实现范围、验证命令与结果

**Step 2: Run verification**

Run:

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet
```

Expected: PASS

**Step 3: Check workspace**

Run:

```bash
git status --short
```

Expected: 只包含本次相关文件改动。

**Step 4: Commit**

```bash
git add apps/desktop-macos-native/README.md docs/progress/2026-03-11-native-traffic-monitor.md
git commit -m "docs(native): record traffic monitor integration"
```
