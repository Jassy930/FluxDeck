# 2026-03-09 Gateway Forwarding 设计稿

## 目标

为 FluxDeck 建立一个面向单 Gateway 的标准协议转发内核，第一阶段完整覆盖以下三条链路：

- `OpenAI inbound -> OpenAI upstream`
- `Anthropic inbound -> OpenAI upstream`
- `Anthropic inbound -> Anthropic upstream`

设计目标聚焦于：

- 转发能力完整性
- 响应与流式效果稳定性
- 标准协议边界清晰
- 为后续转发内容整理、Token 统计与监控预留稳定扩展点

## 范围

### 本阶段纳入

- 单 Gateway 单默认 Provider 转发
- OpenAI / Anthropic 两种标准入站协议
- OpenAI / Anthropic 两种标准上游协议
- 普通响应与 Streaming 响应
- 标准协议内的模型决策能力
- 结构化请求日志增强
- Token / usage 整理能力的接口预留

### 本阶段不纳入

- Provider failover / provider chain
- 熔断器 / 主动健康检查
- Provider 私有协议适配
- 某家 relay 的特殊 header / body hack
- 完整 metrics/tracing 系统
- 单独的 usage 汇总表
- `OpenAI inbound -> Anthropic upstream`

## 实施结果回填

截至 2026-03-09，本设计稿对应的一阶段实现已经完成并验证：

- 已完成 `OpenAI inbound -> OpenAI upstream`
- 已完成 `Anthropic inbound -> OpenAI upstream`
- 已完成 `Anthropic inbound -> Anthropic upstream`
- 已补齐结构化请求日志字段、Admin API logs 暴露字段与 usage 记录入口
- 已通过 Rust 全量测试、前端测试与 e2e smoke 验证

当前明确延后：

- `OpenAI inbound -> Anthropic upstream`
- 流式 usage 的完整聚合与持久化
- 独立 metrics / tracing / usage 汇总存储

## 边界原则

### 1. Gateway 只处理标准协议

Gateway 只面向标准 `OpenAI` / `Anthropic` 协议进行解码、编码与转发。

不在 Gateway 内部承担：

- Provider 私有字段修补
- 非标准响应格式兼容
- 特定 relay 的特殊 header 规则
- 某个客户端的协议方言适配

### 2. 特殊适配放在两端

- 下游客户端应先保证自己输出标准协议
- 上游 Provider 若不是标准协议，应由独立适配层先转换为标准协议
- FluxDeck Gateway 只在标准协议世界内桥接与转发

### 3. 转发内核必须具备可观测插槽

当前阶段不直接实现完整监控系统，但必须预留稳定插槽，以支持后续：

- Token 数量整理
- 用量统计
- 延迟与首字节统计
- 请求分类与失败阶段分析

## 总体架构

建议采用“协议适配层 + 共享转发内核”的方案。

### 三层结构

#### Inbound Layer

负责理解客户端协议，并将其转为内部统一请求语义。

包括：

- `OpenAI inbound decoder`
- `Anthropic inbound decoder`

职责：

- 基础字段校验
- 消息结构标准化
- tool / stream / token 参数提取
- 保留标准协议扩展字段

不负责：

- 查询目标 Provider
- 拼接上游请求
- 记录转发策略

#### Core Forwarding Layer

负责一次转发请求的统一业务决策。

包括：

- `TargetResolver`
- `ModelResolver`
- `ForwardExecutor`
- `ResponseMapper`
- `ForwardObservationCollector`

职责：

- 解析 Gateway / Provider 目标
- 解析 `upstream_protocol`
- 决定 `effective_model`
- 控制 streaming / non-streaming 分支
- 统一错误分类
- 统一日志与 usage 整理入口

不负责：

- 协议具体 header 细节
- 上游 URL 拼装细节
- 某协议 SSE 格式细节

#### Upstream Layer

负责向标准 OpenAI / Anthropic 上游发起 HTTP 请求。

包括：

