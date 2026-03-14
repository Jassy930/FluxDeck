# 2026-03-14 Traffic Trend Continuity Fix

## 结果

- 修复了 `fluxd` 的 `GET /admin/stats/trend` 仅返回非空 bucket 的问题。
- 现在 trend 接口会按 `period + interval` 生成连续时间桶：
  - 有数据的 bucket 回填真实聚合值
  - 无数据的 bucket 返回 `request_count=0`、`avg_latency=0`、`error_count=0`
  - 空 bucket 的 `input_tokens / output_tokens / cached_tokens` 均为 `0`
  - 空 bucket 的 `by_model` 返回空数组
- 原生端 `Traffic` 主图不再需要猜测或补洞，横向时间轴可直接按接口返回的连续 bucket 渲染。

## 根因

- 之前的 `/admin/stats/trend` 查询只对 `request_logs` 中实际存在请求的时间桶做 `GROUP BY`。
- 当某些时段没有任何请求时，接口会直接缺失对应 bucket，导致前端图表把相邻的非空桶直接连起来。
- 这种稀疏时间轴在 `6h / 24h` 上更明显，所以视觉上会误以为“粒度变粗”。

## 实现

- `crates/fluxd/src/http/admin_routes.rs`
  - 在 `get_stats_trend` 中引入递归 CTE 生成连续 bucket 序列
  - 再将已有聚合结果左连接到完整 bucket 序列上
  - 保持现有返回字段和模型 bucket 聚合逻辑不变
- `crates/fluxd/tests/admin_api_test.rs`
  - 新增连续空桶回归测试
  - 调整既有 trend 测试，使其基于“非空 bucket”断言模型聚合内容，兼容新的连续时间轴语义

## 验证

- `cargo test -q -p fluxd admin_stats_trend_returns_continuous_buckets_with_zero_value_gaps`：PASS
- `cargo test -q -p fluxd admin_stats_trend`：PASS
- `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTrafficMonitorBuildsTokenTrendSeriesAndSummary -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTrafficMonitorGroupsTailModelsIntoOtherForTokenTrend -quiet`：PASS

## 备注

- 本轮未修改 Admin API 契约字段，只修正了趋势时间轴的完整性。
- 仓库仍存在既有 warning：`crates/fluxd/tests/anthropic_stream_encoder_test.rs` 中的未使用变量 `lines`，本轮未处理。
