# Native Traffic 趋势图柔化曲线 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将原生端 `Traffic` 页 `Token Trend by Model` 主图从硬折线改为中度柔化曲线，同时保持现有 hover、tooltip、图例和数据口径不变。

**Architecture:** 在 `TrafficAnalyticsView.swift` 中提取可测试的平滑路径辅助函数，先用 XCTest 锁定控制点与路径几何约束，再将折线和堆叠面积统一切换到共享的贝塞尔曲线构造。整个实现只改原生端渲染层，不触碰后端契约或 Web 桌面端。

**Tech Stack:** SwiftUI、XCTest、xcodebuild、Markdown

---

### Task 1: 锁定平滑曲线几何约束

**Files:**
- Modify: `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`
- Reference: `docs/plans/active/2026-03-13-native-traffic-trend-curve-polish-design.md`

**Step 1: 写失败测试**

新增针对平滑路径辅助函数的测试，至少覆盖：

- 两点场景会生成一段曲线且首尾点不变
- 三点尖峰场景的控制点不会明显越过相邻点形成假峰值
- 平台数据不会因为曲线插值产生无意义波动

**Step 2: 运行测试确认失败**

Run:

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTrafficTrendSmoothingSegmentsKeepEndpointsAndClampControlPoints -derivedDataPath /tmp/fluxdeck-native-derived-curve-red1 -quiet
```

Expected: FAIL，错误来自平滑路径辅助函数尚不存在或断言不成立。

### Task 2: 实现平滑路径辅助函数

**Files:**
- Modify: `apps/desktop-macos-native/FluxDeckNative/Features/TrafficAnalyticsView.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`

**Step 1: 写最小实现**

在 `TrafficAnalyticsView.swift` 中新增：

- 可测试的平滑段描述结构
- 控制点计算函数
- `smoothedLinePath`
- 共享的点集转换逻辑

要求：

- 首尾点保持真实 bucket 坐标
- 控制点 `y` 值受局部上下界约束
- 点数不足时平滑函数安全回退

**Step 2: 运行定向测试**

Run:

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTrafficTrendSmoothingSegmentsKeepEndpointsAndClampControlPoints -derivedDataPath /tmp/fluxdeck-native-derived-curve-green1 -quiet
```

Expected: PASS

### Task 3: 将折线与堆叠面积统一切换到平滑曲线

**Files:**
- Modify: `apps/desktop-macos-native/FluxDeckNative/Features/TrafficAnalyticsView.swift`

**Step 1: 替换折线路径**

将当前 `rawLinePath` 的逐点 `addLine` 改为使用平滑路径函数。

**Step 2: 替换面积上边界**

将 `stackedAreaPath` 的上边界与下边界也改为共享平滑路径闭合，避免“线圆面折”。

**Step 3: 保持交互稳定**

确认以下逻辑不变：

- hover 仍按 bucket 命中
- tooltip 仍取真实 bucket 数据
- 高亮点仍使用原始 bucket 坐标

### Task 4: 回归测试与文档收尾

**Files:**
- Modify: `docs/progress/2026-03-13-native-traffic-model-token-trend.md`

**Step 1: 跑定向测试**

Run:

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative \
  -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTrafficTrendRenderableLinesUseTotalAsPrimaryAndModelRawValues \
  -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTrafficTrendSmoothingSegmentsKeepEndpointsAndClampControlPoints \
  -derivedDataPath /tmp/fluxdeck-native-derived-curve-final -quiet
```

Expected: PASS

**Step 2: 记录进度**

在 `docs/progress/2026-03-13-native-traffic-model-token-trend.md` 增补本次“柔化曲线”改动、验证命令与结果。

**Step 3: 整理工作区**

Run:

```bash
git status --short
```

确认仅包含本次相关文件变更。
