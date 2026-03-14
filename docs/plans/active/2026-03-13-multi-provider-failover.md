# Multi-Provider Failover Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为 FluxDeck Gateway 增加多 Provider 有序链路、健康管理与故障切流，并同步扩展 Admin API、`fluxctl` 和 macOS 原生桌面端。

**Architecture:** 通过新增 `gateway_route_targets` 与 `provider_health_states` 两个稳定存储结构，把“链路配置”和“健康快照”从现有单 `default_provider_id` 模式中拆开；运行时引入 `RouteSelector + ProviderHealthService + HealthMonitor`，让协议 route handler 只负责解码/编码与转发，统一通过选择器执行顺序切流和状态更新。

**Tech Stack:** Rust, Axum, SQLx(SQLite), SwiftUI, XCTest, clap

---

### Task 1: 建立 migration 与数据兼容层

**Files:**
- Create: `crates/fluxd/migrations/007_gateway_route_targets.sql`
- Create: `crates/fluxd/migrations/008_provider_health_states.sql`
- Modify: `crates/fluxd/tests/storage_migration_test.rs`
- Modify: `docs/contracts/admin-api-v1.md`

**Step 1: 写失败测试，覆盖历史 Gateway 自动回填 route target**

在 `crates/fluxd/tests/storage_migration_test.rs` 新增测试：

- 构造只包含旧 `gateways.default_provider_id` 的数据
- 跑 migration 后断言：
  - `gateway_route_targets` 存在一条 `priority = 0`
  - `provider_id = default_provider_id`

**Step 2: 运行测试确认失败**

Run: `cargo test -q -p fluxd --test storage_migration_test`

Expected:

- FAIL，提示缺少新表或缺少回填逻辑

**Step 3: 写 migration**

- 新建 `007_gateway_route_targets.sql`
- 新建 `008_provider_health_states.sql`
- 在 migration 中把历史 `default_provider_id` 回填为 `priority = 0` 的 route target

**Step 4: 再次运行测试确认通过**

Run: `cargo test -q -p fluxd --test storage_migration_test`

Expected:

- PASS

**Step 5: 更新契约文档中的 Gateway 结构说明**

- 给 `GET/POST/PUT /admin/gateways` 补 `route_targets`
- 增加 Provider 健康接口草案

**Step 6: Commit**

```bash
git add crates/fluxd/migrations/007_gateway_route_targets.sql crates/fluxd/migrations/008_provider_health_states.sql crates/fluxd/tests/storage_migration_test.rs docs/contracts/admin-api-v1.md
git commit -m "feat(fluxd): add gateway route target storage"
```

### Task 2: 增加 Repo 与领域模型

**Files:**
- Modify: `crates/fluxd/src/domain/gateway.rs`
- Create: `crates/fluxd/src/domain/provider_health.rs`
- Create: `crates/fluxd/src/repo/gateway_route_repo.rs`
- Create: `crates/fluxd/src/repo/provider_health_repo.rs`
- Modify: `crates/fluxd/src/repo/mod.rs`
- Modify: `crates/fluxd/src/repo/provider_repo.rs`
- Test: `crates/fluxd/tests/provider_service_test.rs`

**Step 1: 写失败测试，覆盖 Provider 被 route target 引用时拒绝删除**

在 `crates/fluxd/tests/provider_service_test.rs` 新增测试：

- 建 Provider
- 建 Gateway 与 route target
- 调用删除 Provider
- 断言返回 `ReferencedByGateways`

**Step 2: 运行测试确认失败**

Run: `cargo test -q -p fluxd --test provider_service_test`

Expected:

- FAIL，仍只按 `default_provider_id` 检查引用

**Step 3: 扩展领域模型与 Repo**

- 在 `domain/gateway.rs` 增加 `GatewayRouteTarget`
- 新增 `provider_health.rs`
- 新增 `GatewayRouteRepo`
- 新增 `ProviderHealthRepo`
- 更新 `ProviderRepo` 引用检查逻辑

**Step 4: 再次运行测试确认通过**

Run: `cargo test -q -p fluxd --test provider_service_test`

Expected:

- PASS

**Step 5: Commit**

```bash
git add crates/fluxd/src/domain/gateway.rs crates/fluxd/src/domain/provider_health.rs crates/fluxd/src/repo/gateway_route_repo.rs crates/fluxd/src/repo/provider_health_repo.rs crates/fluxd/src/repo/mod.rs crates/fluxd/src/repo/provider_repo.rs crates/fluxd/tests/provider_service_test.rs
git commit -m "feat(fluxd): model gateway route targets and provider health"
```

