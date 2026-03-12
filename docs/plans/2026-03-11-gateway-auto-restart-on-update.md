# Gateway Auto Restart On Update Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 当运行中的 Gateway 在保存编辑后确实发生配置变化时，由 `fluxd` 自动执行 `stop -> start`，并让原生桌面端 UI 与 `fluxctl` 明确提示用户。

**Architecture:** 将“是否需要自动重启”的判断和执行收敛到 `fluxd` 的 `PUT /admin/gateways/{id}` 路径中，返回一个带 `gateway/runtime_status/last_error/restart_performed/config_changed/user_notice` 的结果对象。原生桌面端与 `fluxctl` 只消费该结果并显示提示，避免多客户端重复实现运行态逻辑。

**Tech Stack:** Rust, axum, sqlx, SwiftUI, XCTest, clap

---

### Task 1: 为 `fluxd` Gateway 更新结果建立回归测试

**Files:**
- Modify: `crates/fluxd/tests/admin_api_test.rs`

**Step 1: 写失败测试，覆盖运行中 Gateway 更新后自动重启**

新增测试：

- 创建 provider 与 gateway
- 启动 gateway
- 对运行中的 gateway 执行 `PUT /admin/gateways/{id}`，修改 `listen_host` 或 `listen_port`
- 断言返回 JSON 包含：
  - `restart_performed = true`
  - `config_changed = true`
  - `runtime_status = "running"`
  - `user_notice` 非空

**Step 2: 写失败测试，覆盖运行中但无变化时不自动重启**

新增测试：

- 启动 gateway
- 使用与现有配置完全一致的 payload 调用 `PUT`
- 断言：
  - `restart_performed = false`
  - `config_changed = false`

**Step 3: 写失败测试，覆盖停止态更新时不自动重启**

新增测试：

- 保持 gateway 未启动
- 执行 `PUT`
- 断言：
  - `restart_performed = false`
  - `runtime_status = "stopped"`

**Step 4: 运行测试，确认先失败**

Run: `cargo test -p fluxd admin_api_ --test admin_api_test -q`

Expected: FAIL，提示返回结构缺少 `restart_performed` / `config_changed` 或行为未触发。

### Task 2: 在 `fluxd` 中实现按需自动重启

**Files:**
- Modify: `crates/fluxd/src/http/admin_routes.rs`
- Modify: `crates/fluxd/src/domain/gateway.rs`（如需增加可比较输入结构）

**Step 1: 定义 Gateway 更新结果结构**

实现一个稳定返回对象，例如：

```rust
#[derive(Debug, Serialize)]
struct GatewayUpdateResult {
    gateway: Gateway,
    runtime_status: String,
    last_error: Option<String>,
    restart_performed: bool,
    config_changed: bool,
    user_notice: Option<String>,
}
```

**Step 2: 在 `update_gateway` 中先读取旧配置并计算是否变化**

最小实现：

- `get_by_id`
- 比较旧配置与 `UpdateGatewayInput`
- 获取更新前运行态

**Step 3: 在更新成功后对运行中的已变更 Gateway 自动执行 `stop -> start`**

实现逻辑：

- `was_running && config_changed` 时
  - `stop_gateway`
  - `start_gateway`
- 填充 `restart_performed`
- 生成 `user_notice`

**Step 4: 若自动重启失败，保留持久化结果并返回错误提示**

实现逻辑：

- Gateway 配置已写入数据库
- `last_error` 返回运行态错误
- `user_notice` 指明“配置已保存，但自动重启失败”

**Step 5: 运行测试，确认通过**

Run: `cargo test -p fluxd admin_api_ --test admin_api_test -q`

Expected: PASS

### Task 3: 更新 `fluxctl` 消费新结果对象

**Files:**
- Modify: `crates/fluxctl/src/main.rs`
- Modify: `crates/fluxctl/tests/cli_smoke_test.rs`

**Step 1: 写失败测试，覆盖 gateway update 输出的新语义**

为 CLI 结果结构增加测试，至少覆盖：

- 解析 `gateway update` 命令仍稳定
- 新增更新结果对象序列化/打印路径不会破坏现有输出

如需补独立单测，可在 `crates/fluxctl/tests/` 中新增专门测试文件。

**Step 2: 在 `gateway update` 分支中解码并打印更新结果**

实现内容：

- 打印完整 JSON
- 若 `user_notice` 存在，追加打印一行提示

**Step 3: 运行测试**

Run: `cargo test -p fluxctl -q`

Expected: PASS

### Task 4: 更新原生桌面端 Admin API 模型与提示文案

**Files:**
- Modify: `apps/desktop-macos-native/FluxDeckNative/Networking/AdminApiClient.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift`
- Test: `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`

**Step 1: 写失败测试，覆盖新的 Gateway 更新结果解码**

新增测试：

- 构造包含 `gateway/restart_performed/config_changed/user_notice` 的 JSON
- 断言原生端可正确解码

**Step 2: 写失败测试，覆盖提示文案派生**

新增测试：

- `restart_performed = false` -> “Gateway 配置已保存”
- `restart_performed = true` -> “Gateway 配置已保存，运行中的实例已自动重启”
- `last_error != nil` -> “配置已保存，但自动重启失败…”

**Step 3: 更新 `AdminApiClient.updateGateway` 返回类型**

实现内容：

- 新增 `AdminGatewayUpdateResult`
- `updateGateway` 改为返回更新结果对象

**Step 4: 在 `ContentView.updateGateway` 中根据结果设置提示**

最小实现：

- 关闭弹窗
- 清理 `loadError`
- 刷新资源
- 将成功提示保存到一个轻量状态（例如 `operationNotice`）
- 修改 `GatewayFormSheet` 中旧的“手动 stop/start”文案

**Step 5: 运行原生测试**

Run: `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`

Expected: PASS

### Task 5: 更新契约和运行文档

**Files:**
- Modify: `docs/contracts/admin-api-v1.md`
- Modify: `docs/ops/local-runbook.md`
- Modify: `docs/USAGE.md`
- Modify: `docs/progress/2026-03-11-anthropic-base-url-normalization.md`（如需补串联说明）
- Create: `docs/progress/2026-03-11-gateway-auto-restart-on-update.md`

**Step 1: 更新 Admin API 契约**

补充：

- `PUT /admin/gateways/{id}` 新返回结构
- 自动重启触发条件

**Step 2: 更新运行手册与使用说明**

补充：

- 运行中的 Gateway 保存后会自动重启
- 未运行实例仅保存配置，不会启动

**Step 3: 记录开发日志**

说明：

- 根因
- 行为变更
- 验证命令

### Task 6: 运行闭环验证并整理工作区

**Files:**
- Modify: 无

**Step 1: 运行后端测试**

Run: `cargo test -p fluxd admin_api_ --test admin_api_test -q`

Expected: PASS

**Step 2: 运行 CLI 测试**

Run: `cargo test -p fluxctl -q`

Expected: PASS

**Step 3: 运行原生测试**

Run: `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`

Expected: PASS

**Step 4: 整理 git 状态**

Run: `git status --short --branch`

Expected: 只出现本次任务相关变更
