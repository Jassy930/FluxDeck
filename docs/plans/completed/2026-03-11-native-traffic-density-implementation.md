# Native Traffic Density Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将 `apps/desktop-macos-native` 的 `Traffic` 页面改造成更高密度的原生监控台布局，让首屏完整展示 KPI 与趋势主区。

**Architecture:** 继续使用现有 `TrafficAnalyticsModel` 和 `TrafficAnalyticsView`，不改动 stats 数据流，只压缩 `TrafficAnalyticsView` 的垂直结构、内边距、KPI 卡高度和 breakdown 行高。必要时新增少量布局辅助组件，但保持 `SurfaceCard` / `StatusPill` 体系不变。

**Tech Stack:** SwiftUI、XCTest、xcodebuild。

---

### Task 1: 为紧凑布局补最小保护测试

**Files:**
- Modify: `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`

**Step 1: Write the failing test**

增加一个最小测试，验证零流量模型仍保留可渲染骨架状态，不会因为布局压缩而退回空白页。

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`
Expected: FAIL 或在现有行为基础上暴露缺失状态字段。

**Step 3: Write minimal implementation**

- 若需要，补充紧凑布局用的状态字段或常量

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`
Expected: PASS

### Task 2: 实现高密度头部与 KPI 区

**Files:**
- Modify: `apps/desktop-macos-native/FluxDeckNative/Features/TrafficAnalyticsView.swift`

**Step 1: Compress header**

- 将标题、时间范围、刷新、更新时间合并进单层短卡
- 压缩顶部内边距与控件间距

**Step 2: Compress KPI cards**

- 降低 KPI 卡高度
- 缩短辅助文案和 pill 占位
- 保留数字主视觉

**Step 3: Verify**

Run: `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`
Expected: PASS

### Task 3: 实现趋势区与 breakdown 的高密度布局

**Files:**
- Modify: `apps/desktop-macos-native/FluxDeckNative/Features/TrafficAnalyticsView.swift`

**Step 1: Move trend into first screen**

- 收紧趋势区的上下内边距
- 缩短右侧摘要卡高度

**Step 2: Compact breakdown**

- 每列仅保留 top 3
- 收紧行距和分隔

**Step 3: Verify**

Run: `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`
Expected: PASS

### Task 4: 更新文档与验证

**Files:**
- Modify: `apps/desktop-macos-native/README.md`
- Create or Modify: `docs/progress/2026-03-11-native-traffic-density.md`

**Step 1: Update docs**

- 说明 `Traffic` 页面现已使用高密度监控布局

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
