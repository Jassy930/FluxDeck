# 2026-03-12 Native Logs Workbench Redesign

## 阶段 1：后端日志契约补齐

- 时间：2026-03-12 16:59:22 CST
- 范围：`crates/fluxd`

### 红阶段

- 在 `storage_migration_test`、`request_log_service_test`、`admin_api_test` 中先加入 `cached_tokens` 断言。
- 定向执行 `cargo test -q --test storage_migration_test --test request_log_service_test --test admin_api_test`。
- 失败结果符合预期：`UsageSnapshot` 尚未提供 `cached_tokens` 字段，测试无法通过。

### 绿阶段

- 新增 migration `006_request_logs_cached_tokens.sql`，为 `request_logs` 增加稳定列 `cached_tokens`。
- 扩展 `UsageSnapshot`、usage 提取逻辑、日志写入/回写链路，以及 `/admin/logs` 返回结构。
- 同步修正 repair-table 路径，确保旧库修复时也会保留 `cached_tokens`。

### 验证

```bash
cargo test -q --test storage_migration_test --test request_log_service_test --test admin_api_test
```

- 结果：通过

### 当前 git 状态

- 已修改：`crates/fluxd/src/forwarding/*`、`crates/fluxd/src/service/request_log_service.rs`、`crates/fluxd/src/http/admin_routes.rs`、`crates/fluxd/src/storage/migrate.rs`
- 已修改测试：`crates/fluxd/tests/storage_migration_test.rs`、`crates/fluxd/tests/request_log_service_test.rs`、`crates/fluxd/tests/admin_api_test.rs`、`crates/fluxd/tests/forwarding_types_test.rs`
- 新增文件：`crates/fluxd/migrations/006_request_logs_cached_tokens.sql`

## 阶段 2：原生端日志模型补齐

- 时间：2026-03-12 17:03:13 CST
- 范围：`apps/desktop-macos-native`

### 红阶段

- 在 `FluxDeckNativeTests.swift` 新增完整日志契约解码测试、模型映射展示测试、四类 token 摘要测试。
- 执行 `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`。
- 失败结果符合预期：`AdminLog` 尚未暴露完整字段，也没有对应格式化属性。

### 绿阶段

- 为 `AdminLog` 增加协议、模型映射、流式/延迟、token、错误阶段等完整字段。
- 为兼容旧 payload，补上自定义解码默认值，保证缺失字段时仍能解码。
- 将模型映射、token 摘要、错误摘要整理为 `AdminLog` 计算属性，复用到旧详情卡模型。

### 验证

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet
```

- 结果：通过

### 当前 git 状态

- 已修改：`apps/desktop-macos-native/FluxDeckNative/Networking/AdminApiClient.swift`、`apps/desktop-macos-native/FluxDeckNative/Features/SettingsModels.swift`
- 已修改测试：`apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`
- 后端阶段改动仍保留，待统一收口

## 阶段 3：Logs Workbench 单列手风琴重构

- 时间：2026-03-12 17:07:47 CST
- 范围：`apps/desktop-macos-native/FluxDeckNative/Features/LogsWorkbenchView.swift`

### 红阶段

- 新增日志卡片摘要模型与展开状态机测试：
  - 失败日志摘要优先错误文本
  - 成功日志保留模型、路由、延迟、时间
  - 同时只允许一条展开
  - 可见日志变化或筛选变化后会清理失效展开项
- 执行 `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`。
- 失败结果符合预期：缺少 `LogStreamCardModel` 与 `LogsWorkbenchExpansionState`。

### 绿阶段

- 用单列 `Request Stream` 取代旧的 `Requests + Details` 双栏布局。
- 引入 `LogsWorkbenchExpansionState` 管理单一展开项。
- 引入 `LogStreamCardModel` 统一折叠态/展开态字符串，避免视图层重复拼装文案。
- 展开态补齐请求 ID、协议、stream、first byte、四类 token、错误阶段/类型、完整错误文本与原始 `usage_json`。

### 验证

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet
```

- 结果：通过

### 当前 git 状态

- 已修改：`apps/desktop-macos-native/FluxDeckNative/Features/LogsWorkbenchView.swift`
- 原生端与后端前序阶段改动仍保留，待统一文档与总验收收口

## 阶段 4：文档同步与总验收

- 时间：2026-03-12 17:13:20 CST
- 范围：契约文档、使用说明、运行手册、README、`fluxctl` 范围核查

### 文档同步

- 更新 `docs/contracts/admin-api-v1.md`，将 `cached_tokens` 固化为稳定日志字段，并说明原生端 Logs 工作台已消费单列可展开日志流。
- 更新 `docs/USAGE.md` 与 `docs/ops/local-runbook.md`：
  - 补充 `cached_tokens`
  - 说明原生端 Logs 页已改为单列可展开卡片
  - 明确 `fluxctl logs` 仍然只是输出分页 JSON
- 更新 `README.md` 与 `apps/desktop-macos-native/README.md`，同步新的日志工作台形态与 token 观察能力。

### `fluxctl` 范围核查

- 检查 `crates/fluxctl/src/main.rs` 后确认：
  - `logs` 子命令仅调用 `GET /admin/logs?limit=N`
  - 然后直接 `serde_json::to_string_pretty` 输出
- 结论：`fluxctl` 本次无需代码修改，也无需新增测试，只需文档同步。

### 最终验证

```bash
cargo test -q
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet
./scripts/e2e/smoke.sh
```

- 结果：
  - `cargo test -q` 通过
  - `xcodebuild test ...` 通过
  - `./scripts/e2e/smoke.sh` 输出 `smoke ok`

### 当前 git 状态

- 已修改：`crates/fluxd/*`、`apps/desktop-macos-native/*`、`docs/*`、`README.md`、`apps/desktop-macos-native/README.md`
- 新增文件：
  - `crates/fluxd/migrations/006_request_logs_cached_tokens.sql`
  - `docs/progress/2026-03-12-native-logs-workbench-redesign.md`

## 阶段 5：合入后原生端兼容修复

- 时间：2026-03-12 17:45:00 CST
- 范围：`apps/desktop-macos-native/FluxDeckNative/Networking/AdminApiClient.swift`

### 现象

- 日志工作台分支合入 `main` 后，原生端测试在默认 `DerivedData` 上出现两类异常：
  - 先是链接阶段找不到旧签名 `AdminLog.init(requestID:gatewayID:providerID:model:statusCode:latencyMs:error:createdAt:)`
  - 后续在脏增量产物上出现 `outlined destroy of [AdminLog]` 崩溃，看起来像应用启动即退，但实际崩溃进程为 `FluxDeckNativeTests.xctest`

### 处理

- 在 `AdminLog` 上补回旧签名初始化器，内部统一转发到新的全量初始化器，避免旧测试夹具和旧调用点失配。
- 使用全新 `DerivedData` 路径 `/tmp/fluxdeck-native-derived-mainverify` 重新验证，确认崩溃来自 Xcode 增量构建缓存污染，而不是当前源码的确定性运行时问题。

### 验证

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -derivedDataPath /tmp/fluxdeck-native-derived-mainverify -destination 'platform=macOS,arch=arm64' -quiet
cargo test -q
./scripts/e2e/smoke.sh
```

- 结果：
  - 原生端测试通过
  - `cargo test -q` 通过
  - `./scripts/e2e/smoke.sh` 输出 `smoke ok`

### 当前 git 状态

- 已修改：`apps/desktop-macos-native/FluxDeckNative/Networking/AdminApiClient.swift`
- 已更新：`docs/progress/2026-03-12-native-logs-workbench-redesign.md`