### Task 3: 扩展 Admin API Gateway 契约与写入路径

**Files:**
- Modify: `crates/fluxd/src/http/admin_routes.rs`
- Modify: `crates/fluxd/src/http/dto.rs`
- Modify: `crates/fluxd/src/domain/gateway.rs`
- Modify: `crates/fluxd/src/repo/gateway_repo.rs`
- Test: `crates/fluxd/tests/admin_api_test.rs`
- Modify: `docs/USAGE.md`
- Modify: `docs/ops/local-runbook.md`

**Step 1: 写失败测试，覆盖 Gateway create/update 返回 route targets**

在 `crates/fluxd/tests/admin_api_test.rs` 新增测试：

- `POST /admin/gateways` 传 `route_targets`
- `GET /admin/gateways` 断言返回扩展字段
- 兼容只传 `default_provider_id` 的旧请求

**Step 2: 运行测试确认失败**

Run: `cargo test -q -p fluxd --test admin_api_test`

Expected:

- FAIL，响应里没有 `route_targets`

**Step 3: 实现 Admin API 扩展**

- 扩展 `CreateGatewayInput` / `UpdateGatewayInput`
- 在 create/update 时写 `gateway_route_targets`
- 返回 `route_targets`
- 保持 `default_provider_id` 向后兼容

**Step 4: 再次运行测试确认通过**

Run: `cargo test -q -p fluxd --test admin_api_test`

Expected:

- PASS

**Step 5: 更新运行文档**

- 在 `docs/USAGE.md` 增加多 route target 的示例
- 在 `docs/ops/local-runbook.md` 说明旧字段兼容与新健康接口

**Step 6: Commit**

```bash
git add crates/fluxd/src/http/admin_routes.rs crates/fluxd/src/http/dto.rs crates/fluxd/src/domain/gateway.rs crates/fluxd/src/repo/gateway_repo.rs crates/fluxd/tests/admin_api_test.rs docs/USAGE.md docs/ops/local-runbook.md
git commit -m "feat(admin): expose gateway route targets"
```

### Task 4: 实现 Provider 健康状态机

**Files:**
- Create: `crates/fluxd/src/service/provider_health_service.rs`
- Modify: `crates/fluxd/src/service/mod.rs`
- Test: `crates/fluxd/tests/provider_health_service_test.rs`
- Modify: `docs/contracts/admin-api-v1.md`

**Step 1: 写失败测试，覆盖失败摘除、探测恢复与冷却回切**

在 `crates/fluxd/tests/provider_health_service_test.rs` 新增测试：

- 连续失败三次进入 `unhealthy`
- 探测成功后进入 `probing`
- 连续成功达到阈值进入 `healthy`
- `recover_after` 未到时不允许回切

**Step 2: 运行测试确认失败**

Run: `cargo test -q -p fluxd --test provider_health_service_test`

Expected:

- FAIL，服务不存在

**Step 3: 写最小实现**

- 实现 `record_failure`
- 实现 `record_success`
- 实现 `mark_probe_result`
- 用固定阈值先跑通状态机

**Step 4: 再次运行测试确认通过**

Run: `cargo test -q -p fluxd --test provider_health_service_test`

Expected:

- PASS

**Step 5: Commit**

```bash
git add crates/fluxd/src/service/provider_health_service.rs crates/fluxd/src/service/mod.rs crates/fluxd/tests/provider_health_service_test.rs docs/contracts/admin-api-v1.md
git commit -m "feat(fluxd): add provider health state machine"
```

### Task 5: 实现 RouteSelector 与顺序故障切流

**Files:**
- Create: `crates/fluxd/src/forwarding/route_selector.rs`
- Modify: `crates/fluxd/src/forwarding/mod.rs`
- Modify: `crates/fluxd/src/forwarding/executor.rs`
- Modify: `crates/fluxd/src/http/openai_routes.rs`
- Modify: `crates/fluxd/src/http/anthropic_routes.rs`
- Modify: `crates/fluxd/src/http/passthrough.rs`
- Test: `crates/fluxd/tests/route_selector_test.rs`
- Test: `crates/fluxd/tests/openai_forwarding_test.rs`
- Test: `crates/fluxd/tests/anthropic_forwarding_test.rs`
- Test: `crates/fluxd/tests/openai_passthrough_fallback_test.rs`

