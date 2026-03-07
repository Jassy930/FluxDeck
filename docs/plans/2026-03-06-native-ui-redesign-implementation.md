# FluxDeck macOS Native 原生界面重设计 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将 `apps/desktop-macos-native` 重构为强对齐参考图风格的深色原生工作台，统一 `Overview / Topology / Traffic / Connections / Logs / Providers / Gateways / Settings` 的信息架构与视觉体系，同时保留现有 Admin API 数据流与业务能力。

**Architecture:** 继续使用现有 SwiftUI + `AdminApiClient` 数据流，先拆出导航与视觉骨架，再逐页用 TDD 补齐衍生 view model、工作台页面和画布组件。优先把可测试逻辑沉淀为纯 Swift 类型与帮助函数，再让 `ContentView` 负责状态持有和页面编排。

**Tech Stack:** SwiftUI、Foundation、XCTest、xcodebuild、macOS 原生应用工程 `apps/desktop-macos-native/FluxDeckNative.xcodeproj`

---

### Task 1: 拆出导航模型与页面分组

**Files:**
- Create: `apps/desktop-macos-native/FluxDeckNative/App/AppNavigation.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative.xcodeproj/project.pbxproj`

**Step 1: Write the failing test**

在 `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift` 新增测试：

```swift
func testNavigationGroupsExposeExpectedSections() {
    let groups = SidebarGroup.defaultGroups

    XCTAssertEqual(groups.map(\.title), ["Overview", "Visualization", "Proxy", "System"])
    XCTAssertTrue(groups[1].items.contains(.topology))
    XCTAssertTrue(groups[2].items.contains(.providers))
    XCTAssertEqual(AppMode.allCases.map(\.rawValue), ["Backup", "Direct", "Rule", "Global"])
}
```

**Step 2: Run test to verify it fails**

Run: `env HOME=/tmp xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -destination 'platform=macOS' -derivedDataPath /tmp/fluxdeck-native-derived -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testNavigationGroupsExposeExpectedSections`
Expected: FAIL，因为 `SidebarGroup`、`AppMode`、新页面枚举尚未定义。

**Step 3: Write minimal implementation**

在 `apps/desktop-macos-native/FluxDeckNative/App/AppNavigation.swift` 定义：

- `enum SidebarSection`
- `struct SidebarGroup`
- `enum AppMode`
- 导航图标、标题、分组与默认顺序

然后在 `apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift` 引用这些类型，移除旧的内联导航枚举。

**Step 4: Run test to verify it passes**

Run: `env HOME=/tmp xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -destination 'platform=macOS' -derivedDataPath /tmp/fluxdeck-native-derived -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testNavigationGroupsExposeExpectedSections`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/desktop-macos-native/FluxDeckNative/App/AppNavigation.swift apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift apps/desktop-macos-native/FluxDeckNative.xcodeproj/project.pbxproj
git commit -m "feat(desktop-native): add grouped navigation model"
```

### Task 2: 建立深色视觉 token 与通用表面组件

**Files:**
- Create: `apps/desktop-macos-native/FluxDeckNative/UI/DesignTokens.swift`
- Create: `apps/desktop-macos-native/FluxDeckNative/UI/SurfaceCard.swift`
- Create: `apps/desktop-macos-native/FluxDeckNative/UI/StatusPill.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative.xcodeproj/project.pbxproj`

**Step 1: Write the failing test**

新增测试验证视觉 token 可被纯逻辑读取：

```swift
func testDesignTokensExposeDarkWorkbenchPalette() {
    XCTAssertEqual(DesignTokens.cornerRadius.window, 26)
    XCTAssertEqual(DesignTokens.cornerRadius.card, 18)
    XCTAssertEqual(DesignTokens.statusColors.running.accessibilityName, "running")
    XCTAssertEqual(DesignTokens.statusColors.error.accessibilityName, "error")
}
```

**Step 2: Run test to verify it fails**

Run: `env HOME=/tmp xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -destination 'platform=macOS' -derivedDataPath /tmp/fluxdeck-native-derived -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testDesignTokensExposeDarkWorkbenchPalette`
Expected: FAIL，因为 `DesignTokens` 尚不存在。

**Step 3: Write minimal implementation**

在 `apps/desktop-macos-native/FluxDeckNative/UI/DesignTokens.swift` 定义统一 token：

- 背景色、边框色、文本色、强调色
- 圆角体系
- 间距体系
- 状态色语义包装

同时新建 `SurfaceCard` 和 `StatusPill` 作为通用卡片与状态胶囊组件，先提供最小可用实现。

**Step 4: Run test to verify it passes**

Run: `env HOME=/tmp xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -destination 'platform=macOS' -derivedDataPath /tmp/fluxdeck-native-derived -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testDesignTokensExposeDarkWorkbenchPalette`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/desktop-macos-native/FluxDeckNative/UI/DesignTokens.swift apps/desktop-macos-native/FluxDeckNative/UI/SurfaceCard.swift apps/desktop-macos-native/FluxDeckNative/UI/StatusPill.swift apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift apps/desktop-macos-native/FluxDeckNative.xcodeproj/project.pbxproj
git commit -m "feat(desktop-native): add dark workbench design tokens"
```

