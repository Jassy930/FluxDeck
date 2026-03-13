# Native Topology Sankey Polish Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将原生端 `Topology` 页面从“功能正确但画布感不足”的 token flow 视图重构为以流带为主角的 Sankey 主舞台，同时补上最小可读宽度与 hover 诊断交互。

**Architecture:** 保持现有 `TopologyGraph` 客户端聚合模型和三列结构不变，专注重构 `TopologyCanvasView` 的视图比例、流带绘制、节点呈现和 hover 状态。测试先锁定最小宽度、节点弱化与 hover 语义，再做最小 SwiftUI 实现，避免再把诊断数据塞回节点卡片。

**Tech Stack:** SwiftUI、Canvas、XCTest、xcodebuild、Markdown

## 执行状态

- 状态：已完成
- 完成日期：2026-03-13
- 结果摘要：
  - 已补齐 `TopologyCanvasScreenModel` 的轻量节点摘要、hover payload 与 hover state
  - 已抽离 `TopologyBandScale` 与 `TopologyCanvasStageLayout`，锁定最小流带宽度和主舞台比例
  - 已将原生端 `Topology` 画布重构为更接近参考图的三列 Sankey 主舞台
  - 已通过定向测试、完整原生测试、`cargo test -q` 与 `./scripts/e2e/smoke.sh`

---

### Task 1: 锁定 Sankey 主舞台的展示模型

**Files:**
- Modify: `apps/desktop-macos-native/FluxDeckNative/Features/TopologyCanvasView.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`

**Step 1: 写失败测试，要求屏幕模型输出轻量节点与 hover 载荷**

新增测试覆盖：

- 节点卡片摘要降到单行主信息 + 极简次信息
- `TopologyCanvasScreenModel` 可派生 hover 所需链路与节点摘要
- `Hot Paths` 与 `Model Mix` 仍保留，但不依赖重节点卡片

**Step 2: 运行测试，确认失败**

Run:

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative \
  -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTopologyCanvasBuildsLightweightNodeSummaries \
  -derivedDataPath /tmp/fluxdeck-native-derived-sankey-red1 -quiet
```

Expected: FAIL

**Step 3: 写最小实现**

- 在 `TopologyCanvasView.swift` 中整理 screen model、node summary、hover payload 结构
- 不在 View 中堆积聚合逻辑

**Step 4: 运行定向测试**

Run:

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative \
  -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTopologyCanvasBuildsLightweightNodeSummaries \
  -derivedDataPath /tmp/fluxdeck-native-derived-sankey-green1 -quiet
```

Expected: PASS

### Task 2: 锁定流带最小宽度与主次差异

**Files:**
- Modify: `apps/desktop-macos-native/FluxDeckNative/Features/TopologyCanvasView.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`

**Step 1: 写失败测试，要求小流量也有最小可读宽度**

新增测试覆盖：

- 极小 token 链路不会被渲染为接近 0 的宽度
- 大流量仍明显宽于小流量
- `Tokens` 与 `Requests` 模式都走相同的最小宽度规则

**Step 2: 运行测试，确认失败**

Run:

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative \
  -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTopologyCanvasAppliesMinimumReadableBandWidth \
  -derivedDataPath /tmp/fluxdeck-native-derived-sankey-red2 -quiet
```

Expected: FAIL

**Step 3: 写最小实现**

- 将流带宽度计算抽成纯函数
- 实现 `max(minReadableWidth, scaledWidth(value))`
- 保持非线性缩放

**Step 4: 运行定向测试**

Run:

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative \
  -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTopologyCanvasAppliesMinimumReadableBandWidth \
  -derivedDataPath /tmp/fluxdeck-native-derived-sankey-green2 -quiet
```

Expected: PASS

### Task 3: 重构主画布比例与节点弱化

**Files:**
- Modify: `apps/desktop-macos-native/FluxDeckNative/Features/TopologyCanvasView.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative/UI/DesignTokens.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`

**Step 1: 写失败测试，锁定更轻的节点锚点表现**

新增测试覆盖：

- 节点卡片不再暴露过多诊断字段
- 画布高度和列间距更偏向流带主舞台
- `Gateway` 列保持略高权重，但不回到重卡片

**Step 2: 运行测试，确认失败**

Run:

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative \
  -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTopologyCanvasPrioritizesBandStageOverHeavyCards \
  -derivedDataPath /tmp/fluxdeck-native-derived-sankey-red3 -quiet
```

Expected: FAIL

**Step 3: 写最小实现**

- 收窄节点宽度
- 调整列间距、背景层级、标题说明和控制栏位置
- 保持三列结构稳定

**Step 4: 运行定向测试**

Run:

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative \
  -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTopologyCanvasPrioritizesBandStageOverHeavyCards \
  -derivedDataPath /tmp/fluxdeck-native-derived-sankey-green3 -quiet
```

Expected: PASS

### Task 4: 加入 hover 高亮与 tooltip 数据

**Files:**
- Modify: `apps/desktop-macos-native/FluxDeckNative/Features/TopologyCanvasView.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`

**Step 1: 写失败测试，锁定 hover 语义**

新增测试覆盖：

- hover 流带时能得到链路 tooltip 数据
- hover 节点时能得到节点汇总 tooltip 数据
- 非 hover 链路有降透明度语义

**Step 2: 运行测试，确认失败**

Run:

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative \
  -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTopologyCanvasBuildsHoverTooltipPayloads \
  -derivedDataPath /tmp/fluxdeck-native-derived-sankey-red4 -quiet
```

Expected: FAIL

**Step 3: 写最小实现**

- 在 `TopologyCanvasView.swift` 中加入 hover state
- 为流带和节点分别生成 tooltip 文案与高亮状态
- 保持不新增右侧详情抽屉

**Step 4: 运行定向测试**

Run:

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative \
  -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTopologyCanvasBuildsHoverTooltipPayloads \
  -derivedDataPath /tmp/fluxdeck-native-derived-sankey-green4 -quiet
```

Expected: PASS

### Task 5: 文档同步与完整验证

**Files:**
- Modify: `README.md`
- Modify: `docs/plans/active/2026-03-13-native-topology-sankey-polish-design.md`
- Modify: `docs/plans/active/2026-03-13-native-topology-sankey-polish.md`
- Modify: `docs/progress/2026-03-13-native-topology-token-flow.md`

**Step 1: 运行完整原生测试**

Run:

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -derivedDataPath /tmp/fluxdeck-native-derived-sankey-final -quiet
```

Expected: PASS

**Step 2: 运行仓库级验证**

Run:

```bash
cargo test -q
./scripts/e2e/smoke.sh
```

Expected: PASS；如存在既有 warning，在进度文档记录。

**Step 3: 更新文档状态**

- 设计文档改为 `已实现`
- 进度文档补充 Sankey 主舞台重构结果与 hover 诊断说明
- README 如有必要补充“参考图导向的 Sankey 画布”表述

**Step 4: 检查 git 状态**

Run:

```bash
git status --short
```

Expected: 仅有本次相关文件变更。

**Step 5: 提交**

```bash
git add README.md \
  apps/desktop-macos-native/FluxDeckNative/Features/TopologyCanvasView.swift \
  apps/desktop-macos-native/FluxDeckNative/UI/DesignTokens.swift \
  apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift \
  docs/plans/active/2026-03-13-native-topology-sankey-polish-design.md \
  docs/plans/active/2026-03-13-native-topology-sankey-polish.md \
  docs/progress/2026-03-13-native-topology-token-flow.md
git commit -m "feat(native-topology): polish sankey stage"
```
