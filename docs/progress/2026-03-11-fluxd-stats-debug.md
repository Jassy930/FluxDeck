# 2026-03-11 fluxd Stats Debug

## 现象

- 原生 `Traffic` 页面没有展示实时统计内容
- 直接读取 `fluxd`：
  - `/admin/logs?limit=5` 有最近请求
  - `/admin/stats/overview?period=1h` 返回全 0
  - `/admin/stats/trend?period=1h&interval=5m` 返回空数组

## 调查结果

- 运行中的 `fluxd` 使用数据库：`/Users/jassy/.fluxdeck/fluxdeck.db`
- 数据库中最近 1 小时 `request_logs` 实际有 17 条记录
- 根因不是无流量，也不是时区导致漏算
- 真正根因是 stats SQL 中 `AVG(latency_ms)` 在 SQLite 返回 `REAL`
- `admin_routes.rs` 却把这些查询结果按 `i64` 解码
- 查询失败后被 `Err(_) => 0 / []` 吞掉，导致 stats 接口看起来像“没有数据”

## 时间说明

- `fluxd` / SQLite `CURRENT_TIMESTAMP` 使用 UTC
- 例如日志中 `2026-03-11 08:55:07` 对应本地上海时间 `2026-03-11 16:55:07`
- 时间显示不是本地时区，但不影响按 UTC 窗口聚合

## 修复

- 将 stats SQL 中的 `AVG(latency_ms)` 显式转换为整数毫秒
- 移除 overview 总查询里未使用且会触发类型解码失败的 `avg_latency`
- 新增回归测试覆盖“平均延迟为小数时，stats 仍应返回最近日志统计”

## 验证

已执行：

```bash
cargo test -q admin_stats_include_recent_logs_even_when_average_latency_is_fractional --test admin_api_test
```

结果：

- 失败测试先稳定复现
- 修复后通过

## 备注

- 当前正在运行的本地 `fluxd` 进程仍是旧二进制
- 需要重启 `fluxd` 后，真实 `/admin/stats/*` 响应才会反映本次修复