### Task 3: 搭建统一应用壳与顶部模式条

**Files:**
- Create: `apps/desktop-macos-native/FluxDeckNative/UI/AppShellView.swift`
- Create: `apps/desktop-macos-native/FluxDeckNative/UI/SidebarView.swift`
- Create: `apps/desktop-macos-native/FluxDeckNative/UI/TopModeBar.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative.xcodeproj/project.pbxproj`

**Step 1: Write the failing test**

新增纯逻辑测试，验证顶部状态摘要文案：

```swift
func testShellStatusSummaryUsesGatewayAndErrorCounts() {
    let summary = ShellStatusSummary.make(
        isLoading: false,
        loadError: "gateway timeout",
        gateways: [
            AdminGateway(id: "gw", name: "GW", listenHost: "127.0.0.1", listenPort: 18080, inboundProtocol: "openai", defaultProviderId: "pv", enabled: true, runtimeStatus: "running", lastError: nil)
        ]
    )

    XCTAssertEqual(summary.connectionLabel, "Connected")
    XCTAssertEqual(summary.errorLabel, "1 alert")
}
```

**Step 2: Run test to verify it fails**

Run: `env HOME=/tmp xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -destination 'platform=macOS' -derivedDataPath /tmp/fluxdeck-native-derived -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testShellStatusSummaryUsesGatewayAndErrorCounts`
Expected: FAIL，因为 `ShellStatusSummary` 尚不存在。

**Step 3: Write minimal implementation**

- 在 `AppShellView.swift` 附近引入 `ShellStatusSummary`
- 新建统一外壳布局：大圆角容器、左侧分组导航、顶部模式条、主内容插槽
- 在 `ContentView.swift` 中保留数据刷新与 sheet 管理，但将页面组织交给新壳层

**Step 4: Run test to verify it passes**

Run: `env HOME=/tmp xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -destination 'platform=macOS' -derivedDataPath /tmp/fluxdeck-native-derived -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testShellStatusSummaryUsesGatewayAndErrorCounts`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/desktop-macos-native/FluxDeckNative/UI/AppShellView.swift apps/desktop-macos-native/FluxDeckNative/UI/SidebarView.swift apps/desktop-macos-native/FluxDeckNative/UI/TopModeBar.swift apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift apps/desktop-macos-native/FluxDeckNative.xcodeproj/project.pbxproj
git commit -m "feat(desktop-native): scaffold unified app shell"
```

### Task 4: 重写 Overview 的监控首页模型与布局

**Files:**
- Create: `apps/desktop-macos-native/FluxDeckNative/Features/OverviewDashboardView.swift`
- Create: `apps/desktop-macos-native/FluxDeckNative/Features/OverviewModels.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative.xcodeproj/project.pbxproj`

**Step 1: Write the failing test**

新增测试，验证首页统计模型能从 `providers / gateways / logs` 派生：

```swift
func testOverviewDashboardModelBuildsRunningAndTrafficCards() {
    let model = OverviewDashboardModel.make(
        providers: [AdminProvider(id: "pv", name: "Provider", kind: "openai", baseURL: "https://api.openai.com/v1", apiKey: "sk", models: ["gpt-4o-mini"], enabled: true)],
        gateways: [AdminGateway(id: "gw", name: "Gateway", listenHost: "127.0.0.1", listenPort: 18080, inboundProtocol: "openai", defaultProviderId: "pv", enabled: true, runtimeStatus: "running", lastError: nil)],
        logs: [AdminLog(requestID: "req_1", gatewayID: "gw", providerID: "pv", model: "gpt-4o-mini", statusCode: 200, latencyMs: 120, error: nil, createdAt: "2026-03-06T10:00:00Z")]
    )

    XCTAssertEqual(model.runningStatus.connectionCountText, "1")
    XCTAssertEqual(model.networkStatus.internetLatencyText, "120 ms")
    XCTAssertEqual(model.trafficSummary.totalRequestsText, "1")
}
```

**Step 2: Run test to verify it fails**

Run: `env HOME=/tmp xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -destination 'platform=macOS' -derivedDataPath /tmp/fluxdeck-native-derived -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testOverviewDashboardModelBuildsRunningAndTrafficCards`
Expected: FAIL，因为 `OverviewDashboardModel` 尚不存在。

**Step 3: Write minimal implementation**

- 在 `OverviewModels.swift` 中实现首页所需的纯数据模型
- 在 `OverviewDashboardView.swift` 中实现卡片化监控首页
- 用 `SurfaceCard`、`StatusPill`、统一指标块替代旧 `OverviewView`

**Step 4: Run test to verify it passes**

Run: `env HOME=/tmp xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -destination 'platform=macOS' -derivedDataPath /tmp/fluxdeck-native-derived -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testOverviewDashboardModelBuildsRunningAndTrafficCards`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/desktop-macos-native/FluxDeckNative/Features/OverviewDashboardView.swift apps/desktop-macos-native/FluxDeckNative/Features/OverviewModels.swift apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift apps/desktop-macos-native/FluxDeckNative.xcodeproj/project.pbxproj
git commit -m "feat(desktop-native): redesign overview dashboard"
```

