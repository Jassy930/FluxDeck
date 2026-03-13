# Provider / Gateway 删除功能实现计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为 `fluxd`、`fluxctl` 和原生桌面端增加 Provider / Gateway 删除能力，统一落实“Provider 被引用时拒绝删除”和“运行中的 Gateway 自动停机后删除”的规则。

**Architecture:** 由 `fluxd` Admin API 作为唯一删除语义来源。Provider 删除通过 service + repo 完成引用检查与删除；Gateway 删除由 Admin API 编排运行态停机与 repo 删除。`fluxctl` 与原生端只做确认、调用接口和结果展示，不做本地业务裁决。

**Tech Stack:** Rust (`axum`, `sqlx`, `clap`), SwiftUI, Foundation, Markdown

---

### Task 1: 为 Provider 删除补后端测试

**Files:**
- Modify: `crates/fluxd/tests/admin_api_test.rs`

**Step 1: 写“删除未被引用 Provider 成功”的失败测试**

新增测试：

- 先创建 Provider
- 调用 `DELETE /admin/providers/{id}`
- 断言返回 `200`
- 再调用 `GET /admin/providers` 确认该记录不存在

**Step 2: 写“删除被 Gateway 引用的 Provider 返回 409”的失败测试**

新增测试：

- 先创建 Provider
- 再创建引用它的 Gateway
- 调用 `DELETE /admin/providers/{id}`
- 断言状态码为 `409`
- 断言返回 `referenced_by_gateway_ids`

**Step 3: 运行后端相关测试确认失败**

Run: `cargo test -q admin_api_test`

Expected: 新增的 Provider 删除用例失败，提示路由或删除逻辑缺失

### Task 2: 为 Gateway 删除补后端测试

**Files:**
- Modify: `crates/fluxd/tests/admin_api_test.rs`

**Step 1: 写“删除已停止 Gateway 成功”的失败测试**

新增测试：

- 创建 Provider 和 Gateway
- 不启动 Gateway
- 调用 `DELETE /admin/gateways/{id}`
- 断言返回 `200`
- 再查询 `GET /admin/gateways` 确认记录已删除

**Step 2: 写“删除运行中的 Gateway 会先停机再删除”的失败测试**

新增测试：

- 创建 Provider 和 Gateway
- 调用 `POST /admin/gateways/{id}/start`
- 调用 `DELETE /admin/gateways/{id}`
- 断言返回 `200`
- 断言 `stop_performed=true`

**Step 3: 写“删除不存在资源返回 404”的失败测试**

覆盖：

- `DELETE /admin/providers/provider_not_found`
- `DELETE /admin/gateways/gateway_not_found`

**Step 4: 运行后端相关测试确认失败**

Run: `cargo test -q admin_api_test`

Expected: 新增 Gateway 删除用例失败，提示路由或行为未实现

### Task 3: 实现 Provider 删除后端能力

**Files:**
- Modify: `crates/fluxd/src/repo/provider_repo.rs`
- Modify: `crates/fluxd/src/service/provider_service.rs`
- Modify: `crates/fluxd/src/http/admin_routes.rs`

**Step 1: 在 repo 增加依赖查询与删除能力**

新增方法：

- `list_gateway_ids_referencing(provider_id: &str) -> Result<Vec<String>>`
- `delete(provider_id: &str) -> Result<bool>`

删除时应在事务中先删 `provider_models` 再删 `providers`。

**Step 2: 在 service 增加 Provider 删除结果建模**

新增删除结果类型或错误分支，至少能表达：

- Provider 不存在
- Provider 被哪些 Gateway 引用
- 删除成功

**Step 3: 在 Admin API 新增 `DELETE /admin/providers/{id}`**

要求：

- 成功返回 `{ ok: true, id }`
- 不存在返回 `404`
- 被引用返回 `409` 和 `referenced_by_gateway_ids`

**Step 4: 运行后端相关测试**

Run: `cargo test -q admin_api_test`

Expected: Provider 删除相关测试通过，Gateway 删除相关测试仍可能失败

### Task 4: 实现 Gateway 删除后端能力

**Files:**
- Modify: `crates/fluxd/src/repo/gateway_repo.rs`
- Modify: `crates/fluxd/src/http/admin_routes.rs`

**Step 1: 在 repo 增加 Gateway 删除方法**

新增：

- `delete(gateway_id: &str) -> Result<bool>`

**Step 2: 在 Admin API 新增 `DELETE /admin/gateways/{id}`**

要求：

- 先读取 Gateway 是否存在
- 读取删除前运行态
- 若运行中则先 `stop_gateway`
- 停机成功后再删除配置
- 返回 `ok`、`id`、`runtime_status_before_delete`、`stop_performed`、`user_notice`

**Step 3: 保证停机失败时不删除配置**

失败响应：

