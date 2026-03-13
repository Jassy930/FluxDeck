# FluxDeck 架构问题调研清单

## 文档目的

本清单用于承接 2026-03-12 的仓库级架构评审结果，把需要后续逐项调查和解决的问题先固定下来。

使用方式：

- 每个问题后续单独开一份调查/设计/实施文档
- 本文档只负责问题命名、范围归类和简要支撑
- 若某个问题已进入独立处理，可在条目下补充对应文档链接

## 问题分组

### A. 后端边界与运行时

#### A1. 运行时配置快照缺失

- 名称：`runtime-config-snapshot`
- 级别：高
- 影响面：`fluxd` 数据面热路径、Gateway 扩展、运行时性能与一致性

简要支撑：

- `TargetResolver` 在请求转发时实时查询 `gateways + providers` 并解析 `protocol_config_json`
- `executor` 每条转发路径都重新构造 resolver 并查库
- Anthropic 路由还有独立的一套目标解析与配置读取逻辑
- 当前控制面配置存储与数据面运行时决策没有真正拆开

后续调查建议：

- 评估 `compiled gateway config` / `runtime snapshot` 是否作为统一运行时输入
- 明确配置更新后的刷新机制、失效机制和并发读写模型

#### A2. 协议扩展点不真实

- 名称：`protocol-extension-surface`
- 级别：高
- 影响面：新增协议、协议桥接、日志提取、测试矩阵

简要支撑：

- `ProtocolRegistry` 很薄，真实入口仍靠 runtime 的 `match inbound_protocol`
- OpenAI / Anthropic 协议逻辑分散在专门 router 中
- 新增协议仍需要同时修改 runtime、HTTP router、转发链路和测试

后续调查建议：

- 评估统一的 protocol adapter / descriptor 接口
- 区分协议入口注册、桥接能力声明、usage 提取、错误映射四类职责

#### A3. Admin API 业务编排下沉不足

- 名称：`admin-api-application-layer`
- 级别：高
- 影响面：控制面演进、API 稳定性、后续多入口复用

简要支撑：

- `admin_routes.rs` 同时承担路由、生命周期编排、配置 diff、统计 SQL 和响应拼装
- `ProviderService` 很薄，尚未形成完整 application service 层
- Gateway 更新/删除行为的核心规则仍留在 HTTP handler 内部

后续调查建议：

- 把 Gateway 生命周期管理、Admin 查询模型、统计聚合抽到 application service/use-case
- 为后续鉴权、审计、事件发布和 API versioning 预留明确落点

#### A4. Admin API 错误契约不统一

- 名称：`admin-api-error-contract`
- 级别：高
- 影响面：CLI、原生端、自动化脚本、后续 API 消费端

简要支撑：

- 某些列表接口内部失败时返回 `200 + 空列表`
- `start/stop gateway` 失败时只返回 `{ok:false}`
- `create_gateway` 失败时甚至返回伪造的 `Gateway` 对象
- 客户端很难区分“空数据”“校验错误”“内部故障”

后续调查建议：

- 定义统一 error envelope
- 为所有非 2xx 响应补上稳定错误码和机器可读字段

#### A5. Gateway 运行态模型过薄

- 名称：`gateway-runtime-state-model`
- 级别：中高
- 影响面：状态可观测性、自恢复、故障诊断、分发后稳定性

简要支撑：

- `GatewayManager` 运行状态主要保存在进程内 `HashMap`
- 子任务退出结果没有完整回收与反向同步
- `status()` 本质上只看 map 中是否存在 key

后续调查建议：

- 明确运行时状态机
- 增加 task 退出后的状态回收、错误记录和监督机制

#### A6. 日志与统计模型混在同一热表

- 名称：`request-log-observability-model`
- 级别：中高
- 影响面：日志保留、统计分析、诊断可读性、长期观测能力

简要支撑：

- `request_logs` 同时承担请求事件、日志展示和统计聚合来源
- 一些维度信息目前被拼接进 `error` 字符串
- retention 仍是简单按条数裁剪

