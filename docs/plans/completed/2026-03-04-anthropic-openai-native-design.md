# FluxDeck 原生 Anthropics 入站转 OpenAI 兼容转发设计

日期：2026-03-04  
状态：已评审通过（用户确认）

## 1. 目标与范围

目标是在 `fluxd` 内原生支持 Anthropics 协议入站，并转发到 OpenAI 兼容上游，满足：

- 最大兼容度（语义可表达范围内尽量等价）
- 高宽容度（未知字段、能力差异可配置降级）
- 高自由度（网关级可配置，后续支持多对多协议转换）

首要落地链路：`anthropic -> openai-compatible`。

## 2. 关键约束

- 必须原生实现，不引入外部协议网关作为运行时依赖。
- 优先采用成熟开源实践（参考 transformer/adapter 思路）。
- Beta/扩展能力按可行性纳入：
  - 可行且稳定：首版直接实现。
  - 不成熟或不可逆：预留扩展点与 capability flag。

## 3. 总体架构（支持多对多）

采用“协议图 + IR”架构，而不是单向硬编码映射：

1. `protocol/ir`：统一语义中间层（Message、Tool、Event、Extensions）
2. `protocol/adapters/{proto}`：每个协议拆成两部分
- `decoder`: 协议请求/响应 -> IR
- `encoder`: IR -> 协议请求/响应
3. `protocol/registry`
- 注册入站/出站协议
- 在运行时选择 `A -> IR -> B` 的适配组合
4. `runtime/gateway_manager`
- 根据 `gateway.inbound_protocol` + `gateway.upstream_protocol` 选择路由与编解码器

这套结构可在后续扩展 `openai -> anthropic`、`anthropic -> gemini` 等组合，不改主链路。

## 4. 模块设计

### 4.1 HTTP 层

- 新增 `crates/fluxd/src/http/anthropic_routes.rs`
- 计划支持：
  - `POST /v1/messages`
  - `POST /v1/messages/count_tokens`
  - `stream=true` 的 SSE 分支

### 4.2 协议层

- 新增 `crates/fluxd/src/protocol/ir.rs`
- 新增 `crates/fluxd/src/protocol/adapters/anthropic/*`
- 新增 `crates/fluxd/src/protocol/adapters/openai/*`
- 新增 `crates/fluxd/src/protocol/registry.rs`

### 4.3 运行时

- 改造 `gateway_manager`：按协议组合启动对应 router/handler
- 为网关增加可选协议适配配置（兼容模式、能力开关、降级策略）

## 5. 数据流与映射规则

主流程：

`Inbound Request -> Decoder -> IR -> Encoder -> Upstream Request -> Upstream Response -> Decoder -> IR -> Encoder -> Outbound Response`

首版关键映射：

1. `model`
- Anthropics `model` -> IR -> OpenAI `model`
- 允许网关默认模型覆盖

2. `system`
- Anthropics `system`（字符串或 block）归一到 IR `system_parts[]`
- 编码到 OpenAI `messages(role=system)`

3. `messages/content blocks`
- 归一为 IR `parts[]`（text/image/tool_use/tool_result/thinking/...）
- 再编码到 OpenAI `messages/tools/tool_choice`

4. `tool_use/tool_result`
- IR 统一为 `tool_calls[]` / `tool_outputs[]`
- 保证后续双向可回放

5. `streaming`
- IR 统一事件模型（start/delta/tool_delta/stop/error）
- Anthropics SSE 与 OpenAI SSE 各自只负责事件编解码

6. `count_tokens`
- 优先调用上游原生能力
- 无能力时降级到本地估算并标记 `estimated=true`

7. `unknown fields`
- `permissive/compatible` 模式进入 `extensions`
- `strict` 模式明确报错

## 6. 错误处理与兼容策略

### 6.1 错误分层

- `decode_error`
- `capability_error`
- `upstream_error`
- `encode_error`

内部统一为 `FluxError { code, layer, message, details, request_id }`，再由出站协议 encoder 输出对应格式。

### 6.2 兼容模式

网关级策略：

- `strict`：不支持即失败
- `compatible`（默认）：优先降级并附带 warning 元数据
- `permissive`：最大透传，最小失败面

### 6.3 能力降级策略

按能力维度配置：

- `streaming`: `reject | downgrade_to_non_stream`
- `tools`: `reject | serialize_as_text`
- `thinking/citations/...`: `drop_with_notice | reject`

## 7. Beta/扩展能力纳入标准

每项能力满足以下三条则纳入首版：

1. 官方定义稳定且可依赖
2. 映射可逆，或降级可解释
3. 至少有 1 个可重复 e2e 用例

不满足时：保留 capability flag 与适配接口，不阻塞主链路上线。

## 8. 测试与验收

### 8.1 测试分层

- 单元测试：decoder/encoder/normalizer
- 契约测试：Anthropics 入/出参 shape 稳定
- e2e：`anthropic client -> fluxd -> mock openai upstream`

### 8.2 Golden Cases

- 基础非流式 `messages`
- `tool_use + tool_result` 往返
- 流式文本增量
- 流式工具调用增量（上游可用时）
- `count_tokens` 原生/降级两路径
- 未知字段透传 vs strict 拒绝

### 8.3 验收命令

- `cargo test -q`
- `cd apps/desktop && bun run test`
- `./scripts/e2e/smoke.sh`
- （新增）Anthropics 协议 e2e 脚本输出通过标识

## 9. 交付阶段

- Phase 1：`/v1/messages` + streaming + tools + count_tokens + compatibility modes
- Phase 2：可行 beta 能力默认开启（flag 可控）
- Phase 3：抽象成通用多对多 adapter SDK

## 10. 后续计划

本设计文档确认后，进入 `writing-plans` 产出可执行实施计划（任务拆分、测试先行顺序、风险回滚策略）。
