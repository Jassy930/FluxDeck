# 2026-03-12 仓库级架构评审记录

## 目标

对 FluxDeck 整个仓库做一次偏长期演进视角的架构审查，重点关注：

- 控制面与数据面的边界是否清晰
- 协议扩展能力是否真的可持续
- 原生桌面端是否已经形成稳定应用层
- 文档、测试与验收链路是否对齐当前产品主线

## 结论摘要

当前仓库已经具备“边界清晰的单体雏形”，但距离可长期演进的平台型架构还有明显差距。

最关键的问题不是单点 bug，而是三组结构性耦合：

1. `fluxd` 仍把控制面配置存储、运行时决策、协议转发和统计查询压在同一个服务与同一份 SQLite 模型上。
2. 原生桌面端虽然界面层拆分较细，但应用状态管理和契约边界仍高度集中在 `ContentView` 与 `AdminApiClient.swift`。
3. 文档与验证链路没有完全跟随“原生端优先、Web 端暂停”的产品现实，仓库里出现了多套主线定义。

## 主要发现

### 1. `fluxd` 当前更像“分层单体”，还不是稳定平台内核

高优先级风险：

- 数据面热路径仍直接读取控制面 SQLite，并在请求期动态解析 Gateway/Provider 配置。
- 协议扩展点仍主要依赖 `match` 和专门路由，而不是真正的注册式能力模型。
- Admin API handler 里混入了生命周期编排、配置 diff、统计 SQL 和错误语义决策。
- `GatewayManager` 只维护进程内内存态，缺少任务退出回收、监督和更强状态机。

影响：

- 协议继续增加时，修改点会横跨 runtime、router、forwarding、日志提取和测试矩阵。
- 如果未来要支持更多 Gateway、更多观测维度，控制面和数据面会一起放大复杂度。

### 2. 原生桌面端 UI 已成形，但应用层边界还不稳

高优先级风险：

- `ContentView` 已经同时承担应用级状态容器、导航协调、异步刷新和 CRUD workflow。
- `AdminApiClient.swift` 同时承载 DTO、JSON 容器、网络传输、错误翻译和展示辅助逻辑。
- 多个视图和派生模型直接消费 `Admin*` DTO，缺少中间 application model / adapter。

影响：

- 后端契约扩展会直接向多个 UI 面扩散。
- 后续若引入缓存、离线快照、增量刷新、健康检查、分发期诊断页，改动面会越来越大。

### 3. 主线产品、主线文档、主线验收还没有重新对齐

高优先级风险：

- 仓库约定已明确 `apps/desktop` 暂停，但 README、USAGE、testing 文档仍把它放在默认验证链路里。
- `scripts/e2e/smoke.sh` 仍依赖 `apps/desktop/src/api/admin` 做一致性校验。
- 原生端是当前主产品，但未进入默认主线质量门禁。

影响：

- 新成员和自动化容易被旧入口误导。
- 后端和原生端长期解耦会继续被遗留 Web 桌面实现拖住。

## 建议路线

### Phase 1：先清边界，不急着再扩协议面

建议优先做：

1. 引入 `compiled gateway config` / `runtime snapshot`
2. 把 Gateway 生命周期与 Admin 查询编排从 `http/admin_routes.rs` 下沉到 application service
3. 统一 Admin API 错误 envelope 与 machine-readable code
4. 把 CLI 和 Native 的契约消费从“手写复制”收敛为共享 contract 或生成物

### Phase 2：把原生端从“大根视图”升级为应用层结构

建议优先做：

1. 拆分 `AdminApiClient.swift` 为 `Contracts / Transport / Repository / Mapper`
2. 把 `ContentView` 下沉为 `AppStore + feature store/view model`
3. 限制 `Admin*` DTO 只出现在 adapter 层，View 只消费稳定 view state

### Phase 3：重新定义唯一质量门禁

建议优先做：

1. 建立唯一主线验证集合，覆盖 `cargo test -q`、`./scripts/e2e/smoke.sh`、`xcodebuild test`
2. 把 Web 桌面一致性校验从主 smoke 中移出，降为 legacy 检查
3. 建立 capability matrix，明确能力与单元/契约/E2E/运维文档的映射

## 不建议的方向

当前不建议立即做“大重构式通用代理平台化”。

原因：

- 现在最影响长期演进的不是“协议抽象不够宏大”，而是边界和质量门禁没有收敛。
- 在控制面/数据面、原生端应用层和文档验证链路都尚未稳定前，直接重写成更抽象的平台会放大风险。

## 本次输出

- 新增计划归档：`docs/plans/completed/2026-03-12-repository-architecture-review.md`
- 新增进度记录：`docs/progress/2026-03-12-repository-architecture-review.md`