后续调查建议：

- 评估“事件存储”和“聚合查询模型”是否拆分
- 评估是否需要更结构化的错误/维度字段与保留策略

#### A7. CLI 契约复用能力不足

- 名称：`shared-admin-contracts`
- 级别：中
- 影响面：`fluxctl`、脚本自动化、后续客户端实现

简要支撑：

- `fluxctl` 仍以 `serde_json::Value` 为主，缺少 typed response
- CLI 与服务端之间没有共享 contract crate
- 错误处理和 notice 提取较脆弱

后续调查建议：

- 评估共享 contract crate 或生成式契约产物
- 明确 CLI 是否要成为稳定自动化接口的一部分

#### A8. Provider 密钥边界过宽

- 名称：`provider-secret-boundary`
- 级别：中
- 影响面：配置安全、远程控制、审计、诊断导出

简要支撑：

- `Provider` 领域对象直接携带 `api_key`
- list/get 等标准链路会回传完整密钥字段
- 若未来边界从纯本机扩展出去，补救成本会明显增加

后续调查建议：

- 拆分可回显配置与 secret material
- 明确哪些入口允许读原始密钥，哪些只能读遮罩值

### B. 原生桌面端应用层

#### B1. 根视图状态过载

- 名称：`native-root-store-split`
- 级别：高
- 影响面：原生端功能扩展、异步编排、可测试性

简要支撑：

- `ContentView` 同时维护 providers、gateways、logs、traffic、settings 等大量状态
- 导航协调、CRUD workflow、sheet/alert、副作用刷新都集中在单个根视图
- 已经具备“超级根视图”的典型特征

后续调查建议：

- 评估 `AppStore / WorkbenchStore + feature store/view model` 方案
- 明确全局状态、页面状态和短生命周期 UI 状态的边界

#### B2. 原生端网络层单文件耦合过重

- 名称：`native-admin-client-decomposition`
- 级别：高
- 影响面：契约演进、代码维护、测试隔离

简要支撑：

- `AdminApiClient.swift` 同时包含 DTO、JSONValue、枚举、传输层、错误翻译和展示辅助函数
- 后端字段变化会同时波及 networking、表单和展示语义
- 单文件已经承担过多角色

后续调查建议：

- 拆成 `Contracts / Transport / Repository / Mapper / UI helper`
- 把传输与展示语义解耦

#### B3. 视图直接绑定后端 DTO

- 名称：`native-dto-to-viewstate-boundary`
- 级别：中高
- 影响面：原生端 UI 演进、缓存/离线、后端契约波动

简要支撑：

- 多个视图和派生模型直接消费 `AdminProvider / AdminGateway / AdminLog`
- 缺少 application model 或 adapter 层做缓冲
- 当前更像“直接渲染 Admin API 返回值”

后续调查建议：

- 引入稳定的 `ViewState` / `ScreenModel`
- 将 `Admin*` DTO 限制在 adapter 层内部

#### B4. 原生端边界测试不足

- 名称：`native-boundary-test-gap`
- 级别：中
- 影响面：请求拼装、错误处理、并发刷新、状态污染

简要支撑：

- 当前测试更多集中在纯函数模型和派生结构
- 缺少针对 `AdminApiClient` 的 URLSession 级测试
- 缺少针对 `ContentView` 异步编排与状态机的测试

后续调查建议：

- 增加 transport 层 contract test
- 增加 store/view model 级状态机测试

### C. 文档、测试与质量门禁

#### C1. 主线质量门禁不一致

- 名称：`quality-gate-realignment`
- 级别：高
- 影响面：开发流程、CI、架构调整优先级
- 状态：已于 2026-03-12 完成第一轮收敛；见 `docs/testing/quality-gates.md` 与 `docs/progress/2026-03-12-quality-gate-realignment.md`

简要支撑：

- 仓库约定已切到原生端优先
- README、USAGE、testing 文档仍把 Web 桌面验证放在主入口
- 不同文档对“什么才算通过”给出不同答案