**Step 1: 写失败测试，覆盖按顺序跳过 unhealthy target**

在 `crates/fluxd/tests/route_selector_test.rs` 新增测试：

- `provider_a` 不健康
- `provider_b` 健康
- 断言选择 `provider_b`

**Step 2: 写失败集成测试，覆盖请求内 failover**

在 forwarding 集成测试里增加：

- 第一个 mock upstream 返回 `502`
- 第二个 mock upstream 返回 `200`
- 断言最终响应成功且日志标记了 failover

**Step 3: 运行测试确认失败**

Run: `cargo test -q -p fluxd --test route_selector_test`

Run: `cargo test -q -p fluxd --test openai_forwarding_test`

Expected:

- FAIL，仍然只会命中单个 provider

**Step 4: 实现选择器与重试路径**

- `TargetResolver` 升级/迁移到 `RouteSelector`
- route handler 捕获可切流错误后尝试下一个 target
- 成功/失败都回写 `ProviderHealthService`

**Step 5: 再次运行测试确认通过**

Run: `cargo test -q -p fluxd --test route_selector_test`

Run: `cargo test -q -p fluxd --test openai_forwarding_test`

Run: `cargo test -q -p fluxd --test anthropic_forwarding_test`

Run: `cargo test -q -p fluxd --test openai_passthrough_fallback_test`

Expected:

- PASS

**Step 6: Commit**

```bash
git add crates/fluxd/src/forwarding/route_selector.rs crates/fluxd/src/forwarding/mod.rs crates/fluxd/src/forwarding/executor.rs crates/fluxd/src/http/openai_routes.rs crates/fluxd/src/http/anthropic_routes.rs crates/fluxd/src/http/passthrough.rs crates/fluxd/tests/route_selector_test.rs crates/fluxd/tests/openai_forwarding_test.rs crates/fluxd/tests/anthropic_forwarding_test.rs crates/fluxd/tests/openai_passthrough_fallback_test.rs
git commit -m "feat(fluxd): add ordered failover routing"
```

### Task 6: 增加后台主动探测与健康 Admin API

**Files:**
- Create: `crates/fluxd/src/runtime/health_monitor.rs`
- Modify: `crates/fluxd/src/runtime/mod.rs`
- Modify: `crates/fluxd/src/main.rs`
- Modify: `crates/fluxd/src/http/admin_routes.rs`
- Test: `crates/fluxd/tests/gateway_manager_test.rs`
- Test: `crates/fluxd/tests/admin_api_test.rs`

**Step 1: 写失败测试，覆盖 Provider probe 接口与恢复状态变化**

在 `crates/fluxd/tests/admin_api_test.rs` 新增：

- `POST /admin/providers/{id}/probe`
- `GET /admin/providers/health`
- 断言状态快照更新

**Step 2: 运行测试确认失败**

Run: `cargo test -q -p fluxd --test admin_api_test`

Expected:

- FAIL，接口不存在

**Step 3: 实现后台探测与接口**

- 启动 `HealthMonitor`
- 增加 Admin API 健康读取与手动 probe

**Step 4: 再次运行测试确认通过**

Run: `cargo test -q -p fluxd --test admin_api_test`

Expected:

- PASS

**Step 5: Commit**

```bash
git add crates/fluxd/src/runtime/health_monitor.rs crates/fluxd/src/runtime/mod.rs crates/fluxd/src/main.rs crates/fluxd/src/http/admin_routes.rs crates/fluxd/tests/gateway_manager_test.rs crates/fluxd/tests/admin_api_test.rs
git commit -m "feat(fluxd): add provider health monitoring"
```

### Task 7: 扩展 `fluxctl`

**Files:**
- Modify: `crates/fluxctl/src/cli.rs`
- Modify: `crates/fluxctl/src/main.rs`
- Test: `crates/fluxctl/tests/cli_smoke_test.rs`
- Modify: `docs/USAGE.md`
- Modify: `docs/ops/local-runbook.md`

**Step 1: 写失败测试，覆盖 `--route-target` 参数解析**

在 `crates/fluxctl/tests/cli_smoke_test.rs` 新增测试：

- `gateway create --route-target provider_a:0 --route-target provider_b:1`
- `provider health list`
- `provider probe provider_a`

**Step 2: 运行测试确认失败**

Run: `cargo test -q -p fluxctl --test cli_smoke_test`

