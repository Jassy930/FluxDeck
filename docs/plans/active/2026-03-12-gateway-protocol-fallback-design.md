# Gateway Protocol Fallback 设计稿

日期：2026-03-12  
状态：已评审通过（用户确认）

## 1. 背景

当前 FluxDeck 已经支持：

- `openai -> openai`
- `anthropic -> openai`
- `anthropic -> anthropic`

但在 `openai-response` / Codex 一类场景中暴露出一个结构性问题：

- Provider 层已经允许配置更完整的协议类型
- Gateway 的 `inbound_protocol` / `upstream_protocol` 类型集合没有与 Provider 对齐
- 运行时仍然依赖“按已实现端点逐个接入”的方式
- 导致某些合法配置虽然能保存，但请求进入 Gateway 后直接 `404`，处于“可配置但不可用”的状态

这不符合项目当前对兼容性和可用性的目标。

## 2. 目标

本次设计目标：

1. 统一 Provider / Gateway 的协议类型集合
2. 在 `inbound_protocol == upstream_protocol` 时，为未专门实现的端点提供默认自动转发能力
3. 尽可能兼容常见客户端路径形式，例如：
   - `/responses`
   - `/v1/responses`
4. 保留现有专门实现链路（如 `chat/completions`、`messages`）的协议级处理、日志与监控扩展点
5. 避免因“暂未专门实现某端点”而让整个协议类型不可用

## 3. 非目标

本次不做：

- 把 FluxDeck 整体重构成通用 HTTP 反向代理
- 一次性补齐所有协议的 usage / metrics / tracing 深度能力
- 为 Provider 私有协议或非标准 header/body hack 做全量兼容
- 直接删除现有专门实现的 OpenAI / Anthropic 路由

## 4. 方案对比

### 方案 B：协议网关优先 + 同协议透传兜底

做法：

- 继续保留现有显式协议 handler
- 当请求未命中专门实现，且 `inbound_protocol == upstream_protocol` 时，进入兜底透传
- 透传保留原方法、原路径、原查询、原头、原 body

优点：

- 与现有项目架构一致
- 可以快速修复“可配置但不可用”
- 不影响后续对热点端点做协议增强

缺点：

- 兜底透传阶段只能提供最小日志，不具备完整结构化观测

### 方案 C：通用代理优先 + 协议增强附加

做法：

- Gateway 默认把所有请求都当成可透传流量
- 协议理解、usage 解析、日志增强作为中间件或插件附加

优点：

- 长期模型更统一
- 理论上对新增端点更自然

缺点：

- 与当前项目定位偏离较大
- 需要重构 Gateway 的主职责和现有分层
- 会把已经稳定的协议转发链路一起卷入重构

## 5. 方案选择

结论：采用方案 B。

原因：

- 项目现有设计文档已经把 FluxDeck 定义为“协议网关”，而不是通用 reverse proxy
- 当前代码结构也是围绕 `inbound_protocol + upstream_protocol + 专门 handler` 组织
- 用户当前核心诉求是“先保证可用”，而不是立刻重写成新的代理平台

因此更合理的长期路线是：

- 保持“协议网关”作为主架构
- 正式引入“同协议默认透传”作为一等 fallback 能力

## 6. 详细设计

### 6.1 协议类型集合统一

需要把以下三处的协议视图对齐：

- Provider `kind`
- Gateway `inbound_protocol`
- Gateway `upstream_protocol`

原则：

- Gateway 协议值不再只停留在 `openai | anthropic`
- 至少要能表达当前已支持和已暴露给用户的标准协议类型
- `provider_default` 仍作为 `upstream_protocol` 的特殊解析值保留

首批统一目标：

- `openai`
- `openai-response`
- `anthropic`
- `gemini`
- `azure-openai`
- `new-api`
- `ollama`
- `provider_default`（仅 `upstream_protocol`）

说明：

- 这不代表所有协议都已有专门 handler
- 它只表示配置层与运行时分发层使用一致的协议名集合

### 6.2 路由优先级

Gateway 对请求的处理顺序：

1. 先匹配已有专门 handler
2. 若未命中专门 handler，则判断是否允许同协议透传
3. 若允许，则进入 passthrough handler
4. 若不允许，则返回明确错误，而不是静默 404

这意味着：

- 已有能力不退化
- 未实现端点在同协议场景下默认可用
- 不同协议之间仍然坚持显式适配，不做隐式跨协议猜测

### 6.3 同协议默认透传规则

透传触发条件：

- `resolved inbound_protocol == resolved upstream_protocol`
- 当前请求没有命中该协议的专门 handler

透传范围：

- 方法：`GET/POST/PUT/PATCH/DELETE`
- 路径：尽可能原样透传
- 查询串：原样透传
- 请求头：默认透传，过滤 hop-by-hop 头
- 请求体：原样透传
- 响应状态码/头/body：原样返回

首批兼容策略：

- OpenAI 系协议同时兼容：
  - `/responses`
  - `/v1/responses`
- 若 Provider `base_url` 已带 `/v1`，Gateway 需避免拼接出错误双前缀

### 6.4 日志与监控边界

专门 handler 继续保留：

- `usage` 提取
- `first_byte_ms`
- 结构化 `error_stage`
- 模型请求/实际模型记录

兜底透传初期只要求最小观测：

- `request_id`
- `gateway_id`
- `provider_id`
- `inbound_protocol`
- `upstream_protocol`
- `status_code`
- `latency_ms`
- 原始错误文本（若可获取）

也就是说：

- 透传链路先保证可用
- 深度观测后续按端点增量补充

### 6.5 错误语义

当前未实现端点不应再表现为框架层 `404`。

新的原则：

- 若命中 passthrough，则让上游真实响应决定状态码
- 若协议不一致且没有专门适配器，返回明确的配置/能力错误
- 若协议一致但透传构造失败，返回明确的 gateway forwarding error

## 7. 待讨论 Issue

### Issue: 是否演进到方案 C（通用代理优先）

当前结论是不采用方案 C 作为本轮实施方向，但需要将其保留为正式待讨论议题。

需要后续专门评估的点：

- FluxDeck 的产品定位是否要从“协议网关”升级为“本地代理平台”
- 若采用通用代理优先，现有 `protocol/*`、`forwarding/*`、`http/*_routes.rs` 的职责如何重组
- 现有监控、usage、错误分层能力应作为网关核心还是中间件能力存在
- 方案 C 是否真的降低长期复杂度，还是仅把复杂度从协议层转移到代理中间件层

建议将该 issue 作为后续架构讨论项，在完成本轮可用性修复后单独评审。

## 8. 验收标准

- `openai-response` / Codex 类请求不再因 Gateway 缺少 `/responses` 路由而直接 `404`
- Gateway 的 `inbound_protocol` / `upstream_protocol` 与 Provider 类型集合完成对齐
- 同协议、未专门实现端点可以自动透传
- 不同协议、未实现适配的场景返回明确错误
- 文档明确说明专门 handler 与 fallback passthrough 的边界
