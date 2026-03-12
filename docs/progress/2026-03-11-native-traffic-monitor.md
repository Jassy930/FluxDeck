# 2026-03-11 Native Traffic Monitor

## 本次完成

- 为 `apps/desktop-macos-native` 接入原生统计模型与 Admin Stats API 解码
- 为 `Traffic` 页面接入真实 `/admin/stats/overview` 与 `/admin/stats/trend`
- 将 `Traffic` 页面改造成监控工作台，包含：
  - 时间范围切换 `1h / 6h / 24h`
  - KPI 指标
  - 趋势图
  - Gateway / Provider / Model breakdown
  - Alerts 摘要
- 保持与现有 `SurfaceCard`、`StatusPill`、`DesignTokens` 一致的原生工作台风格
- 将 KPI 指标栏升级为“主值 + 附属指标”结构：
  - `Requests / min` 展示请求量前二 gateway 的 `rpm`
  - `Success Rate` 展示请求量前二 gateway 的 `ok / err`
  - `Avg Latency` 展示请求量前二 gateway 的具体延迟
  - `Total Tokens` 展示 `Input / Output / Cached`
- 将 `Cached` token 口径改为直接消费 `fluxd` `/admin/stats/overview` 与 `/admin/stats/trend` 返回的稳定 `cached_tokens` 字段
- 同步扩展 `fluxd` Stats 契约，在顶层总览、Gateway/Provider/Model breakdown 与趋势 bucket 中均返回 `cached_tokens`

## 主要文件

- `apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift`
- `apps/desktop-macos-native/FluxDeckNative/Features/TrafficAnalyticsView.swift`
- `apps/desktop-macos-native/FluxDeckNative/Features/TrafficConnectionsModels.swift`
- `apps/desktop-macos-native/FluxDeckNative/Networking/AdminApiClient.swift`
- `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`
- `crates/fluxd/src/http/admin_routes.rs`
- `crates/fluxd/tests/admin_api_test.rs`
- `docs/contracts/admin-api-v1.md`
- `docs/plans/2026-03-12-native-traffic-kpi-supplement-design.md`
- `docs/plans/2026-03-12-native-traffic-kpi-supplement.md`

## 验证

已执行：

```bash
cargo test -q --test admin_api_test
cargo test -q
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testAdminStatsOverviewAndTrendDecodeCachedTokens -derivedDataPath /tmp/fluxdeck-native-derived-kpi-cached -quiet
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -derivedDataPath /tmp/fluxdeck-native-derived-kpi-full -quiet
```

结果：

- `cargo test -q --test admin_api_test` 21 个用例通过
- `cargo test -q` 全量通过
- 已验证 `cached_tokens` 解码测试通过
- 原生 `FluxDeckNativeTests` 完整测试通过
- 存在 Xcode/XCTest 的 macOS 版本告警，但不影响测试通过

## 后续可选

- 为 `Traffic` 增加自动轮询刷新
- 将趋势图进一步细化为请求量 / 延迟 / 错误数多层可切换视图
- 增加点击 breakdown 跳转 `Logs` 过滤视图
