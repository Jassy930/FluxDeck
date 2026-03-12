# Native Logs Density Polish Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将原生端 `Logs` 页面收敛为统一的紧凑工具栏 + 两行日志行视图，提升日志扫描密度并保持现有展开诊断能力。

**Architecture:** 保留 `LogsWorkbenchView` 的数据流、筛选逻辑和单条展开状态机，只重构顶栏与日志项的视图结构。优先通过 `LogStreamCardModel` 补齐折叠态和展开态所需的分组文案，避免在 SwiftUI 视图中重复拼接字符串；测试先覆盖格式化和状态行为，再做最小视图调整。

**Tech Stack:** SwiftUI、XCTest、xcodebuild、Markdown

---

### Task 1: 为紧凑折叠态摘要补失败测试

**Files:**
- Modify: `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative/Features/LogsWorkbenchView.swift`

**Step 1: Write the failing test**

新增测试，断言：

- 折叠态模型可直接提供 token 摘要、latency、time
- 失败日志优先展示错误摘要
- 成功日志优先展示模型信息
- 第二行小标签包含协议 / stream 信息

**Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testCompactLogRowSummaryFormatting -derivedDataPath /tmp/fluxdeck-native-derived-logs-density-red -quiet
```

Expected: FAIL，提示缺少新的摘要字段或格式化结果与预期不符

**Step 3: Write minimal implementation**

- 在 `LogStreamCardModel` 中增加紧凑折叠态所需的二级摘要字段
- 保持已有字段兼容，避免破坏当前视图调用

**Step 4: Run test to verify it passes**

Run 同上

Expected: PASS

### Task 2: 重排 Log Filters 为紧凑工具栏

**Files:**
- Modify: `apps/desktop-macos-native/FluxDeckNative/Features/LogsWorkbenchView.swift`
- Optional Modify: `apps/desktop-macos-native/FluxDeckNative/UI/SurfaceCard.swift`

**Step 1: Write the failing test**

如果现有测试框架适合视图模型断言，则增加对过滤区状态文案的测试；否则记录本任务依赖人工验收，不新增脆弱快照测试。

**Step 2: Write minimal implementation**

- 将 `filterBar` 从厚重内容卡改为轻量工具栏布局
- 收紧标题、内边距、控件间距和状态标签样式
- 统一与日志流的描边和背景语义

**Step 3: Verify**

Run:

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -derivedDataPath /tmp/fluxdeck-native-derived-logs-density-toolbar -quiet
```

Expected: PASS

### Task 3: 将日志项从大卡片收敛为两行紧凑行视图

**Files:**
- Modify: `apps/desktop-macos-native/FluxDeckNative/Features/LogsWorkbenchView.swift`

**Step 1: Write the failing test**

新增测试，断言：

- 折叠态模型支持第一行主判断信息和第二行元信息
- 展开态仍然只允许一条日志展开
- 失败日志保留更强语义强调入口

**Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testLogExpansionStateAndCompactRows -derivedDataPath /tmp/fluxdeck-native-derived-logs-density-row-red -quiet
```

Expected: FAIL，提示新的行式摘要或状态行为尚未实现

**Step 3: Write minimal implementation**

- 收紧单条日志内边距、圆角、描边和间距
- 将折叠态改为两行结构
- 第二行加入 token / latency / time / protocol / stream 元信息
- 保留点击整行展开与 `Load More`

**Step 4: Run test to verify it passes**

Run 同上

Expected: PASS

### Task 4: 将展开态改为分组式诊断区

**Files:**
- Modify: `apps/desktop-macos-native/FluxDeckNative/Features/LogsWorkbenchView.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`

**Step 1: Write the failing test**

新增测试，断言：

- 展开态可区分 `Execution` 与 `Diagnostics`
- `usage_json` 为空时不渲染原始明细块
- 长错误文本仍可完整展示

**Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testExpandedDiagnosticsGrouping -derivedDataPath /tmp/fluxdeck-native-derived-logs-density-expand-red -quiet
```

Expected: FAIL，提示分组化展开态尚未实现

**Step 3: Write minimal implementation**

- 将短字段组织为分组块
- 将 `error` 与 `usage_json` 组织为单独长文本区域
- 保持可复制文本能力

**Step 4: Run test to verify it passes**

Run 同上

Expected: PASS

### Task 5: 文档收口与最终验证

**Files:**
- Modify: `docs/progress/2026-03-12-native-logs-density-polish.md`
- Optional Modify: `apps/desktop-macos-native/README.md`

**Step 1: Update docs**

- 记录日志界面密度优化的实现结果
- 如有必要，在原生端 README 中补充新的日志视图说明

**Step 2: Run final verification**

Run:

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -derivedDataPath /tmp/fluxdeck-native-derived-logs-density-full -quiet
git status --short
```

Expected:

- `xcodebuild test` PASS
- `git status --short` 仅包含本次相关文件变更
