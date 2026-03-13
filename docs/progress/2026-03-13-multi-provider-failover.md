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

- 按实施计划先落 migration 与数据兼容层
- 然后逐步推进 Admin API、runtime、`fluxctl`、原生端

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

### 当前剩余缺口

- Task 7 已完成最小 CLI 闭环：
  - `fluxctl gateway create/update` 已支持重复 `--route-target provider_id:priority[:enabled]`
  - `fluxctl provider health list` 已接入 `GET /admin/providers/health`
  - `fluxctl provider probe <id>` 已接入 `POST /admin/providers/{id}/probe`
- Task 6 已完成最小闭环：
  - 新增 `GET /admin/providers/health`
  - 新增 `POST /admin/providers/{id}/probe`
  - `fluxd` 启动时会拉起后台 `HealthMonitor`
  - `HealthMonitor` 当前会周期性补齐健康快照，并把 `unhealthy` Provider 推进到 `probing`
- 为兼容 `provider_health_states -> providers` 外键约束，Provider 删除路径已调整为先删健康快照、再删 Provider 实体
- Anthropic `count_tokens` 路径仍未补齐请求级 failover，目前仍按单 target 处理
- `request_logs` 还未额外增加 `failover_performed / route_attempt_count / provider_id_initial` 等新观测字段
- 后台主动探测仍是保守骨架：
  - 还没有真实上游网络探测
  - 还没有独立冷却窗口调度与探测退避
  - 还没有按 Gateway / 模型维度维护健康状态
