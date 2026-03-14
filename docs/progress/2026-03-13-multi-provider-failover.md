# 2026-03-13 多 Provider 健康管理与故障切流设计记录

## 本轮完成

- 基于当前仓库实现确认：Gateway 仍为单 `default_provider_id` 模型
- 明确了一阶段方案采用：
  - 有序链路
  - 主被动结合健康管理
  - 冷却后回切
- 输出设计稿：
  - `docs/plans/active/2026-03-13-multi-provider-failover-design.md`
- 输出实施计划：
  - `docs/plans/active/2026-03-13-multi-provider-failover.md`

## 关键设计决策

- 不把多 Provider 链路继续塞进 `protocol_config_json`
- 显式新增 `gateway_route_targets`
- 显式新增 `provider_health_states`
- 运行时引入 `RouteSelector + ProviderHealthService + HealthMonitor`
- Admin API、`fluxctl`、原生端统一暴露 route targets、健康状态和 active provider

## 已记录技术债务

- 保留 `gateways.default_provider_id` 作为兼容字段
- 健康状态一阶段按 Provider 全局维度维护
- 一阶段不保留健康历史事件表
- 一阶段不做权重路由、并发赛马、按模型条件路由
- 原生端一阶段使用“上下移动”而不是拖拽排序

## 下一步

- 当前阶段性提交已完成，后续按 Phase 2 计划继续补齐：
  - Task 13：真实主动探测、冷却窗口、退避策略
  - Task 14：健康状态细化到更小粒度
  - Task 15：原生端链路与健康视图闭环

## 实施进展

### Task 1 已完成：migration 与数据兼容层

- 新增 `crates/fluxd/migrations/007_gateway_route_targets.sql`
- 新增 `crates/fluxd/migrations/008_provider_health_states.sql`
- `run_migrations` 改为使用显式 `static MIGRATOR`
- 新增回归测试，验证历史 `default_provider_id` 升级后会回填 `priority = 0` 的 route target

验证：

- `cargo test -q -p fluxd --test storage_migration_test migration_backfills_gateway_route_targets_from_default_provider`
- `cargo test -q -p fluxd --test storage_migration_test`

### Task 2 已完成：基础领域模型与 Provider 引用检查

- 新增 `GatewayRouteTarget`
- 新增 `ProviderHealthState`
- 新增 `gateway_route_repo.rs`
- 新增 `provider_health_repo.rs`
- `ProviderRepo.list_gateway_ids_referencing` 已覆盖 `gateway_route_targets`
- 新增回归测试，验证被 route target 引用的 Provider 删除会被服务层拒绝

验证：

- `cargo test -q -p fluxd --test provider_service_test delete_provider_rejects_gateway_route_target_reference`
- `cargo test -q -p fluxd --test provider_service_test`

### Task 3 已完成：Gateway Admin API 持久化 route targets

- `Gateway` / `CreateGatewayInput` / `UpdateGatewayInput` 已加入 `route_targets`
- `GatewayRepo.create/get_by_id/update/list/delete` 已同步管理 `gateway_route_targets`
- 旧请求只传 `default_provider_id` 时，服务端会自动生成单条 `priority = 0` 的默认 target
- `default_provider_id` 继续回写为第一条启用 target 的 provider，用于兼容旧客户端
- Admin API 契约文档已更新 `route_targets` 字段与兼容语义

验证：

- `cargo test -q -p fluxd --test admin_api_test admin_api_persists_gateway_route_targets`
- `cargo test -q -p fluxd --test admin_api_test`

### Task 4 已完成：Provider 健康状态机服务

- 新增 `provider_health_service.rs`
- `provider_health_repo.rs` 已支持 `upsert`
- 当前已落最小状态机：
  - 连续失败三次进入 `unhealthy`
  - 探测成功进入 `probing`
  - 连续成功两次从 `probing` 恢复到 `healthy`

验证：

- `cargo test -q -p fluxd --test provider_health_service_test`

### Task 5 当前进展：RouteSelector 与故障切流主路径

- 新增 `crates/fluxd/src/forwarding/route_selector.rs`
- `TargetResolver` 已切到 `RouteSelector`
- OpenAI direct forwarding 已支持：
  - 按 route target 顺序选路
  - 跳过 `unhealthy` provider
  - 网络错误 / `429` / `5xx` 时切到下一个 provider
  - 成功 / 失败结果回写 `ProviderHealthService`