Expected:

- FAIL，参数或命令不存在

**Step 3: 实现 CLI 与请求序列化**

- 扩展 `gateway create/update`
- 增加 `provider health list/probe`

**Step 4: 再次运行测试确认通过**

Run: `cargo test -q -p fluxctl --test cli_smoke_test`

Expected:

- PASS

**Step 5: Commit**

```bash
git add crates/fluxctl/src/cli.rs crates/fluxctl/src/main.rs crates/fluxctl/tests/cli_smoke_test.rs docs/USAGE.md docs/ops/local-runbook.md
git commit -m "feat(fluxctl): manage gateway route targets and provider health"
```

### Task 8: 扩展原生端 Admin API 模型与 Gateway 配置页

**Files:**
- Modify: `apps/desktop-macos-native/FluxDeckNative/Networking/AdminApiClient.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative/Features/ResourceWorkspaceModels.swift`
- Test: `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`
- Modify: `docs/contracts/admin-api-v1.md`

**Step 1: 写失败测试，覆盖 route target 解码与 Gateway 表单派生**

在原生端测试中新增：

- `AdminGateway` 可解码 `route_targets`、`active_provider_id`
- Gateway 表单在多 provider 下生成 route target 列表
- 未知 provider id 的兼容显示

**Step 2: 运行测试确认失败**

Run: `env HOME=/tmp xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -destination 'platform=macOS' -derivedDataPath /tmp/fluxdeck-native-derived-route-editor -quiet`

Expected:

- FAIL，模型字段或 UI 派生逻辑缺失

**Step 3: 实现解码与 Gateway route target 编辑器**

- `Default Provider` picker 改为 `Route Targets`
- 支持上下移动、启停与删除
- summary card 展示 active provider 与链路摘要

**Step 4: 再次运行测试确认通过**

Run: `env HOME=/tmp xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -destination 'platform=macOS' -derivedDataPath /tmp/fluxdeck-native-derived-route-editor -quiet`

Expected:

- PASS

**Step 5: Commit**

```bash
git add apps/desktop-macos-native/FluxDeckNative/Networking/AdminApiClient.swift apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift apps/desktop-macos-native/FluxDeckNative/Features/ResourceWorkspaceModels.swift apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift docs/contracts/admin-api-v1.md
git commit -m "feat(native): add gateway route target editor"
```

### Task 9: 扩展原生端 Provider/Gateway 健康展示与拓扑

**Files:**
- Modify: `apps/desktop-macos-native/FluxDeckNative/Features/ProviderListView.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative/Features/GatewayListView.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative/Features/OverviewModels.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative/Features/TopologyModels.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative/Features/ConnectionsView.swift`
- Test: `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`
- Modify: `README.md`

**Step 1: 写失败测试，覆盖健康摘要与配置链路展示**

新增测试：

- Provider 卡片显示健康状态
- Gateway 卡片显示 active provider 与 unhealthy 数量
- Topology 同时反映配置链路和观测链路

**Step 2: 运行测试确认失败**

Run: `env HOME=/tmp xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -destination 'platform=macOS' -derivedDataPath /tmp/fluxdeck-native-derived-health-view -quiet`

Expected:

- FAIL，展示模型未覆盖新字段

**Step 3: 实现 UI 展示**

- 更新资源卡片
- 更新 Overview 指标
- 更新 Topology 与 Connections

**Step 4: 再次运行测试确认通过**

Run: `env HOME=/tmp xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -destination 'platform=macOS' -derivedDataPath /tmp/fluxdeck-native-derived-health-view -quiet`

Expected:

- PASS

**Step 5: 更新 README**

- 增加多 Provider Gateway 与健康切流能力说明

**Step 6: Commit**

```bash
git add apps/desktop-macos-native/FluxDeckNative/Features/ProviderListView.swift apps/desktop-macos-native/FluxDeckNative/Features/GatewayListView.swift apps/desktop-macos-native/FluxDeckNative/Features/OverviewModels.swift apps/desktop-macos-native/FluxDeckNative/Features/TopologyModels.swift apps/desktop-macos-native/FluxDeckNative/Features/ConnectionsView.swift apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift README.md
git commit -m "feat(native): surface provider health and failover topology"
```

### Task 10: 全量验证与文档收尾

