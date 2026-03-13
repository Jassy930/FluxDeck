# FluxDeck 多 Provider 健康管理与故障切流设计

## 目标

将当前仅支持单 `default_provider_id` 的 Gateway 扩展为支持多 Provider 有序链路，并在 `fluxd + Admin API + fluxctl + macOS 原生桌面端` 上形成一套一致的健康管理与故障切流能力。

本次设计固定采用以下决策：

- 路由模式：`有序链路`
- 健康模式：`主被动结合`
- 回切模式：`冷却后回切`

## 背景与现状

当前 `fluxd` 的 Gateway 运行时以单一 `default_provider_id` 为唯一上游目标：

- 数据模型：`gateways.default_provider_id`
- 解析逻辑：`TargetResolver.resolve(gateway_id)` 只返回一个 `ResolvedTarget`
- 运行态：仅维护 Gateway 的 `running/stopped` 与 `last_error`
- 原生端与 `fluxctl`：都只允许配置单个默认 Provider

这导致以下能力缺失：

- 不能为同一 Gateway 配置多个上游 Provider
- 不能根据健康状态自动摘除故障 Provider
- 不能在失败时按顺序切到备用 Provider
- 不能在高优先级 Provider 恢复后按冷却窗口回切
- 不能在管理端清晰展示路由链路、活跃 Provider 与健康状态

## 设计目标

### 本次纳入

- 同一 Gateway 可配置多个 Provider target
- 按优先级顺序选择 Provider
- 主被动结合的 Provider 健康管理
- 请求失败时同请求内的顺序故障切流
- 冷却后回切
- Admin API / `fluxctl` / 原生端统一暴露链路与健康信息
- 技术债务显式记录

### 本次不纳入

- 权重负载均衡
- 并发赛马
- 按模型维度独立健康状态
- 按租户或规则表达式路由
- 完整健康历史事件时间线
- 拖拽式复杂链路编辑器

## 方案对比

### 方案 A：继续把多 Provider 配置塞进 `protocol_config_json`

优点：

- migration 最少
- 能快速验证功能

缺点：

- 路由关系不可查询
- 删除 Provider、引用检查、UI 展示都要反序列化 JSON
- 路由与协议配置混杂，后续维护成本高

结论：不采用。

### 方案 B：显式建模 `Gateway Route Targets + Provider Health Runtime`

优点：

- 路由关系可查询、可测试、可展示
- 健康状态与 Provider 主配置分离
- 适合后续逐步扩展权重、模型覆盖与更复杂策略

缺点：

- 改动面覆盖 repo、runtime、Admin API、CLI、原生端

结论：本次采用。

### 方案 C：直接引入完整独立 Routing/Health Engine

优点：

- 模型最完整
- 二阶段扩展空间最大

缺点：

- 明显超出当前阶段复杂度
- 首版交付与验证成本过高

结论：暂不采用。

## 总体架构

采用“显式链路配置 + 独立健康状态 + 统一路由选择器”的结构。

### 新增核心部件

- `GatewayRouteRepo`
- `ProviderHealthRepo`
- `ProviderHealthService`
- `RouteSelector`
- `HealthMonitor`

### 分层职责

#### Types / Domain

- `Gateway`：保留主配置
- `GatewayRouteTarget`：描述 Gateway 到 Provider 的有序目标
- `ProviderHealthState`：描述 Provider 当前健康快照

#### Repo

- `GatewayRepo`：只负责 `gateways`
- `GatewayRouteRepo`：负责 `gateway_route_targets`
- `ProviderHealthRepo`：负责 `provider_health_states`

#### Service

- `ProviderHealthService`：封装状态机更新
- `GatewayConfigService`：聚合 Gateway 主配置与 route targets 的写入

#### Runtime

- `RouteSelector`：负责按顺序选路与 failover
- `HealthMonitor`：负责后台主动探测
- 协议 route handler 只负责调用选择器、发请求、回写健康结果

#### UI / CLI

- 统一消费 `route_targets`、`active_provider_id`、`health_summary`

## 数据模型设计

### 1. `gateways`

保留现有主字段：

- `id`
- `name`
- `listen_host`
- `listen_port`
- `inbound_protocol`
- `upstream_protocol`
- `protocol_config_json`
- `default_model`
- `enabled`
- `auto_start`

一阶段继续保留：

- `default_provider_id`

其语义降级为兼容字段：

- 用于兼容旧客户端与旧数据
- 服务端在写入 `route_targets` 时同步维护为第一条启用 target 的 `provider_id`
- 新运行时不再以它作为真实路由来源

### 2. 新增 `gateway_route_targets`

建议字段：

- `id TEXT PRIMARY KEY`
- `gateway_id TEXT NOT NULL`
- `provider_id TEXT NOT NULL`
- `priority INTEGER NOT NULL`
- `enabled INTEGER NOT NULL DEFAULT 1`
- `created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP`
- `updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP`

约束：

- `UNIQUE(gateway_id, priority)`
- `UNIQUE(gateway_id, provider_id)`
- `FOREIGN KEY (gateway_id) REFERENCES gateways(id)`
- `FOREIGN KEY (provider_id) REFERENCES providers(id)`

