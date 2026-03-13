# Native Shell Header Merge Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将原生桌面端壳层顶栏与内容区 admin 信息栏合并为单层结构，释放首屏垂直空间。

**Architecture:** 新增一个纯派生的壳层顶栏模型，由 `ContentView` 提供 admin endpoint、最近刷新时间和刷新状态；`AppShellView`/`TopModeBar` 负责渲染统一顶栏；原 `headerBar` 改为仅在异常时显示的错误横幅。数据加载与页面业务模型保持不变。

**Tech Stack:** SwiftUI、XCTest、xcodebuild。

---

### Task 1: 为顶栏合并补最小失败测试

**Files:**
- Modify: `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`
- Create or Modify: `apps/desktop-macos-native/FluxDeckNative/UI/TopModeBar.swift`

**Step 1: Write the failing test**

新增一个模型测试，验证壳层顶栏在以下场景下输出正确元数据：

- endpoint 行包含 `Admin`
- 有刷新时间时暴露 `Last refresh`
- 刷新中状态返回 `Refreshing`

**Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testShellToolbarModelBuildsEndpointAndRefreshMetadata -quiet
```

Expected: FAIL，提示模型或字段不存在。

**Step 3: Write minimal implementation**

- 在 `TopModeBar.swift` 中引入最小纯派生模型
- 仅实现满足测试的字段与构造逻辑

**Step 4: Run test to verify it passes**

Run:

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testShellToolbarModelBuildsEndpointAndRefreshMetadata -quiet
```

Expected: PASS

### Task 2: 将壳层元数据接入顶栏

**Files:**
- Modify: `apps/desktop-macos-native/FluxDeckNative/UI/AppShellView.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative/UI/TopModeBar.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift`

**Step 1: Extend shell inputs**

- 为 `AppShellView` 增加顶栏模型或必要字段
- 让 `ContentView` 基于当前 `client.displayBaseURL`、`lastRefreshedAt`、`isLoading/isSubmitting` 构造壳层顶栏数据

**Step 2: Render merged top bar**

- 在 `TopModeBar` 中增加 endpoint、副文本、最近刷新时间和刷新按钮
- 保持模式切换与状态 pill 的原有视觉语义

**Step 3: Verify**

Run:

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testShellToolbarModelBuildsEndpointAndRefreshMetadata -quiet
```

Expected: PASS

### Task 3: 移除重复 header，并保留错误横幅

**Files:**
- Modify: `apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift`

**Step 1: Remove normal header row**

- 移除 `headerBar` 在常态下的渲染
- 删除重复的 `ConnectionBadge` 和 `Refresh` 入口

**Step 2: Preserve failure feedback**

- 将现有 `loadError` 呈现改为轻量错误横幅
- 保留 `Retry` 行为，继续调用 `refreshAll()`

**Step 3: Verify**

Run:

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet
```

Expected: PASS

### Task 4: 更新进度文档并整理工作区

**Files:**
- Create: `docs/progress/2026-03-12-native-shell-header-merge.md`

**Step 1: Update docs**

- 记录本次顶栏合并的动机、涉及文件和验证命令

**Step 2: Check workspace**

Run:

```bash
git status --short
```

Expected: 仅包含本次新增/修改文档与原生端代码文件，以及用户已有未跟踪文档。