- OpenAI passthrough fallback 已支持相同的顺序切流语义
- Anthropic `/v1/messages` 已支持相同的请求级顺序切流语义
  - 首个 provider 返回网络错误 / `429` / `5xx` 时，会切到下一个 provider
  - 成功 / 失败结果会回写 `ProviderHealthService`

已补回归测试：

- `crates/fluxd/tests/route_selector_test.rs`
- `crates/fluxd/tests/openai_forwarding_test.rs`
- `crates/fluxd/tests/openai_passthrough_fallback_test.rs`

验证：

- `cargo test -q -p fluxd --test route_selector_test`
- `cargo test -q -p fluxd --test openai_forwarding_test`
- `cargo test -q -p fluxd --test openai_passthrough_fallback_test`
- `cargo test -q -p fluxd --test anthropic_forwarding_test`

### Task 11 已完成：Anthropic `count_tokens` 请求级 failover

- `count_tokens_handler` 已改为复用 ordered candidates，而不是单 target 直连
- Anthropic native upstream 与 OpenAI-compatible upstream 两条 `count_tokens` 路径现在都支持：
  - 网络错误时顺序切到下一个 provider
  - `429` / `5xx` 时顺序切到下一个 provider
  - 成功 / 失败结果回写 `ProviderHealthService`
- 新增回归测试 `anthropic_count_tokens_fail_over_to_next_provider_on_upstream_5xx`
- 当前仍未补 `failover_performed / route_attempt_count / provider_id_initial` 之类额外观测字段，这部分继续放在 Task 12

验证：

- `cargo test -q -p fluxd --test anthropic_forwarding_test anthropic_count_tokens_fail_over_to_next_provider_on_upstream_5xx`
  - 初次运行：FAIL，观察到首个 provider `500` 后未切流
  - 实现后再次运行：PASS
- `cargo test -q -p fluxd --test anthropic_forwarding_test --test anthropic_count_tokens_test`
  - `anthropic_forwarding_test`：`12 passed`
  - `anthropic_count_tokens_test`：`5 passed`

### Task 12 已完成：failover 观测字段与日志维度

- `request_logs` 已新增：
  - `failover_performed`
  - `route_attempt_count`
  - `provider_id_initial`
- `RequestLogService` 已把上述字段作为稳定列写入，而不是继续拼进 `error` 文本
- `GET /admin/logs` 已返回这 3 个字段，Admin API 契约文档已同步更新
- 当前已覆盖的请求级切流日志路径：
  - OpenAI direct forwarding
  - Anthropic `/v1/messages`
  - Anthropic `/v1/messages/count_tokens`
  - OpenAI passthrough fallback

验证：

- `cargo test -q -p fluxd --test storage_migration_test migration_adds_request_log_forwarding_columns`
  - PASS
- `cargo test -q -p fluxd --test request_log_service_test`
  - PASS
- `cargo test -q -p fluxd --test admin_api_test admin_api_response_shape_is_stable`
  - PASS
- `cargo test -q -p fluxd --test openai_forwarding_test`
  - PASS
- `cargo test -q -p fluxd --test openai_passthrough_fallback_test fails_over_to_backup_provider_for_openai_passthrough_fallback`
  - PASS
- `cargo test -q -p fluxd --test anthropic_forwarding_test anthropic_messages_fail_over_to_next_provider_on_upstream_5xx`
  - PASS
- `cargo test -q -p fluxd --test anthropic_forwarding_test anthropic_count_tokens_fail_over_to_next_provider_on_upstream_5xx`
  - PASS

### Task 13 已完成：`HealthMonitor` 真实主动探测

- `HealthMonitor` 不再直接把 `unhealthy` 推到 `probing`
- 当前已落真实主动探测闭环：
  - 仅在 `recover_after` 到期后才对 `unhealthy` Provider 发起 probe
  - probe 成功会把全局状态推进到 `probing`
  - probe 失败会保持 `unhealthy`，并基于 `failure_streak` 延长下一次 `recover_after`
- 当前 probe 采用对 `provider.base_url` 的轻量 HTTP GET：
  - `429` / `5xx` 视为 probe 失败
  - 其他 HTTP 状态（例如 `401`）视为 upstream 可达

验证：

- `cargo test -q -p fluxd --test gateway_manager_test`