### Task 5: 构建 Topology 关系模型与画布骨架

**Files:**
- Create: `apps/desktop-macos-native/FluxDeckNative/Features/TopologyCanvasView.swift`
- Create: `apps/desktop-macos-native/FluxDeckNative/Features/TopologyModels.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative.xcodeproj/project.pbxproj`

**Step 1: Write the failing test**

新增测试，验证拓扑模型能将日志聚合为节点与边：

```swift
func testTopologyGraphBuildsGatewayProviderEdgesFromLogs() {
    let graph = TopologyGraph.make(
        gateways: [AdminGateway(id: "gw", name: "Gateway", listenHost: "127.0.0.1", listenPort: 18080, inboundProtocol: "openai", defaultProviderId: "pv", enabled: true, runtimeStatus: "running", lastError: nil)],
        providers: [AdminProvider(id: "pv", name: "Provider", kind: "openai", baseURL: "https://api.openai.com/v1", apiKey: "sk", models: ["gpt-4o-mini"], enabled: true)],
        logs: [
            AdminLog(requestID: "req_1", gatewayID: "gw", providerID: "pv", model: "gpt-4o-mini", statusCode: 200, latencyMs: 120, error: nil, createdAt: "2026-03-06T10:00:00Z"),
            AdminLog(requestID: "req_2", gatewayID: "gw", providerID: "pv", model: "gpt-4o-mini", statusCode: 502, latencyMs: 800, error: "bad gateway", createdAt: "2026-03-06T10:01:00Z")
        ]
    )

    XCTAssertEqual(graph.columns.count, 3)
    XCTAssertEqual(graph.edges.count, 2)
    XCTAssertEqual(graph.edges.first?.requestCount, 2)
}
```

**Step 2: Run test to verify it fails**

Run: `env HOME=/tmp xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -destination 'platform=macOS' -derivedDataPath /tmp/fluxdeck-native-derived -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTopologyGraphBuildsGatewayProviderEdgesFromLogs`
Expected: FAIL，因为 `TopologyGraph` 尚不存在。

**Step 3: Write minimal implementation**

- 在 `TopologyModels.swift` 中实现节点、边、列与聚合逻辑
- 在 `TopologyCanvasView.swift` 中用 `Canvas`、`Path` 和自定义节点卡片实现三列或四列画布
- 在 `ContentView.swift` 中接入独立 `Topology` 页面

**Step 4: Run test to verify it passes**