- 返回 `400`
- 保留明确错误信息，便于 CLI / UI 直接展示

**Step 4: 运行后端测试**

Run: `cargo test -q admin_api_test`

Expected: 删除相关 Admin API 测试全部通过

### Task 5: 为 `fluxctl` 删除命令补测试

**Files:**
- Modify: `crates/fluxctl/tests/cli_smoke_test.rs`
- Modify: `crates/fluxctl/src/main.rs`

**Step 1: 写 `provider delete` / `gateway delete` 命令解析测试**

覆盖：

- 普通删除命令
- 带 `-y` / `--yes` 的删除命令

**Step 2: 提取可测试的确认逻辑辅助函数测试**

目标：

- `yes=true` 时跳过确认
- 非 `yes` 模式下只有显式确认才返回继续

**Step 3: 运行 CLI 测试确认失败**

Run: `cargo test -q -p fluxctl`

Expected: 新增删除命令和确认逻辑测试失败

### Task 6: 实现 `fluxctl` 删除命令与确认逻辑

**Files:**
- Modify: `crates/fluxctl/src/cli.rs`
- Modify: `crates/fluxctl/src/main.rs`

**Step 1: 为 `ProviderCmd` / `GatewayCmd` 增加 `Delete` 子命令**

参数：

- 位置参数 `id`
- `-y` / `--yes`

**Step 2: 在 `main.rs` 增加删除分支**

要求：

- 默认打印确认提示并读取 stdin
- `-y` 跳过确认
- 成功打印 JSON 响应
- 若有 `user_notice`，额外打印 `Notice: ...`

**Step 3: 为 Provider 冲突错误增加更可读输出**

至少在错误信息中包含：

- Provider id
- `referenced_by_gateway_ids`

**Step 4: 运行 CLI 测试**

Run: `cargo test -q -p fluxctl`

Expected: CLI 测试通过

### Task 7: 为原生端删除流程补测试

**Files:**
- Modify: `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`

**Step 1: 写 Provider / Gateway 删除结果与错误处理测试**

覆盖：

- Gateway 删除返回体解码
- Gateway 删除提示文案优先使用 `user_notice`
- Provider 删除冲突错误的可展示文案

**Step 2: 写列表删除入口状态测试**

覆盖：

- 提交中禁用删除按钮
- 删除动作与现有 Configure / Edit / Start / Stop 共存

**Step 3: 运行原生端测试确认失败**

Run: `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`

Expected: 新增删除相关测试失败

### Task 8: 实现原生端删除 API 与工作台交互

**Files:**
- Modify: `apps/desktop-macos-native/FluxDeckNative/Networking/AdminApiClient.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative/Features/ProviderListView.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative/Features/GatewayListView.swift`

**Step 1: 在 `AdminApiClient` 增加删除接口与结果模型**

新增：

- `deleteProvider(id:)`
- `deleteGateway(id:)`
- Gateway 删除结果解码结构

**Step 2: 在 `ContentView` 增加删除状态与确认流**

要求：

- Provider / Gateway 删除前弹确认
- 成功后刷新资源列表
- 清理编辑状态
- 设置 `operationNotice` / `loadError`

**Step 3: 在列表卡片中增加 `Delete` 入口**

要求：

- 与现有按钮并列
- 提交中禁用
- 文案清晰区分 Provider / Gateway 语义

**Step 4: 运行原生端测试**

Run: `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`

Expected: 原生端测试通过

### Task 9: 更新契约与运行文档

**Files:**
- Modify: `docs/contracts/admin-api-v1.md`
- Modify: `docs/ops/local-runbook.md`
- Modify: `apps/desktop-macos-native/README.md`

**Step 1: 更新 Admin API 契约**

补充：

- `DELETE /admin/providers/{id}`
- `DELETE /admin/gateways/{id}`
- `409` Provider 冲突响应结构
- Gateway 删除结果字段说明

**Step 2: 更新本地运行手册**

补充：

- `fluxctl provider delete <id>`
- `fluxctl gateway delete <id>`
- `-y` / `--yes` 用法

**Step 3: 更新原生端 README**

补充：

- 原生工作台支持 Provider / Gateway 删除
- Provider 与 Gateway 删除的确认语义

### Task 10: 全量验证、文档整理与工作区清理

**Files:**
- Create: `docs/progress/2026-03-12-provider-gateway-delete.md`

**Step 1: 运行后端与 CLI 测试**

Run: `cargo test -q`

Expected: Rust 测试通过

**Step 2: 运行原生端测试**

Run: `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`

Expected: 原生端测试通过

**Step 3: 记录进度文档**

写入：

- 已实现范围
- 验证命令
- 已知限制

**Step 4: 整理 git 状态**

Run: `git status --short --branch`

Expected: 仅包含本次代码与文档变更，以及工作区原有未提交内容