后续调查建议：

- 建立唯一主线质量门禁
- 区分 `core-gate`、`native-release-gate` 和 legacy 检查

#### C2. 主 smoke 仍依赖暂停中的 Web 桌面

- 名称：`smoke-vs-legacy-web-coupling`
- 级别：高
- 影响面：后端演进、契约复用、E2E 稳定性
- 状态：主 `smoke.sh` 已完成解耦；遗留 Web 一致性检查已迁出到 `scripts/e2e/legacy_web_consistency.sh`

简要支撑：

- `scripts/e2e/smoke.sh` 仍调用 `validate_cli_desktop_consistency.ts`
- 该脚本直接导入 `apps/desktop/src/api/admin`
- 当前主 smoke 仍被已暂停栈绑住

后续调查建议：

- 提取共享契约夹具
- 把 Web 一致性检查从主 smoke 移出

#### C3. 原生端未进入主线验收

- 名称：`native-release-verification-gap`
- 级别：高
- 影响面：发布质量、回归风险、主产品可信度
- 状态：`ci-gate` / `release-gate` 已纳入原生端测试；仍缺少平台级自动化与 native + running fluxd 集成验证

简要支撑：

- 当前默认主线验证未覆盖 `xcodebuild test`
- 原生端 README 有独立测试命令，但没有纳入仓库主门禁
- `smoke ok` 不能代表原生壳可交付

后续调查建议：

- 把原生端测试纳入发布前必跑
- 评估增加 native + running fluxd 的集成验证

#### C4. 文档分类漂移

- 名称：`docs-information-architecture-cleanup`
- 级别：中高
- 影响面：检索效率、历史结论可信度、协作一致性

简要支撑：

- `docs/README.md` 约定的目录语义与实际落盘位置已经不完全一致
- `docs/plans/` 根目录存在多份非 `active/completed` 结构的文件
- 一次性验证记录与长期 testing 文档混放

后续调查建议：

- 区分 `normative / active work / historical evidence`
- 恢复 `docs/plans/active + completed` 的稳定结构

#### C5. 能力-测试映射缺失

- 名称：`capability-test-matrix`
- 级别：中高
- 影响面：长期回归控制、扩协议后的质量判断

简要支撑：

- 现在主要靠零散测试文件和人工记忆判断覆盖面
- 缺少“某项能力由哪些单测、契约测试、E2E、运维文档覆盖”的总表
- 随协议和运行时特性扩展，追踪成本会持续上升

后续调查建议：

- 建立 capability matrix
- 按数据模型、Admin API、runtime 生命周期、forwarding、native shell 契约分层映射

#### C6. 运维手册偏 happy path

- 名称：`operator-runbook-hardening`
- 级别：中
- 影响面：本地运维、正式分发、故障恢复

简要支撑：

- 现有 `local-runbook` 主要覆盖启动、CRUD、调用和日志查看
- 缺少备份恢复、迁移失败、端口/进程异常、日志保留和升级恢复等内容
- 更像开发者本地使用说明，而不是长期运维手册

后续调查建议：

- 拆成 `local-dev-runbook`、`operator-runbook`、`failure-recovery-runbook`
- 补齐数据库、端口、迁移、自动重启失败等故障路径说明

## 推荐处理顺序

建议优先顺序：

1. `native-release-verification-gap`
2. `docs-information-architecture-cleanup`
3. `admin-api-error-contract`
4. `admin-api-application-layer`
5. `runtime-config-snapshot`
6. `native-admin-client-decomposition`
7. `native-root-store-split`
8. `protocol-extension-surface`

说明：

- `quality-gate-realignment` 与 `smoke-vs-legacy-web-coupling` 已完成第一轮治理，不再作为当前最高优先级待办

## 备注

本清单是后续问题调查入口，不是最终设计稿。

每个问题在正式推进前，建议单独建立：

- 调查文档
- 设计文档
- 实施计划
- 验证记录
