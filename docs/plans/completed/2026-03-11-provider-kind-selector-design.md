# 2026-03-11 Provider Kind Selector 设计稿

## 背景

当前 Provider 的 `kind` 在 macOS 原生前端通过自由文本输入，存在两个问题：

- 用户需要记忆合法值，配置体验差
- 后端未对 `kind` 做白名单验证，非法值可以写入数据库

本次改动目标是把 `kind` 收敛为固定枚举集合，同时保持现有存储结构与 API 字段不变。

## 目标

- 原生前端创建 Provider 时使用可选下拉，而不是自由填写
- 原生前端编辑 Provider 时允许重新选择 `kind`
- 后端在创建和更新 Provider 时校验 `kind`，必须是允许值之一
- Admin API 契约明确 `kind` 的允许值，避免前后端再次各自猜测

## 非目标

- 不修改数据库 schema
- 不把 `kind` 改成数据库 enum 或 Rust/Swift 强枚举持久化类型
- 不重做 Web 前端 Provider 表单
- 不自动迁移历史非法数据

## 允许值

存储值与 API 请求值使用机器值：

- `openai`
- `openai-response`
- `gemini`
- `anthropic`
- `azure-openai`
- `new-api`
- `ollama`

原生前端显示值使用友好标签：

- `OpenAI`
- `OpenAI-Response`
- `Gemini`
- `Anthropic`
- `Azure OpenAI`
- `New API`
- `Ollama`

## 方案选择

### 方案 A：只改原生前端输入控件

优点：

- 改动最小

缺点：

- 无法阻止 API 或其他客户端写入非法 `kind`
- 数据完整性仍然依赖前端自觉

### 方案 B：原生前端固定选项 + 后端白名单校验

优点：

- 同时满足可选体验与服务端约束
- 不改 schema，兼容当前存量数据结构
- 风险和改动面都较小

缺点：

- 需要同步维护一份允许值列表

### 方案 C：前后端全部改成强枚举类型

优点：

- 类型最严格

缺点：

- 需要改动 Rust/Swift/TS 多层模型和序列化
- 相对当前需求成本偏高

结论：采用方案 B。

## 详细设计

### 原生前端

在 `ProviderFormSheet` 中把 `Kind` 字段从 `TextField` 改成 `Picker`：

- 创建模式默认选中 `openai`
- 编辑模式按现有 provider 的 `kind` 回填
- 用户可以重新选择并保存

为避免 UI 和提交逻辑散落多处，新增一组共享元数据：

- `ProviderKindOption`
- 固定有序选项数组
- `label(for:)` 等辅助函数

表单提交仍然发送机器值，不改变 `CreateProviderInput` / `UpdateProviderInput` 字段结构。

### 后端

在 `provider` 领域模型旁增加允许值定义与校验函数：

- `SUPPORTED_PROVIDER_KINDS`
- `is_supported_provider_kind`
- `validate_provider_kind`

`ProviderService` 在以下入口统一执行校验：

- `create_provider`
- `update_provider`

非法时返回 `anyhow` 错误，错误信息需要明确指出非法值与允许值集合。

### Admin API 错误语义

当前 `PUT /admin/providers/{id}` 已返回 JSON 错误对象，保持该模式。

`POST /admin/providers` 当前错误时返回一个“伪 Provider”对象，不利于消费方处理。本次顺手统一为：

- `400`
- `{"error": "..."}`

这样 create/update 的失败语义一致，也更适合后端校验错误。

这属于 Provider Admin API 的行为修正，需要同步更新契约文档与测试。

## 测试策略

### Rust

- `provider_service_test`
  - 创建非法 `kind` 应失败
  - 更新非法 `kind` 应失败
- `admin_api_test`
  - `POST /admin/providers` 非法 `kind` 返回 `400`
  - `PUT /admin/providers/{id}` 非法 `kind` 返回 `400`

### Swift

- Provider kind 选项元数据测试
  - 允许值数量和顺序稳定
  - label 映射正确
- 若已有表单提交辅助可单测，则验证默认值和编辑回填行为

## 风险与兼容性

- 历史数据库若已存在非法 `kind`，列表与详情仍会显示原值；但从编辑页保存时会被要求改成合法值
- 由于 `POST /admin/providers` 错误响应结构从“伪 Provider”改为错误对象，需要确认当前原生前端对失败场景只是展示错误文本，而不是强依赖成功结构

## 验收标准

- 原生前端创建 Provider 时 `kind` 为下拉选择
- 原生前端编辑 Provider 时可以修改 `kind`
- 非法 `kind` 无法通过后端创建或更新
- 契约文档列出 `kind` 允许值
- 相关 Rust 与 Swift 测试通过