Run: `env HOME=/tmp xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -destination 'platform=macOS' -derivedDataPath /tmp/fluxdeck-native-derived -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTopologyGraphBuildsGatewayProviderEdgesFromLogs`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/desktop-macos-native/FluxDeckNative/Features/TopologyCanvasView.swift apps/desktop-macos-native/FluxDeckNative/Features/TopologyModels.swift apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift apps/desktop-macos-native/FluxDeckNative.xcodeproj/project.pbxproj
git commit -m "feat(desktop-native): add topology workbench"
```

### Task 6: 增加 Traffic 与 Connections 页面模型

**Files:**
- Create: `apps/desktop-macos-native/FluxDeckNative/Features/TrafficAnalyticsView.swift`
- Create: `apps/desktop-macos-native/FluxDeckNative/Features/ConnectionsView.swift`
- Create: `apps/desktop-macos-native/FluxDeckNative/Features/TrafficConnectionsModels.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative.xcodeproj/project.pbxproj`

**Step 1: Write the failing test**

新增测试验证流量与连接统计聚合：

```swift
func testTrafficAndConnectionsModelsAggregateLogs() {
    let logs = [
        AdminLog(requestID: "req_ok", gatewayID: "gw_a", providerID: "pv_a", model: "gpt-4o-mini", statusCode: 200, latencyMs: 100, error: nil, createdAt: "2026-03-06T10:00:00Z"),
        AdminLog(requestID: "req_err", gatewayID: "gw_b", providerID: "pv_b", model: "claude-3-7-sonnet", statusCode: 500, latencyMs: 900, error: "timeout", createdAt: "2026-03-06T10:01:00Z")
    ]

    let traffic = TrafficAnalyticsModel.make(logs: logs)
    let connections = ConnectionsModel.make(logs: logs)

    XCTAssertEqual(traffic.totalRequests, 2)
    XCTAssertEqual(traffic.errorCount, 1)
    XCTAssertEqual(connections.activeGatewayIDs.sorted(), ["gw_a", "gw_b"])
}
```

**Step 2: Run test to verify it fails**

Run: `env HOME=/tmp xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -destination 'platform=macOS' -derivedDataPath /tmp/fluxdeck-native-derived -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTrafficAndConnectionsModelsAggregateLogs`
Expected: FAIL，因为 `TrafficAnalyticsModel` 与 `ConnectionsModel` 尚不存在。

**Step 3: Write minimal implementation**

- 新建 `TrafficConnectionsModels.swift` 实现纯数据聚合
- 新建 `TrafficAnalyticsView.swift` 和 `ConnectionsView.swift`
- 在新页面中复用统一卡片体系展示趋势和连接摘要

**Step 4: Run test to verify it passes**

Run: `env HOME=/tmp xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -destination 'platform=macOS' -derivedDataPath /tmp/fluxdeck-native-derived -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTrafficAndConnectionsModelsAggregateLogs`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/desktop-macos-native/FluxDeckNative/Features/TrafficAnalyticsView.swift apps/desktop-macos-native/FluxDeckNative/Features/ConnectionsView.swift apps/desktop-macos-native/FluxDeckNative/Features/TrafficConnectionsModels.swift apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift apps/desktop-macos-native/FluxDeckNative.xcodeproj/project.pbxproj
git commit -m "feat(desktop-native): add traffic and connections pages"
```

### Task 7: 把 Providers 与 Gateways 改成工作台页面

**Files:**
- Modify: `apps/desktop-macos-native/FluxDeckNative/Features/ProviderListView.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative/Features/GatewayListView.swift`
- Create: `apps/desktop-macos-native/FluxDeckNative/Features/ResourceWorkspaceModels.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative.xcodeproj/project.pbxproj`

**Step 1: Write the failing test**

新增测试验证资源页面详情模型：

```swift
func testResourceWorkspaceModelsExposePrimaryAndSecondaryMetadata() {
    let providerCard = ProviderWorkspaceCard.make(
        provider: AdminProvider(id: "pv", name: "Provider", kind: "openai", baseURL: "https://api.openai.com/v1", apiKey: "sk", models: ["gpt-4o-mini", "gpt-4.1-mini"], enabled: true)
    )
    let gatewayCard = GatewayWorkspaceCard.make(
        gateway: AdminGateway(id: "gw", name: "Gateway", listenHost: "127.0.0.1", listenPort: 18080, inboundProtocol: "openai", defaultProviderId: "pv", enabled: true, runtimeStatus: "running", lastError: nil)
    )

    XCTAssertEqual(providerCard.modelCountText, "2 models")
    XCTAssertEqual(gatewayCard.endpointText, "127.0.0.1:18080")
    XCTAssertEqual(gatewayCard.runtimeBadge, "RUNNING")
}
```

**Step 2: Run test to verify it fails**

Run: `env HOME=/tmp xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -destination 'platform=macOS' -derivedDataPath /tmp/fluxdeck-native-derived -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testResourceWorkspaceModelsExposePrimaryAndSecondaryMetadata`
Expected: FAIL，因为 `ProviderWorkspaceCard` 与 `GatewayWorkspaceCard` 尚不存在。