- `OpenAiUpstreamClient`
- `AnthropicUpstreamClient`

职责：

- URL 组装
- 认证 header 注入
- body 编码
- 原始响应接收
- streaming / non-streaming 请求发送

不负责：

- DB 查询
- fallback / failover
- 兼容策略
- 监控决策

## 请求流转

一次请求建议按如下链路执行：

1. `Gateway Router`
2. `Inbound Decoder`
3. `TargetResolver`
4. `RequestNormalizer`
5. `UpstreamEncoder + UpstreamClient`
6. `ResponseMapper`
7. `LogWriter / ObservationSink`

### 关键流转对象

#### `NormalizedRequest`

统一内部请求对象，只承载跨协议稳定共性。

建议字段：

- `messages`
- `system`
- `model`
- `stream`
- `max_tokens`
- `temperature`
- `tools`
- `tool_choice`
- `metadata`
- `extensions`

设计原则：

- 只收敛标准协议共性
- 协议特有字段通过 `extensions` 保留
- 不做大而全 IR

#### `ResolvedTarget`

表示本次请求真正要打到哪里的解析结果。

建议字段：

- `provider_id`
- `upstream_protocol`
- `base_url`
- `api_key`
- `effective_model`
- `protocol_config`

#### `ForwardObservation`

承载本次转发的结构化观测信息。

建议字段：

- `request_id`
- `gateway_id`
- `provider_id`
- `inbound_protocol`
- `upstream_protocol`
- `model_requested`
- `model_effective`
- `is_stream`
- `status_code`
- `latency_ms`
- `first_byte_ms`
- `error_stage`
- `error_type`

#### `UsageSnapshot`

承载从标准协议响应中整理出的 usage 信息。

建议字段：

- `input_tokens`
- `output_tokens`
- `total_tokens`
- `cache_read_tokens`
- `cache_write_tokens`
- `reasoning_tokens`
- `raw_usage_payload`

设计原则：

- 允许字段缺失
- 允许不同协议只填部分信息
- 当前阶段先立结构，不要求所有链路都完全提取

## 三条目标链路的实现要求

### 1. OpenAI inbound -> OpenAI upstream

定位为最直通的基准链路。

要求：

- 支持 `/v1/chat/completions`
- 支持 streaming 转发
- 支持 `default_model` fallback
- 支持 `model_requested / model_effective` 记录
- 统一错误包装与日志

### 2. Anthropic inbound -> OpenAI upstream

定位为跨协议兼容主链路。

要求：

- 支持 `/v1/messages`
- 支持 `/v1/messages/count_tokens`
- 完成 `messages -> chat.completions` 映射
- 完成 tool / tool_use 映射
- 完成 usage / stop_reason 映射
- 完成 SSE 映射
- 支持标准协议间的 compatibility policy

### 3. Anthropic inbound -> Anthropic upstream

定位为 Anthropic 原生上游链路。

要求：

- 支持 `/v1/messages`
- 支持 `/v1/messages/count_tokens`
- 支持 Anthropic 原生 streaming
- 尽可能保持 Anthropic 原生错误语义
- 支持 `default_model` fallback
- 支持 usage 提取与日志整理

## 协议共享能力与协议特化能力

### 共享能力

以下能力应放入共享转发内核：

- Gateway / Provider 目标解析
- `upstream_protocol` 分发
- `default_model` fallback
- 标准协议范围内的模型策略
- 统一 request id 与日志
- `ForwardObservation` 汇总
- `UsageSnapshot` 抽取入口
- streaming / non-streaming 统一执行框架
- 错误阶段分类

### 特化能力

以下能力必须按协议分别实现：

- OpenAI / Anthropic 入站解码
- OpenAI / Anthropic 上游编码
- OpenAI / Anthropic 响应映射
- OpenAI SSE / Anthropic SSE 格式处理
- OpenAI tool calls / Anthropic tool_use 映射
- Anthropic `count_tokens` 语义

