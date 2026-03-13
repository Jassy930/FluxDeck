# Native Topology Token Flow Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将原生端 `Topology` 页面从“按请求量画单色粗线”的静态结构图升级为“按 model 分层的 token 流画布”，在保持三列结构的前提下表达总 token 体积、model 构成与热点路径。

**Architecture:** 不扩展后端契约，继续使用原生端已有的 `AdminGateway`、`AdminProvider`、`AdminLog`。先通过测试锁定 `TopologyGraph` 的 token 聚合语义和 model 归并规则，再重写 `TopologyCanvasView` 为支持 token/request 双指标、按 model 分层流带与底部摘要的 SwiftUI 画布。状态控制保持在页面内，避免把临时展示态上升到全局导航层。

**Tech Stack:** SwiftUI、XCTest、xcodebuild、Markdown

---

### Task 1: 用失败测试锁定拓扑 token 聚合语义

**Files:**
- Modify: `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative/Features/TopologyModels.swift`

**Step 1: 写失败测试，覆盖边级 token 聚合与 model 分层**

在 `FluxDeckNativeTests.swift` 新增测试，断言：

- 同一条 `gateway -> provider` 边会聚合多条日志的 `total_tokens`
- 同一路径中的不同 model 会生成独立 `segment`
- `model_effective` 优先于 `model`
- `total_tokens` 为空时会回填 `input_tokens + output_tokens`
- token 缺失但存在请求时，边仍保留最小可见请求语义

**Step 2: 运行测试，确认因旧模型缺少字段失败**

Run:

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative \
  -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTopologyGraphAggregatesTokenSegmentsPerEdge \
  -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTopologyGraphFallsBackForMissingTokenFields \
  -derivedDataPath /tmp/fluxdeck-native-derived-topology-red1 -quiet
```

Expected: FAIL，错误来自 `TopologyEdge` / `TopologyNode` 尚未暴露 token 聚合字段或 segment 结构。

**Step 3: 写最小实现**

在 `TopologyModels.swift`：

- 为节点补齐 `totalTokens / requestCount / cachedTokens / errorCount`
- 为边补齐 `totalTokens / requestCount / cachedTokens / errorCount / segments`
- 新增 `TopologyEdgeSegment`
- 基于 `AdminLog` 聚合边级与节点级 token 数据

**Step 4: 运行定向测试，确认通过**

Run:

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative \
  -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTopologyGraphAggregatesTokenSegmentsPerEdge \
  -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTopologyGraphFallsBackForMissingTokenFields \
  -derivedDataPath /tmp/fluxdeck-native-derived-topology-green1 -quiet
```

Expected: PASS

### Task 2: 锁定 Top N model 与 Other 合并规则

**Files:**
- Modify: `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative/Features/TopologyModels.swift`

**Step 1: 写失败测试，覆盖 Top 3 / Top 5 / All 行为**

新增测试，断言：

- 默认高亮模式只保留 Top 5 model
- 超出阈值的尾部 model 被合并为 `Other`
- `All` 模式下不合并
- `By Model` 与 `Total Only` 使用相同总量但不同 segment 暴露方式

**Step 2: 运行测试，确认失败**

Run:

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative \
  -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTopologyGraphBuildsTopModelHighlightsAndOtherBucket \
  -derivedDataPath /tmp/fluxdeck-native-derived-topology-red2 -quiet
```

Expected: FAIL，错误来自高亮模式和 `Other` 合并逻辑尚未存在。

**Step 3: 写最小实现**

在 `TopologyModels.swift` 新增：

- `TopologyMetricMode`
- `TopologyFlowMode`
- `TopologyHighlightMode`
- 基于 period 总 token 的 Top N model 计算
- `Other` 合并逻辑

**Step 4: 运行定向测试，确认通过**

Run:

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative \
  -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTopologyGraphBuildsTopModelHighlightsAndOtherBucket \
  -derivedDataPath /tmp/fluxdeck-native-derived-topology-green2 -quiet
```

Expected: PASS

### Task 3: 重构拓扑画布为流带视图

**Files:**
- Modify: `apps/desktop-macos-native/FluxDeckNative/Features/TopologyCanvasView.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`