**Step 3: Write minimal implementation**

- 在 `ResourceWorkspaceModels.swift` 中实现 Provider / Gateway 卡片模型
- 改造 `ProviderListView.swift` 与 `GatewayListView.swift`，从系统 `List` 主导改为工作台布局
- 保留创建、编辑、启动、停止等原有操作入口

**Step 4: Run test to verify it passes**

Run: `env HOME=/tmp xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -destination 'platform=macOS' -derivedDataPath /tmp/fluxdeck-native-derived -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testResourceWorkspaceModelsExposePrimaryAndSecondaryMetadata`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/desktop-macos-native/FluxDeckNative/Features/ProviderListView.swift apps/desktop-macos-native/FluxDeckNative/Features/GatewayListView.swift apps/desktop-macos-native/FluxDeckNative/Features/ResourceWorkspaceModels.swift apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift apps/desktop-macos-native/FluxDeckNative.xcodeproj/project.pbxproj
git commit -m "feat(desktop-native): restyle providers and gateways workspaces"
```

### Task 8: 重构 Logs 与 Settings 工作台

**Files:**
- Create: `apps/desktop-macos-native/FluxDeckNative/Features/LogsWorkbenchView.swift`
- Create: `apps/desktop-macos-native/FluxDeckNative/Features/SettingsPanelView.swift`
- Create: `apps/desktop-macos-native/FluxDeckNative/Features/SettingsModels.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative.xcodeproj/project.pbxproj`

**Step 1: Write the failing test**

新增测试验证日志详情与设置卡片模型：

```swift
func testLogsAndSettingsWorkbenchModelsBuildDetailCards() {
    let logCard = LogDetailCardModel.make(
        log: AdminLog(requestID: "req_1", gatewayID: "gw", providerID: "pv", model: "gpt-4o-mini", statusCode: 502, latencyMs: 800, error: "timeout", createdAt: "2026-03-06T10:00:00Z")
    )
    let settings = SettingsPanelModel.make(adminBaseURL: "http://127.0.0.1:7777", isLoading: false, hasError: false)

    XCTAssertEqual(logCard.statusText, "502")
    XCTAssertEqual(logCard.errorText, "timeout")
    XCTAssertEqual(settings.sections.map(\.title), ["Admin API", "Refresh & Sync", "Diagnostics"])
}
```

**Step 2: Run test to verify it fails**

Run: `env HOME=/tmp xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -destination 'platform=macOS' -derivedDataPath /tmp/fluxdeck-native-derived -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testLogsAndSettingsWorkbenchModelsBuildDetailCards`
Expected: FAIL，因为 `LogDetailCardModel` 与 `SettingsPanelModel` 尚不存在。

**Step 3: Write minimal implementation**

- 在 `LogsWorkbenchView.swift` 中实现分析型日志工作台
- 在 `SettingsModels.swift` 与 `SettingsPanelView.swift` 中实现三段式设置面板
- 将旧的日志页和设置页迁移到新工作台风格

**Step 4: Run test to verify it passes**

Run: `env HOME=/tmp xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -destination 'platform=macOS' -derivedDataPath /tmp/fluxdeck-native-derived -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testLogsAndSettingsWorkbenchModelsBuildDetailCards`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/desktop-macos-native/FluxDeckNative/Features/LogsWorkbenchView.swift apps/desktop-macos-native/FluxDeckNative/Features/SettingsPanelView.swift apps/desktop-macos-native/FluxDeckNative/Features/SettingsModels.swift apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift apps/desktop-macos-native/FluxDeckNative.xcodeproj/project.pbxproj
git commit -m "feat(desktop-native): redesign logs and settings workspaces"
```

### Task 9: 整体收口、文档同步与全量验收

**Files:**
- Modify: `apps/desktop-macos-native/README.md`
- Modify: `docs/USAGE.md`
- Modify: `docs/plans/2026-03-06-native-ui-redesign-design.md`
- Modify: `docs/plans/2026-03-06-native-ui-redesign-implementation.md`

**Step 1: Write the failing test**

在 `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift` 增加一个最终集成断言，验证 Overview、Topology、Logs 的核心派生函数在组合数据下都能运行：

