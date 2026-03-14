# 2026-03-14 Native Traffic Input Display Fix

## 背景

原生桌面端 `Traffic` 页面 `Total Tokens` KPI 的 `Input` 行当前直接展示周期内 `input_tokens` 总和，包含了 `cached_tokens`。本次仅调整该处展示口径，要求 `Input` 显示为排除缓存命中后的净输入 token。

## 变更

- 修改 `apps/desktop-macos-native/FluxDeckNative/Features/TrafficConnectionsModels.swift`
- `TrafficAnalyticsModel.kpiStripItems` 中 `Total Tokens` 的 `Input` 展示值改为 `max(totalInputTokens - totalCachedTokens, 0)`
- 不修改后端 Stats API 契约
- 不修改 `trend` 图表、bucket 明细、日志页和其他页面的 token 语义

## 测试

- `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTrafficMonitorModelExposesKpiSupplementRows -quiet`
  - 先失败，确认旧行为仍显示 `2,200`
  - 实现后通过，确认新行为显示 `1,300`
- `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTrafficMonitorModelExposesKpiSupplementRows -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTrafficMonitorModelExposesKpiStripItems -quiet`
  - 通过

## 结果

- `Traffic` 页 `Total Tokens` 卡中的 `Input` 现在显示“原始输入减去 cached”后的净输入值
- 本次变更范围限定在原生端视图模型，未扩散到 API 与存储层
