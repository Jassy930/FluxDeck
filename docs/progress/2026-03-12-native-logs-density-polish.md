# 2026-03-12 Native Logs Density Polish

## 阶段 1：设计确认与实施计划

- 时间：2026-03-12 CST
- 范围：`apps/desktop-macos-native`

### 已确认设计

- 顶部 `Log Filters` 收敛为紧凑工具栏
- `Request Stream` 内部改为更接近表格行的日志流
- 折叠态采用两行紧凑布局
- 首屏核心字段固定为：
  - `状态`
  - `路由`
  - `模型 / 错误摘要`
  - `token 摘要`
  - `latency`
  - `time`
- 展开态保留当前手风琴交互，但重组为更紧凑的分组式诊断区

### 文档产出

- 新增设计文档：`docs/plans/completed/2026-03-12-native-logs-density-polish-design.md`
- 新增实施计划：`docs/plans/completed/2026-03-12-native-logs-density-polish.md`

### 当前 git 状态

- 工作区初始检查：干净
- 当前阶段仅新增文档，尚未进入代码实现

## 阶段 2：原生日志界面密度优化实现

- 时间：2026-03-12 CST
- 范围：`apps/desktop-macos-native`

### 红阶段

- 在 `FluxDeckNativeTests.swift` 新增两类失败测试：
  - 紧凑折叠态摘要直接暴露 token 摘要、时间标签与 meta badges
  - 展开态直接暴露 `Execution / Diagnostics` 分组数据
- 执行定向测试：

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testCompactLogRowSummaryFormatting -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testExpandedDiagnosticsGrouping -derivedDataPath /tmp/fluxdeck-native-derived-logs-density-red1 -quiet
```

- 结果：按预期失败，`LogStreamCardModel` 缺少新的紧凑摘要与分组字段

### 绿阶段

- 在 `LogsWorkbenchView.swift` 中为 `LogStreamCardModel` 增加：
  - `secondaryMetaText`
  - `metaBadges`
  - `executionDetails`
  - `diagnosticsDetails`
- 将 `Log Filters` 收敛为更轻的筛选工具栏
- 将日志项收敛为两行紧凑日志行，并保留单条展开
- 将展开态重组为 `Execution` 与 `Diagnostics` 分组

### 文档同步

- 更新 `README.md`
- 更新 `apps/desktop-macos-native/README.md`
- 更新 `docs/contracts/admin-api-v1.md`
- 更新 `docs/ops/local-runbook.md`
- 更新 `docs/USAGE.md`

### 最终验证

执行：

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -derivedDataPath /tmp/fluxdeck-native-derived-logs-density-full -quiet
cargo test -q
./scripts/e2e/smoke.sh
```

结果：

- `xcodebuild test ...` 通过
- `cargo test -q` 通过
- `./scripts/e2e/smoke.sh` 输出 `smoke ok`

说明：

- `cargo test -q` 过程中存在已有 `unused variable` warning，但不影响测试通过

### 当前 git 状态

- 已修改：`apps/desktop-macos-native/FluxDeckNative/Features/LogsWorkbenchView.swift`
- 已修改测试：`apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`
- 已更新文档：`README.md`、`apps/desktop-macos-native/README.md`、`docs/USAGE.md`、`docs/contracts/admin-api-v1.md`、`docs/ops/local-runbook.md`
- 已新增：`docs/plans/completed/2026-03-12-native-logs-density-polish-design.md`、`docs/plans/completed/2026-03-12-native-logs-density-polish.md`、`docs/progress/2026-03-12-native-logs-density-polish.md`