```swift
func testWorkbenchDerivedModelsStayConsistentForSharedFixture() {
    let providers = [AdminProvider(id: "pv", name: "Provider", kind: "openai", baseURL: "https://api.openai.com/v1", apiKey: "sk", models: ["gpt-4o-mini"], enabled: true)]
    let gateways = [AdminGateway(id: "gw", name: "Gateway", listenHost: "127.0.0.1", listenPort: 18080, inboundProtocol: "openai", defaultProviderId: "pv", enabled: true, runtimeStatus: "running", lastError: nil)]
    let logs = [AdminLog(requestID: "req_1", gatewayID: "gw", providerID: "pv", model: "gpt-4o-mini", statusCode: 200, latencyMs: 120, error: nil, createdAt: "2026-03-06T10:00:00Z")]

    XCTAssertEqual(OverviewDashboardModel.make(providers: providers, gateways: gateways, logs: logs).trafficSummary.totalRequestsText, "1")
    XCTAssertEqual(TopologyGraph.make(gateways: gateways, providers: providers, logs: logs).edges.count, 2)
    XCTAssertEqual(TrafficAnalyticsModel.make(logs: logs).totalRequests, 1)
}
```

**Step 2: Run test to verify it fails**

Run: `env HOME=/tmp xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -destination 'platform=macOS' -derivedDataPath /tmp/fluxdeck-native-derived -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testWorkbenchDerivedModelsStayConsistentForSharedFixture`
Expected: FAIL，直到所有模型完成并且边数量等断言与实现一致。

**Step 3: Write minimal implementation**

- 修正共享 fixture 在各工作台模型中的聚合不一致问题
- 同步更新 `apps/desktop-macos-native/README.md` 与 `docs/USAGE.md`
- 根据最终实现回填设计与计划文档的差异

**Step 4: Run test to verify it passes**

Run: `env HOME=/tmp xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -destination 'platform=macOS' -derivedDataPath /tmp/fluxdeck-native-derived -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testWorkbenchDerivedModelsStayConsistentForSharedFixture`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/desktop-macos-native/README.md docs/USAGE.md docs/plans/2026-03-06-native-ui-redesign-design.md docs/plans/2026-03-06-native-ui-redesign-implementation.md apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift
git commit -m "docs(native): sync redesign docs and verification notes"
```

### Task 10: 运行三段验收并记录结果

**Files:**
- Modify: `docs/USAGE.md`
- Modify: `docs/plans/2026-03-06-native-ui-redesign-implementation.md`

**Step 1: Write the failing test**

这一任务不再新增单元测试，改为先记录验收命令与预期结果，若任何命令失败则作为修复入口。

**Step 2: Run test to verify it fails**

Run: `cargo test -q && (cd apps/desktop && bun run test) && env HOME=/tmp xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -destination 'platform=macOS' -derivedDataPath /tmp/fluxdeck-native-derived && ./scripts/e2e/smoke.sh`
Expected: 在完成全部实现前，其中至少一段失败，暴露剩余问题。

**Step 3: Write minimal implementation**

- 修复三段验收暴露的最后问题
- 将实际命令与结果补充到 `docs/USAGE.md` 和本计划文档末尾

**Step 4: Run test to verify it passes**

Run: `cargo test -q && (cd apps/desktop && bun run test) && env HOME=/tmp xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -destination 'platform=macOS' -derivedDataPath /tmp/fluxdeck-native-derived && ./scripts/e2e/smoke.sh`
Expected: PASS

**Step 5: Commit**

```bash
git add docs/USAGE.md docs/plans/2026-03-06-native-ui-redesign-implementation.md
git commit -m "chore(native): record redesign acceptance results"
```

## 2026-03-07 补充：沉浸式壳层收口

- 去掉 `AppShellView` 外层显式描边，避免界面四周出现过强的“套壳边框”。
- 将外层容器改为更弱的渐变与阴影层次，保留工作台深度但减少框感。
- 收窄外边距，并为侧栏与主区之间改成细分隔，而不是整圈包围线。
- `TopModeBar` 的模式切换改为低对比填充胶囊，弱化此前偏按钮化的蓝色描边选中态。
- `ContentView` 头部移除重复的大标题，仅保留 Admin、刷新时间与状态信息。
- `FluxDeckNativeApp` 切换为隐藏原生标题栏样式，进一步贴近参考图的沉浸式控制台观感。
- 继续收口窗口边缘表现：移除 `AppShellView` 内层容器的圆角裁切、阴影和外边距，避免形成一圈额外黑边，直接让工作区贴合窗口内容区域。
