# 2026-03-09 Gateway Auto Start 实施记录

## 目标

为 Gateway 新增独立的 `auto_start` 开关，并同步更新 `fluxd` 后端、macOS 原生前端与 `fluxctl`：

- `auto_start=true` 时，`fluxd` 每次启动后自动尝试拉起对应 Gateway
- 单个 Gateway 自动启动失败不影响 `fluxd` 本身启动
- 失败信息可通过 Gateway 列表中的 `last_error` 在界面查看

## 设计决策

- 不复用现有 `enabled` 字段，避免把“配置启用”和“进程启动时自动拉起”混为一谈
- 自动启动筛选条件为 `enabled=true && auto_start=true`
- 启动失败仅记录到运行时错误状态，不中断服务主进程

## 实现范围

### 后端

- `crates/fluxd/migrations/003_gateway_auto_start.sql`
- `crates/fluxd/src/domain/gateway.rs`
- `crates/fluxd/src/repo/gateway_repo.rs`
- `crates/fluxd/src/runtime/gateway_manager.rs`
- `crates/fluxd/src/http/admin_routes.rs`
- `crates/fluxd/src/main.rs`

新增：

- `PUT /admin/gateways/{id}` 全量更新 Gateway 配置
- 更新只写入配置，不热更新当前已运行实例

### 原生前端

- `apps/desktop-macos-native/FluxDeckNative/Networking/AdminApiClient.swift`
- `apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift`
- `apps/desktop-macos-native/FluxDeckNative/Features/GatewayListView.swift`
- `apps/desktop-macos-native/FluxDeckNative/Features/ResourceWorkspaceModels.swift`

新增：

- Gateway 卡片增加 `Edit`
- Gateway 创建/编辑统一为 `GatewayFormSheet`
- 编辑界面内容参考 Provider 配置界面组织方式

### CLI

- `crates/fluxctl/src/cli.rs`
- `crates/fluxctl/src/main.rs`
- `crates/fluxctl/src/client.rs`

新增：

- `gateway create --auto-start true|false`
- `gateway update ...`

### 测试

- `crates/fluxd/tests/admin_api_test.rs`
- `crates/fluxd/tests/gateway_manager_test.rs`
- `crates/fluxd/tests/storage_migration_test.rs`
- `crates/fluxctl/tests/cli_smoke_test.rs`
- `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`

## 验证

- `cargo test -q -p fluxd --test gateway_manager_test`
- `cargo test -q -p fluxd --test storage_migration_test`
- `cargo test -q -p fluxd`
- `cargo test -q -p fluxctl --test cli_smoke_test`
- `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`

## 备注

- 本次已更新 `fluxctl`，但 Web 前端仍未补 Gateway 编辑入口
- 兼容旧客户端：未传 `auto_start` 时，后端默认按 `false` 处理
- 后续暂不更新 Web 前端界面；该项列为第二优先级，按阶段手动同步 Gateway 相关功能