语义：

- 一个 Gateway 至少包含 1 个启用 target
- 数字越小优先级越高
- 当前版本不开放 weight、条件路由或模型级 target 覆盖

### 3. 新增 `provider_health_states`

建议字段：

- `provider_id TEXT PRIMARY KEY`
- `scope TEXT NOT NULL DEFAULT 'global'`
- `status TEXT NOT NULL`
- `failure_streak INTEGER NOT NULL DEFAULT 0`
- `success_streak INTEGER NOT NULL DEFAULT 0`
- `last_check_at TEXT`
- `last_success_at TEXT`
- `last_failure_at TEXT`
- `last_failure_reason TEXT`
- `circuit_open_until TEXT`
- `recover_after TEXT`
- `updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP`

语义：

- 当前版本健康状态先按 Provider 全局维度维护
- 不细分到 `gateway + provider + model + protocol`
- `circuit_open_until` 表示摘除窗口
- `recover_after` 表示冷却后回切的最早时间

## 兼容与迁移策略

### 历史数据迁移

新增 migration 后，对每条现存 `gateways` 记录补写一条 `gateway_route_targets`：

- `priority = 0`
- `provider_id = default_provider_id`
- `enabled = 1`

### 请求兼容

- `POST/PUT /admin/gateways` 若只传 `default_provider_id`，服务端自动生成一条 target
- 若传 `route_targets`，服务端以 `route_targets` 为准，并同步 `default_provider_id`

### 读兼容

`GET /admin/gateways` 继续返回：

- `default_provider_id`

同时新增：

- `route_targets`
- `active_provider_id`
- `health_summary`

## 健康状态机

### 状态

- `healthy`
- `degraded`
- `unhealthy`
- `probing`

### 被动失败信号

以下情况视为 Provider 健康失败信号：

- 网络连接失败
- 上游超时
- HTTP `429`
- HTTP `5xx`
- 明确的上游限流/熔断错误

以下情况默认不视为 Provider 健康失败：

- HTTP `400`
- HTTP `401`
- HTTP `403`
- HTTP `404`
- 客户端请求体校验错误
- 模型不存在或参数非法

### 主动探测

`HealthMonitor` 按 Provider 定时进行轻量探测：

- `healthy`：较长周期探测
- `unhealthy`：较短周期探测

主动探测成功：

- `unhealthy -> probing`

主动探测失败：

- 维持 `unhealthy`

### 状态流转建议

- 连续失败 `>= 3`：`healthy/degraded -> unhealthy`
- 连续成功 `>= 2`：`probing -> healthy`
- `429` 与超时可按更重失败权重处理

### 冷却后回切

高优先级 Provider 恢复后：

- 不立即抢回流量
- 进入 `probing`
- 满足连续成功阈值后进入 `healthy`
- 仅当 `recover_after <= now` 时，新请求才重新按优先级选回该 Provider

## 路由选择与故障切流

### 选择规则

一次请求到来时：

1. 读取该 Gateway 的全部 `route_targets`
2. 按 `priority` 升序排列
3. 过滤掉：
   - target `enabled = false`
   - Provider `enabled = false`
   - 处于摘除窗口内的 `unhealthy`
4. 优先选取最靠前的 `healthy`
5. 若没有 `healthy`，可退化尝试最靠前的 `degraded`
6. `probing` 在当前版本仅作为恢复过渡状态，不主动抢主流量

### 故障切流

若当前 target 返回健康失败信号：

1. 写入失败结果到 `ProviderHealthService`
2. 若状态达到摘除阈值，则标记为 `unhealthy`
3. 同一请求内继续尝试下一个 target
4. 成功后记录本次请求发生了 failover

### 当前不做

- 同优先级并发请求
- 多 target 负载均衡
- 按模型维度的健康隔离

## 后端实现设计

### Repo

新增：

- `crates/fluxd/src/repo/gateway_route_repo.rs`
- `crates/fluxd/src/repo/provider_health_repo.rs`

修改：

- `provider_repo.rs` 的 Provider 引用检查改为查询 `gateway_route_targets`
- `gateway_repo.rs` 聚焦 Gateway 主表，不再承担多 target 查询

### Runtime

新增：

- `crates/fluxd/src/runtime/health_monitor.rs`
- `crates/fluxd/src/forwarding/route_selector.rs`

替换逻辑：

- 当前 `TargetResolver.resolve(gateway_id)` 升级为 `RouteSelector.select(...)`
- route handler 成功/失败后统一调用 `ProviderHealthService`

### Request Log 扩展

建议新增观测字段：

- `route_attempt_count`
- `failover_performed`
- `provider_id_initial`
- `provider_id_final`
- `failover_reason`

当前版本即使不额外建表，也应保证请求日志能说明本次是否切流与最终命中哪个 Provider。

## Admin API 设计

### `GET /admin/gateways`

在现有字段基础上新增：

