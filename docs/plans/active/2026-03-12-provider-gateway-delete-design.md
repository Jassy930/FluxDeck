# FluxDeck Provider / Gateway 删除功能设计

## 目标

为 `fluxd`、`fluxctl` 和原生桌面端统一增加 Provider 与 Gateway 删除能力，并确保删除行为由 `fluxd` 作为唯一真相来源统一裁决。

本次设计覆盖三个入口：

- `fluxd` Admin API
- `fluxctl`
- 原生桌面端 UI

## 设计动机

当前系统已支持 Provider / Gateway 的创建、查询、更新，以及 Gateway 的运行时启停，但缺少删除入口。这带来几个问题：

- 测试数据和废弃配置只能手动改库清理
- `fluxctl` 无法完成完整资源生命周期管理
- 原生桌面端工作台只能新增和编辑，不能回收失效资源

同时，删除并不是简单的数据库行删除。系统内部已有两条明确约束：

- `Gateway.default_provider_id` 强依赖一个现存 Provider
- Gateway 可能存在运行中的 listener，需要先安全停机再删除配置

因此，删除语义必须先在服务端定死，再由 CLI 和 UI 复用。

## 方案选择

### 方案 A：由 `fluxd` 统一实现删除语义，CLI / UI 只调用接口

优点：

- 单一真相来源，行为不会因客户端不同而漂移
- Provider 引用检查与 Gateway 停机删除都可以在服务端原子控制
- 未来增加其他客户端时无需重复实现删除规则

缺点：

- 需要同时扩展 Admin API、CLI、Swift 客户端和测试

### 方案 B：`fluxctl` / 原生端自行预检查和编排删除逻辑

优点：

- 服务端改动看似较少

缺点：

- 删除规则分散，容易出现 UI 和 CLI 行为不一致
- 未来新增入口时需要再次复制逻辑
- 很难保证运行态检查与删除动作之间没有竞态

### 方案 C：直接依赖数据库外键和底层错误

优点：

- 代码量最少

缺点：

- 用户只能看到底层数据库错误
- Gateway 删除时无法表达“先 stop 再 delete”的业务语义
- 不符合当前 Admin API 的明确契约风格

### 结论

采用方案 A。

## 行为规则

### Provider 删除

- 新增 `DELETE /admin/providers/{id}`
- 若 Provider 不存在：返回 `404`
- 若仍被任一 Gateway 的 `default_provider_id` 引用：拒绝删除并返回 `409`
- `409` 响应必须包含正在引用该 Provider 的 `gateway id` 列表，便于 CLI 与 UI 直接展示
- 若未被引用：删除 Provider 及其 `provider_models`

### Gateway 删除

- 新增 `DELETE /admin/gateways/{id}`
- 若 Gateway 不存在：返回 `404`
- 若 Gateway 当前为运行中：由服务端自动执行 `stop -> delete`
- 若自动停止失败：删除中止，返回错误，不删除配置
- 若 Gateway 当前未运行：直接删除配置

## API 设计

### `DELETE /admin/providers/{id}`

成功返回：

```json
{
  "ok": true,
  "id": "provider_main"
}
```

冲突返回：

```json
{
  "error": "provider is referenced by gateways",
  "id": "provider_main",
  "referenced_by_gateway_ids": ["gateway_main", "gateway_backup"]
}
```

状态码：

- `200`：删除成功
- `404`：Provider 不存在
- `409`：仍被 Gateway 引用
- `400`：其他请求错误

### `DELETE /admin/gateways/{id}`

成功返回：

```json
{
  "ok": true,
  "id": "gateway_main",
  "runtime_status_before_delete": "running",
  "stop_performed": true,
  "user_notice": "Gateway 已删除。运行中的实例已先停止。"
}
```

状态码：

- `200`：删除成功
- `404`：Gateway 不存在
- `400`：删除前停机失败或其他请求错误

字段语义：

- `runtime_status_before_delete`：删除前的运行态
- `stop_performed`：本次是否实际执行了停机
- `user_notice`：给 CLI / UI 直接展示的人类可读文案

## 服务端实现边界

### `fluxd`

Provider 删除流程：

1. 查询 Provider 是否存在
2. 查询有哪些 Gateway 的 `default_provider_id` 指向它
3. 若引用列表非空，返回 `409` 和引用列表
4. 删除 `provider_models`
5. 删除 Provider 主记录

Gateway 删除流程：

1. 查询 Gateway 是否存在
2. 读取删除前运行态
3. 若运行中，调用 `gateway_manager.stop_gateway`
4. 停机成功后删除 Gateway 配置
5. 返回带 `user_notice` 的删除结果

实现边界约束：

- Provider 的“是否可删”判断应放在 `service` 层，避免客户端重复实现
- Gateway 的运行态删除编排应放在 Admin API 路由层或专门服务层，因为它同时依赖 repo 和 runtime manager
- repo 层只做持久化：查询引用、删除记录、列出依赖

## fluxctl 设计

新增子命令：

- `fluxctl provider delete <id>`
- `fluxctl gateway delete <id>`

交互规则：

- 默认要求确认
- 支持 `-y` / `--yes` 跳过确认，便于脚本自动化

确认文案要求：

- Provider 删除提示“若仍被 Gateway 引用，服务端会拒绝删除”
- Gateway 删除提示“若实例正在运行，服务端会先停止再删除”

输出规则：

- 成功时打印完整 JSON 响应
- 若返回 `user_notice`，额外打印 `Notice: ...`
- Provider 删除命中 `409` 时，要把 `referenced_by_gateway_ids` 一并展示出来

## 原生桌面端设计

### Provider 工作台

- 每张 Provider 卡片增加 `Delete`
- 删除前弹确认框
- 确认文案强调：
  - 删除不可恢复
  - 若仍被 Gateway 引用，操作会失败

### Gateway 工作台

- 每张 Gateway 卡片增加 `Delete`
- 删除前弹确认框
- 确认文案强调：
  - 删除不可恢复
  - 若实例正在运行，系统会先停止再删除

### 删除后的状态更新

- 成功后统一刷新 Provider / Gateway 列表
- 若删除目标正在编辑中，清理对应 sheet 状态
- Gateway 删除优先展示服务端 `user_notice`
- Provider 删除展示简短成功提示
- 删除失败时沿用现有 `loadError` / `operationNotice` 通道

## 测试策略

### `fluxd`

- 删除未被引用的 Provider 成功
- 删除被 Gateway 引用的 Provider 返回 `409`，并包含引用列表
- 删除已停止的 Gateway 成功
- 删除运行中的 Gateway 时自动先停机再删除
- 删除不存在的 Provider / Gateway 返回 `404`
- Gateway 停机失败时删除中止

### `fluxctl`

- 命令解析覆盖 `provider delete` / `gateway delete`
- `-y` / `--yes` 参数解析正确
- 确认逻辑函数可单测
- 删除结果中的 `user_notice` 可以被提取输出

### 原生桌面端

- 删除返回体解码正确
- Provider 删除冲突错误可以转为可展示信息
- Gateway 删除结果优先显示 `user_notice`
- 列表卡片存在删除入口且提交中状态会禁用

## 文档同步

本次变更必须同步更新：

- `docs/contracts/admin-api-v1.md`
- `docs/ops/local-runbook.md`
- `apps/desktop-macos-native/README.md`

如代码实现过程引入新的错误返回结构，也必须同步写入契约文档。

## 非目标

- 不支持 Provider 级联删除 Gateway
- 不引入“软删除”或回收站
- 不在本次修改日志和统计数据的保留策略
- 不在本次重构原生端全局提示系统，只复用现有错误与 notice 通道