## Gateway 配置模型

沿用现有 `Gateway` 配置结构，但收紧语义。

### 保留字段

- `id`
- `name`
- `listen_host`
- `listen_port`
- `inbound_protocol`
- `upstream_protocol`
- `default_provider_id`
- `default_model`
- `protocol_config_json`
- `enabled`
- `auto_start`

### 语义约束

#### `inbound_protocol`

第一阶段只允许：

- `openai`
- `anthropic`

#### `upstream_protocol`

第一阶段只允许：

- `openai`
- `anthropic`

并且该字段必须成为运行时真实行为开关，而不是文档字段。

#### `default_provider_id`

维持单 Gateway 单默认 Provider，不引入 provider chain。

### `protocol_config_json` 约束

将其收敛为标准协议策略容器。

建议允许以下分组：

- `request_policy`
- `model_policy`
- `response_policy`
- `observability`
- `timeouts`

允许保留 `compatibility_mode`，但仅控制标准协议之间的映射策略：

- `strict`
- `compatible`

不允许承担 Provider 私有兼容。

## 日志与可观测预留

当前阶段不实现完整监控系统，但在主链路预留六个观测点：

1. 请求进入时
2. 入站解码完成后
3. 上游请求发出前
4. 收到上游首字节时
5. 响应完成时
6. 失败退出时

### 建议增强 `request_logs`

在现有 `request_logs` 基础上建议补充：

- `inbound_protocol`
- `upstream_protocol`
- `model_requested`
- `model_effective`
- `stream`
- `first_byte_ms`
- `input_tokens`
- `output_tokens`
- `total_tokens`
- `usage_json`
- `error_stage`
- `error_type`

当前阶段先增强现有日志表，不急于拆 usage 专表。

## 测试策略

每条链路至少覆盖以下场景：

- 非流式成功
- 流式成功
- 配置错误
- 上游错误
- `default_model` fallback
- usage 提取
- 日志字段完整性

### 优先测试顺序

1. 共享内核单元测试
2. `OpenAI inbound -> OpenAI upstream`
3. `Anthropic inbound -> OpenAI upstream`
4. `Anthropic inbound -> Anthropic upstream`

## 分阶段实施建议

### 阶段 1：抽共享内核

目标：

- 抽出 `ResolvedTarget`
- 抽出 `ForwardObservation`
- 抽出 `UsageSnapshot`
- 抽出 `TargetResolver`
- 抽出 `UpstreamClient` trait
- 保持现有行为尽量不变

### 阶段 2：迁移 OpenAI 基准链路

目标：

- 将 `OpenAI inbound -> OpenAI upstream` 接入共享内核
- 补齐 OpenAI streaming
- 补齐 `default_model` fallback
- 补齐结构化日志字段

### 阶段 3：迁移 Anthropic -> OpenAI

目标：

- 将现有 Anthropic 路由中的兼容逻辑拆入共享骨架
- 保持现有测试语义尽量稳定

### 阶段 4：新增 Anthropic -> Anthropic

目标：

- 增加 `AnthropicUpstreamClient`
- 实现原生 Anthropic 上游路径

### 阶段 5：增强日志与 usage 整理能力

目标：

- 将 `ForwardObservation` / `UsageSnapshot` 写入增强后的 `request_logs`
- 为后续转发内容监控与统计打基础

## 参考结论

本设计吸收 `cc-switch` 中“共享请求上下文、上游分层、流式单独处理、日志与状态分层”的成熟经验，但明确收窄边界：

- 只做标准协议转发
- 不做 provider-specific 兼容
- 不把 failover / circuit breaker 纳入当前阶段

## 本设计的成功标准

完成第一阶段后，应达到以下状态：

- `upstream_protocol` 真正驱动上游实现
- 三条目标链路都具备明确落点
- OpenAI / Anthropic streaming 有统一执行框架
- `default_model` 与基础模型策略统一生效
- request log 已具备 Token / usage / latency 的结构化预留
