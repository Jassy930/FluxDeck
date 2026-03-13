# 2026-03-13 Native Traffic Model Token Trend

## 结果

- `fluxd` 的 `GET /admin/stats/trend` 已为每个时间 bucket 返回 `by_model`
- 原生端 `Traffic` 主图区已从请求/延迟双折线切换为 token 趋势图：
  - `Total Tokens` 作为粗主线
  - 各模型使用真实 token 折线
  - 底层保留半透明堆叠填充表达组成关系
- 主图已支持更密的时间桶映射：
  - `1h -> 1m`
  - `6h -> 5m`
  - `24h -> 15m`
- 主图新增图例与 hover tooltip，tooltip 会展示当前 bucket 的总 token 与按模型拆分明细
- 原生端视图模型会按 period 总 token 选出 Top 4 模型，其余折叠为 `Other`

## 契约与代码同步

- 后端契约文档已更新：
  - `docs/contracts/admin-api-v1.md`
- Web 侧稳定类型已同步补齐新字段：
  - `apps/desktop/src/api/admin.ts`
- 原生端新增 bucket 级 `by_model` 解码：
  - `apps/desktop-macos-native/FluxDeckNative/Networking/AdminApiClient.swift`
- 原生端新增 token 趋势派生模型：
  - `apps/desktop-macos-native/FluxDeckNative/Features/TrafficConnectionsModels.swift`
- 原生端趋势视图已改为堆叠 token 图表：
  - `apps/desktop-macos-native/FluxDeckNative/Features/TrafficAnalyticsView.swift`

## 验证

- `cargo test -q -p fluxd --test admin_api_test`：PASS
- `cargo test -q`：PASS
- `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`：PASS
- `./scripts/e2e/smoke.sh`：PASS，输出 `anthropic compat ok`、`smoke ok`

## 备注

- `cargo test -q` 仍存在仓库已有的 `unused variable: lines` warning，未在本轮处理
- 本轮未修改暂停中的 `apps/desktop/` 界面实现，只同步了稳定 API 类型

## 追加：趋势图柔化曲线

### 变更

- `Token Trend by Model` 主图的折线由逐段直线改为平滑贝塞尔曲线
- 堆叠面积上边界与下边界改为复用同一套平滑路径逻辑，避免出现“线条变圆但面积仍然生硬”的割裂
- 新增 `buildTrafficTrendSmoothingSegments` 几何辅助函数，用于稳定生成受约束的控制点
- 控制点 `y` 值会被钳制在当前段起止点的局部范围内，避免尖峰附近出现明显过冲或假峰值

### 验证

- `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTrafficTrendSmoothingSegmentsKeepEndpointsAndClampControlPoints -derivedDataPath /tmp/fluxdeck-native-derived-curve-green1 -quiet`：PASS
- `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTrafficTrendRenderableLinesUseTotalAsPrimaryAndModelRawValues -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTrafficTrendSmoothingSegmentsKeepEndpointsAndClampControlPoints -derivedDataPath /tmp/fluxdeck-native-derived-curve-final -quiet`：PASS

### 说明

- hover 命中、tooltip 数据、竖向高亮线和图例映射均保持原有 bucket 语义，不跟随曲线插值结果变化