**Step 1: 写失败测试，锁定无数据态与摘要语义**

新增测试，断言：

- 无边时仍显示空画布提示
- 底部摘要标题改为 `Hot Paths` 和 `Model Mix`
- 节点卡片文案包含 token 指标而不仅是地址/协议

**Step 2: 运行测试，确认失败**

Run:

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative \
  -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTopologyCanvasSummaryUsesTokenSemantics \
  -derivedDataPath /tmp/fluxdeck-native-derived-topology-red3 -quiet
```

Expected: FAIL，错误来自视图仍显示旧的 `Route Summary` 和旧节点卡片。

**Step 3: 写最小实现**

在 `TopologyCanvasView.swift`：

- 将旧描边 Path 改为可填充的带状曲线
- 支持 `Tokens / Requests`
- 支持 `By Model / Total Only`
- 支持 `Top 3 / Top 5 / All`
- 将底部摘要改为 `Hot Paths + Model Mix`
- 节点卡片补齐 token / req / cached / error 诊断信息

**Step 4: 运行定向测试，确认通过**

Run:

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative \
  -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTopologyCanvasSummaryUsesTokenSemantics \
  -derivedDataPath /tmp/fluxdeck-native-derived-topology-green3 -quiet
```

Expected: PASS

### Task 4: 统一色板、流带层级和格式化细节

**Files:**
- Modify: `apps/desktop-macos-native/FluxDeckNative/UI/DesignTokens.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative/Features/TopologyCanvasView.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`

**Step 1: 写失败测试，要求 model 颜色映射稳定**

新增测试，断言：

- 同一 model 在整张图中颜色稳定
- `Other` 使用低饱和保底色
- 异常链路仍能叠加错误语义而不覆盖 model 主色

**Step 2: 运行测试，确认失败**

Run:

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative \
  -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTopologyFlowUsesStableModelPalette \
  -derivedDataPath /tmp/fluxdeck-native-derived-topology-red4 -quiet
```

Expected: FAIL，错误来自颜色映射和辅助样式尚未抽象。

**Step 3: 写最小实现**

在 `DesignTokens.swift` 或 `TopologyCanvasView.swift` 内集中定义：

- model 色板
- `Other` 保底色
- token 数字格式化
- 错误描边与低活跃透明度规则

**Step 4: 运行定向测试，确认通过**

Run:

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative \
  -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTopologyFlowUsesStableModelPalette \
  -derivedDataPath /tmp/fluxdeck-native-derived-topology-green4 -quiet
```

Expected: PASS

### Task 5: 做完整原生回归与文档同步

**Files:**
- Modify: `docs/progress/2026-03-13-native-topology-token-flow.md`
- Modify: `README.md`
- Modify: `docs/plans/active/2026-03-13-native-topology-token-flow-design.md`
- Modify: `docs/plans/active/2026-03-13-native-topology-token-flow.md`

**Step 1: 运行完整原生测试**

Run:

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -derivedDataPath /tmp/fluxdeck-native-derived-topology-all -quiet
```

Expected: PASS

**Step 2: 检查是否需要更新 README 对原生拓扑页的描述**

如果 README 中已有原生端页面说明，补充“token flow / model composition”语义；如果没有变化则记录为无需修改。

**Step 3: 更新进度与设计文档状态**

- 在进度文件记录最终结果、验证命令与限制
- 在设计文档中注明实现完成状态

**Step 4: 检查 git 状态**

Run:

```bash
git status --short
```

Expected: 仅看到本次相关文件改动，无无关回滚。

**Step 5: 提交**

```bash
git add apps/desktop-macos-native/FluxDeckNative/Features/TopologyModels.swift \
  apps/desktop-macos-native/FluxDeckNative/Features/TopologyCanvasView.swift \
  apps/desktop-macos-native/FluxDeckNative/UI/DesignTokens.swift \
  apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift \
  docs/progress/2026-03-13-native-topology-token-flow.md \
  docs/plans/active/2026-03-13-native-topology-token-flow-design.md \
  docs/plans/active/2026-03-13-native-topology-token-flow.md \
  README.md
git commit -m "feat(native-topology): add token flow canvas"
```