**Files:**
- Modify: `docs/progress/2026-03-13-multi-provider-failover.md`
- Modify: `docs/plans/active/2026-03-13-multi-provider-failover-design.md`
- Modify: `docs/plans/active/2026-03-13-multi-provider-failover.md`

**Step 1: 运行后端测试**

Run: `cargo test -q`

Expected:

- PASS

**Step 2: 运行 e2e smoke**

Run: `./scripts/e2e/smoke.sh`

Expected:

- 输出 `smoke ok`

**Step 3: 运行原生端测试**

Run: `env HOME=/tmp xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -destination 'platform=macOS' -derivedDataPath /tmp/fluxdeck-native-derived-all -quiet`

Expected:

- PASS

**Step 4: 回填文档**

- 在 progress 文档记录实际实现偏差
- 在 design/plan 中标记完成情况与剩余债务

**Step 5: Commit**

```bash
git add docs/progress/2026-03-13-multi-provider-failover.md docs/plans/active/2026-03-13-multi-provider-failover-design.md docs/plans/active/2026-03-13-multi-provider-failover.md
git commit -m "docs: close multi-provider failover rollout"
```

---

## Phase 2 跟进计划

> 说明：以下任务不阻塞当前阶段提交，但需要持续追踪，直到“多 Provider 故障切流”具备完整可观测性和原生端闭环。

### Task 11: 补齐 Anthropic `count_tokens` 请求级 failover

**Files:**
- Modify: `crates/fluxd/src/http/anthropic_routes.rs`
- Test: `crates/fluxd/tests/anthropic_forwarding_test.rs`
- Modify: `docs/progress/2026-03-13-multi-provider-failover.md`

**状态：已完成（2026-03-13）**

**Step 1: 写失败测试，覆盖首个 Provider `5xx` 时 `count_tokens` 切到第二个 Provider**

- 已在 `crates/fluxd/tests/anthropic_forwarding_test.rs` 新增：
  - `anthropic_count_tokens_fail_over_to_next_provider_on_upstream_5xx`

**Step 2: 运行测试确认失败**

Run: `cargo test -q -p fluxd --test anthropic_forwarding_test anthropic_count_tokens_fail_over_to_next_provider_on_upstream_5xx`

- 实际结果：
  - FAIL
  - 断言显示响应状态仍为 `500`，说明 `count_tokens` 仍按单 target 处理

**Step 3: 实现最小 failover**

- 让 `count_tokens_handler` 使用 ordered candidates
- 对网络错误、`429`、`5xx` 执行顺序切流
- 回写 `ProviderHealthService`

**Step 4: 再次运行测试确认通过**

Run: `cargo test -q -p fluxd --test anthropic_forwarding_test`

- 实际结果：
  - PASS
  - 同时补跑 `cargo test -q -p fluxd --test anthropic_forwarding_test --test anthropic_count_tokens_test`
  - `anthropic_forwarding_test`: `12 passed`
  - `anthropic_count_tokens_test`: `5 passed`

**完成说明：**

- Anthropic `count_tokens` 现在与 `/v1/messages` 共用 ordered candidates 语义
- OpenAI-compatible 与 Anthropic native upstream 两条 `count_tokens` 路径都已支持请求级 failover
- Phase 2 剩余工作转入 Task 12 继续补观测字段与日志维度

### Task 12: 补 failover 观测字段与日志维度

**Files:**
- Modify: `crates/fluxd/migrations/*`
- Modify: `crates/fluxd/src/service/request_log_service.rs`
- Modify: `crates/fluxd/src/http/anthropic_routes.rs`
- Modify: `crates/fluxd/src/http/passthrough.rs`
- Modify: `crates/fluxd/src/forwarding/executor.rs`
- Modify: `docs/contracts/admin-api-v1.md`
- Modify: `docs/progress/2026-03-13-multi-provider-failover.md`

**状态：已完成（2026-03-13）**

**目标：**

- 新增 `failover_performed`
- 新增 `route_attempt_count`
- 新增 `provider_id_initial`

**完成说明：**

- 已新增 migration，把 3 个字段落到 `request_logs`
- `RequestLogService` 改为写稳定列，`GET /admin/logs` 已返回这些字段
- 已覆盖 OpenAI direct、Anthropic direct、Anthropic `count_tokens`、OpenAI passthrough 的请求级 failover 观测

**验证：**