- `route_targets: GatewayRouteTarget[]`
- `active_provider_id: string | null`
- `routing_mode: "ordered_failover"`
- `health_summary: { healthy_count, degraded_count, unhealthy_count, probing_count }`

`GatewayRouteTarget` 返回字段：

- `provider_id: string`
- `priority: number`
- `enabled: boolean`
- `health_status: "healthy" | "degraded" | "unhealthy" | "probing" | "unknown"`
- `last_failure_reason: string | null`
- `circuit_open_until: string | null`
- `recover_after: string | null`

### `POST /admin/gateways`

新增请求字段：

- `route_targets: Array<{ provider_id: string, priority: number, enabled: boolean }>`

兼容规则：

- 若未传 `route_targets` 但传了 `default_provider_id`，自动生成单条 target

### `PUT /admin/gateways/{id}`

同样支持 `route_targets`，返回的 `gateway` 结构包含扩展后的链路与健康字段。

### 新增健康接口

建议新增：

- `GET /admin/providers/health`
- `POST /admin/providers/{id}/probe`

## `fluxctl` 设计

### Gateway 命令

扩展 `gateway create/update`：

- `--route-target provider_a:0`
- `--route-target provider_b:1`

### 新增命令

- `fluxctl gateway route list <gateway_id>`
- `fluxctl gateway route set <gateway_id> --route-target provider_a:0 --route-target provider_b:1`
- `fluxctl provider health list`
- `fluxctl provider probe <provider_id>`

当前版本若控制范围，也可先只扩展 `gateway create/update` 的 `--route-target` 参数。

## 原生桌面端设计

### Gateway 配置页

将当前单个 `Default Provider` picker 升级为 `Route Targets` 编辑区。

每个 target 行展示：

- Provider 名称
- 优先级
- 是否启用
- 当前健康状态
- 最近失败原因摘要

支持：

- 添加 target
- 删除 target
- 上移/下移 target
- 启用/禁用 target

### Gateway 列表页

当前单 `providerText` 改为展示：

- 配置链路摘要，例如 `provider_a -> provider_b -> provider_c`
- 当前 `active_provider_id`
- 不健康 target 数

### Provider 列表页

新增健康信息：

- 当前健康状态
- 最近失败时间/原因
- 是否处于冷却窗口
- 手动 `Probe` 操作

### Overview / Topology / Connections

新增或补充：

- `Unhealthy Providers`
- `Gateways In Failover`
- 配置链路与观测链路并列展示

## 测试策略

### Rust 单元测试

- `GatewayRouteRepo`
- `ProviderHealthService`
- `RouteSelector`

### `fluxd` 集成测试

- 单 gateway 多 provider 顺序切流
- 主动探测恢复
- 冷却后回切
- 删除被 route target 引用的 Provider
- 历史单 provider 数据兼容

### `fluxctl` 测试

- CLI 参数解析
- 请求体序列化
- 健康命令输出

### 原生端测试

- `AdminApiClient` 解码
- Gateway route target 编辑器
- Provider/Gateway 卡片状态展示
- Topology/Overview 模型派生

## 验收标准

- 一个 Gateway 可配置两个及以上 Provider target
- 失败时可按顺序切到后续 target
- 连续失败会摘除 Provider
- 主动探测可恢复 Provider
- 冷却窗口结束后可回切到高优先级 Provider
- Admin API、`fluxctl`、原生端都可查看 route targets、健康状态和活跃 Provider
- 旧单 Provider Gateway 升级后仍可工作
- 删除被引用 Provider 会被拒绝并明确返回引用关系

## 技术债务 / Deferred Work

### 兼容债务

- 一阶段保留 `gateways.default_provider_id` 作为兼容字段，后续应在旧客户端完全迁移后移除

### 精度债务

- 健康状态先按 Provider 全局维度维护，未细化到 `gateway + provider + model + protocol`

### 观测债务

- 一阶段不新增健康历史事件表，只保留最新快照与请求日志中的切流信息

### 策略债务

- 一阶段不做权重路由、并发赛马、按模型条件路由和复杂半开放量策略

### UI 债务

- 原生端一阶段使用“上下移动按钮”维护优先级，不做拖拽排序
- `Routing JSON` 与可视化链路编辑器并存，但 route target 主配置不再允许通过 JSON 自由编辑

## Phase 2 明确补完项

以下内容明确归入后续阶段追踪，不计入当前阶段性提交完成范围：

- `HealthMonitor` 真实主动探测、冷却窗口调度与退避
- 健康状态从 Provider 全局维度细化到更小作用域
- 原生 macOS 端的链路编辑、健康状态展示与手动 probe 闭环

更新（2026-03-13）：

- Anthropic `count_tokens` 请求级 failover 已在 Phase 2 跟进中补齐，不再属于未完成范围
- failover 观测字段已在 Phase 2 跟进中补齐，不再属于未完成范围

## 推荐实施顺序

1. migration 与 repo
2. Admin API 契约扩展
3. runtime 路由选择与健康状态机
4. `fluxctl` 扩展
5. 原生端 UI 与状态展示
6. 文档与验收补齐