### Task 14 已完成：健康状态细化到 Gateway 作用域

- 新增 `crates/fluxd/migrations/010_provider_health_scope.sql`
- `provider_health_states` 已升级为：
  - `global`
  - `gateway_provider`
  - `model` 字段预留
- `ProviderHealthRepo / ProviderHealthService / RouteSelector` 已支持 Gateway 级快照读取与回写
- 请求路径健康回写已切到 Gateway 作用域：
  - OpenAI direct forwarding
  - OpenAI passthrough fallback
  - Anthropic `/v1/messages`
  - Anthropic `/v1/messages/count_tokens`
- `GET /admin/gateways` 现在会基于 Gateway 级健康状态返回：
  - `route_targets[*].health_status`
  - `route_targets[*].last_failure_reason`
  - `active_provider_id`
  - `health_summary`

验证：

- `cargo test -q -p fluxd --test provider_health_service_test`
- `cargo test -q -p fluxd --test route_selector_test`
- `cargo test -q -p fluxd --test admin_api_test admin_api_exposes_gateway_health_summary_and_active_provider`
- `cargo test -q -p fluxd --test openai_forwarding_test`
- `cargo test -q -p fluxd --test openai_passthrough_fallback_test`
- `cargo test -q -p fluxd --test anthropic_forwarding_test --test anthropic_count_tokens_test`

### Task 15 已完成：原生端链路与健康视图最小闭环

- `apps/desktop-macos-native` 已补：
  - `AdminApiClient`：解码 `route_targets`、`active_provider_id`、`health_summary`、Provider health，并新增 manual probe API
  - `ProviderListView`：展示 Provider health / 最近失败原因，并支持 manual probe
  - `GatewayListView`：展示 route target 顺序、active provider、health summary
  - `GatewayFormSheet`：保存时保留既有 `route_targets`，默认 Provider 改动会同步第一跳 target
- 当前仍保留的 UI 技术债：
  - 原生端尚未提供完整的 route target 排序编辑器，只做到“展示 + 保留 + 同步第一跳”

验证：

- `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -destination 'platform=macOS'`

### 当前剩余缺口

- Task 7 已完成最小 CLI 闭环：
  - `fluxctl gateway create/update` 已支持重复 `--route-target provider_id:priority[:enabled]`
  - `fluxctl provider health list` 已接入 `GET /admin/providers/health`
  - `fluxctl provider probe <id>` 已接入 `POST /admin/providers/{id}/probe`
- Task 6 已完成最小闭环：
  - 新增 `GET /admin/providers/health`
  - 新增 `POST /admin/providers/{id}/probe`
  - `fluxd` 启动时会拉起后台 `HealthMonitor`
- 为兼容 `provider_health_states -> providers` 外键约束，Provider 删除路径已调整为先删健康快照、再删 Provider 实体
- 当前仍保留的技术债：
  - `provider_health_states.model` 虽已入库，但还没有独立模型选路
  - 原生端 route target 编辑仍未提供完整排序交互

## Phase 2 跟踪

| Task | 内容 | 状态 | 最近说明 |
|------|------|------|----------|
| 11 | Anthropic `count_tokens` 请求级 failover | 已完成 | 已支持网络错误 / `429` / `5xx` 顺序切流，并回写 Provider 健康状态 |
| 12 | failover 观测字段与日志维度 | 已完成 | `request_logs` 与 `GET /admin/logs` 已稳定返回 3 个 failover 观测字段 |
| 13 | `HealthMonitor` 真实主动探测 | 已完成 | 已补真实 HTTP probe、冷却窗口与最小失败退避 |
| 14 | 健康状态粒度细化 | 已完成 | 已升级到 `global + gateway_provider (+ model 预留)`，请求路径改为 Gateway 级健康回写 |
| 15 | 原生端链路与健康视图 | 已完成 | Native 已支持 route targets / active provider / provider health / manual probe 的最小闭环 |

### 跟踪更新规则

- 每完成一个 Task，先更新本文件的“状态”和“最近说明”
- 若实现偏离设计稿，需要同步回填：
  - `docs/plans/active/2026-03-13-multi-provider-failover-design.md`
  - `docs/plans/active/2026-03-13-multi-provider-failover.md`
- 每个阶段结束后必须重新记录：
  - 最新验证命令
  - 是否仍存在兼容字段或技术债