- `cargo test -q -p fluxd --test storage_migration_test migration_adds_request_log_forwarding_columns`
- `cargo test -q -p fluxd --test request_log_service_test`
- `cargo test -q -p fluxd --test admin_api_test admin_api_response_shape_is_stable`
- `cargo test -q -p fluxd --test openai_forwarding_test`
- `cargo test -q -p fluxd --test openai_passthrough_fallback_test fails_over_to_backup_provider_for_openai_passthrough_fallback`
- `cargo test -q -p fluxd --test anthropic_forwarding_test anthropic_messages_fail_over_to_next_provider_on_upstream_5xx`
- `cargo test -q -p fluxd --test anthropic_forwarding_test anthropic_count_tokens_fail_over_to_next_provider_on_upstream_5xx`

### Task 13: 强化 `HealthMonitor` 主动探测

**Files:**
- Modify: `crates/fluxd/src/runtime/health_monitor.rs`
- Modify: `crates/fluxd/src/service/provider_health_service.rs`
- Test: `crates/fluxd/tests/gateway_manager_test.rs`
- Modify: `docs/ops/local-runbook.md`
- Modify: `docs/progress/2026-03-13-multi-provider-failover.md`

**目标：**

- 引入真实上游轻量探测
- 引入冷却窗口后的 probe 调度
- 引入最小退避策略

**结果（2026-03-14）：**

- 已完成：`HealthMonitor` 现已基于 Provider `base_url` 发起真实 HTTP 轻量探测
- 已完成：仅在 `recover_after` 到期后才会 probe，失败后会基于 failure streak 延长下一次 `recover_after`
- 已完成：`gateway_manager_test` 已覆盖真实 probe、冷却窗口与失败退避路径

### Task 14: 健康状态细化到 `gateway + provider (+ model)` 维度

**Files:**
- Modify: `crates/fluxd/migrations/*`
- Modify: `crates/fluxd/src/domain/provider_health.rs`
- Modify: `crates/fluxd/src/repo/provider_health_repo.rs`
- Modify: `crates/fluxd/src/service/provider_health_service.rs`
- Modify: `crates/fluxd/src/forwarding/route_selector.rs`
- Modify: `docs/plans/active/2026-03-13-multi-provider-failover-design.md`
- Modify: `docs/progress/2026-03-13-multi-provider-failover.md`

**目标：**

- 避免单个异常模型拖累整个 Provider
- 为更细粒度回切策略打基础

**结果（2026-03-14）：**

- 已完成：新增 `010_provider_health_scope.sql`，把 `provider_health_states` 升级为 `global + gateway_provider (+ model 预留)` 结构
- 已完成：`ProviderHealthRepo / ProviderHealthService / RouteSelector` 已支持 `gateway_provider` 作用域
- 已完成：OpenAI direct、OpenAI passthrough、Anthropic `messages`、Anthropic `count_tokens` 的健康回写均改为优先写 Gateway 级状态
- 未完成：当前 `model` 字段仍以结构预留为主，尚未做独立模型选路

### Task 15: 原生 macOS 端补齐链路与健康视图

**Files:**
- Modify: `apps/desktop-macos-native/**`
- Modify: `docs/USAGE.md`
- Modify: `docs/progress/2026-03-13-multi-provider-failover.md`

**目标：**

- 展示 route targets 顺序
- 展示 active provider / unhealthy 数量 / 最近 probe 状态
- 支持手动 probe
- 支持原生端编辑有序链路

**结果（2026-03-14）：**

- 已完成：macOS Native `AdminApiClient` 已支持 `route_targets`、`active_provider_id`、`health_summary`、Provider health、manual probe
- 已完成：Provider/Gateway 列表页已展示 route targets、active provider、health summary 与最近失败原因
- 已完成：Provider 列表页已提供 manual probe 操作
- 已完成：Gateway 编辑表单已在保存时保留既有 `route_targets`，且默认 Provider 改动会同步第一跳 target
- 未完成：原生端仍未提供完整的可视化多 target 拖拽/上下移动编辑器；当前为“保留并展示已有链路 + 同步第一跳”的最小闭环

### Phase 2 完成条件

- Anthropic `messages` 与 `count_tokens` 都具备请求级 failover
- Request logs 能明确表达切流过程
- 后台主动探测不再只是骨架
- 原生端能展示并操作多 Provider 链路与健康状态

当前结论（2026-03-14）：

- 上述完成条件已满足最小闭环版本
- 唯一保留项是原生端链路编辑器仍未做完整排序交互，这被保留为后续体验增强，不阻塞 Phase 2 收口
