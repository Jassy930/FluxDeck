# 2026-03-11 GLMGLM token 监测排查

## 现象

- 用户反馈：`GLMGLM` gateway 的 token 数量似乎没有进入 FluxDeck 监测面板。
- 监测面板数据来源是 `request_logs.total_tokens` 聚合，而不是单独的内存计数器。

## 现场配置

- `gateways.id=GLMGLM`
- `inbound_protocol=anthropic`
- `upstream_protocol=anthropic`
- `listen_port=18072`
- `default_provider_id=glm-coding-id`
- `default_model=GLM-5`
- `providers.id=glm-coding-id`
- `kind=anthropic`
- `base_url=https://open.bigmodel.cn/api/anthropic`

## 证据 1：Admin 聚合层不是根因

`stats overview` 直接对 `request_logs.total_tokens` 做 `SUM()`：

- `crates/fluxd/src/http/admin_routes.rs`
  - `get_stats_overview()` 使用 `COALESCE(SUM(total_tokens), 0)`
  - `by_gateway` / `by_provider` / `by_model` 也都直接汇总 `total_tokens`

因此只要 `request_logs.total_tokens` 为空，监测面板一定显示不出来。

## 证据 2：`GLMGLM` 历史请求里 token 字段确实长期为空

查询：

```sql
SELECT request_id, gateway_id, provider_id, inbound_protocol, upstream_protocol,
       model_requested, model_effective, stream, status_code,
       input_tokens, output_tokens, total_tokens, created_at
FROM request_logs
WHERE gateway_id='GLMGLM'
ORDER BY created_at DESC
LIMIT 15;
```

结果特征：

- 最近 15 条里 11 条 `stream=1`
- 15 条里 `with_tokens=0`
- `streaming_with_tokens=0`

说明问题发生在 `request_logs` 入库之前，而不是 UI 展示层。

## 证据 3：当前上游 GLM Anthropic 兼容接口本身会返回 usage

直接请求 `glm-coding-id` 上游：

```bash
curl ... /v1/messages/count_tokens
```

返回：

```json
{"input_tokens":6}
```

```bash
curl ... /v1/messages
```

返回关键片段：

```json
"usage":{"input_tokens":6,"output_tokens":48,...}
```

说明“智谱不上报 usage”不是当前根因，至少非流式原生 Anthropic 响应会返回 usage。

## 证据 4：当前经由 FluxDeck 的非流式请求可以记 token，流式请求不会

对本地运行中的 `fluxd` 和 `GLMGLM`（`http://127.0.0.1:18072`）做最小复现：

1. `POST /v1/messages/count_tokens`
2. `POST /v1/messages` 非流式
3. `POST /v1/messages` 流式

复现后查询：

```sql
SELECT request_id, gateway_id, stream, status_code,
       input_tokens, output_tokens, total_tokens, usage_json, created_at
FROM request_logs
WHERE gateway_id='GLMGLM'
ORDER BY created_at DESC
LIMIT 6;
```

结果：

- `count_tokens`：`stream=0`，`total_tokens=6`
- 非流式 `/v1/messages`：`stream=0`，`input_tokens=6`，`output_tokens=48`，`total_tokens=54`
- 流式 `/v1/messages`：`stream=1`，`input_tokens/output_tokens/total_tokens/usage_json` 全空

统计汇总：

```sql
SELECT COUNT(*) AS total,
       SUM(CASE WHEN stream=1 THEN 1 ELSE 0 END) AS streaming,
       SUM(CASE WHEN total_tokens IS NOT NULL THEN 1 ELSE 0 END) AS with_tokens,
       SUM(CASE WHEN stream=1 AND total_tokens IS NOT NULL THEN 1 ELSE 0 END) AS streaming_with_tokens,
       SUM(CASE WHEN stream=0 AND total_tokens IS NOT NULL THEN 1 ELSE 0 END) AS nonstream_with_tokens
FROM request_logs
WHERE gateway_id='GLMGLM';
```

结果：

- `streaming_with_tokens=0`
- `nonstream_with_tokens=2`

这已经直接证明：当前问题集中在流式链路。

## 根因

### 根因 1：所有成功的流式请求都会以空 usage 写入 `request_logs`

以下路径在成功流式返回时都执行：

- 记录一条 `RequestLogEntry`
- `usage: Default::default()`
- 立即把上游字节流透传回客户端

对应位置：

- `crates/fluxd/src/http/anthropic_routes.rs`
  - 原生 `anthropic -> anthropic` 流式路径
  - `openai -> anthropic` 转码流式路径
- `crates/fluxd/src/http/openai_routes.rs`
  - `openai -> openai` 流式路径

因为 `RequestLogService` 只是原样把 `entry.usage.*` 写入表字段，所以这里给空值，数据库就只能得到空值。

### 根因 2：`GLMGLM` 恰好主要走的是 Anthropic 原生流式链路

`GLMGLM` 配置为 `anthropic -> anthropic`，Claude Code/Anthropic 客户端常态使用流式 `/v1/messages`。

而智谱 Anthropic 兼容流在结束前会发送：

```text
event: message_delta
data: {"type":"message_delta",...,"usage":{"input_tokens":6,"output_tokens":48,...}}
```

但当前 FluxDeck 原生流式路径是“只透传、不解析、不在流结束后补写日志”，所以最终 usage 没有被持久化。

### 根因 3：OpenAI 转 Anthropic 的流式链路也存在同类缺口

`crates/fluxd/src/protocol/adapters/openai/stream_decoder.rs` 目前只解析：

- `MessageStart`
- `TextDelta`
- `ToolCallStart`
- `ToolCallDelta`
- `MessageStop`

没有解析任何 usage 事件，因此即使后续要给 `anthropic <- openai stream` 做 token 统计，也还缺少 stream usage 提取。

## 结论

- `GLMGLM` “token 不被监测”的直接原因不是 Admin 聚合，不是 SQLite schema，也不是智谱当前非流式不返回 usage。
- 当前真正的问题是：FluxDeck 的成功流式请求没有 token usage 持久化能力。
- `GLMGLM` 因为主要被 Anthropic 客户端以流式方式调用，所以表现最明显。

## 修复方向

1. 为成功的流式请求增加 usage 采集与最终落库，而不是在流开始时就以空 usage 记账。
2. 对 `anthropic -> anthropic` 原生流：
   - 解析 `message_delta` 里的 `usage`
   - 在流结束后补写或更新对应 `request_logs`
3. 对 `anthropic -> openai` / `openai -> openai` 流：
   - 请求上游携带 usage（若协议支持）
   - 扩展 `OpenAiSseDecoder` 识别最终 usage chunk
   - 在流结束后补写 token 数据
4. 评估是否要把 `count_tokens` 请求单独标记，避免把“预估输入 token”与“真实完成 token”混进同一监测口径。

## 本次实现

- 已先修复用户当前命中的 `anthropic -> anthropic` 原生流式路径
- 新增 `RequestLogService::update_usage()`，允许流结束后按 `request_id` 回写 token 字段
- 在 `crates/fluxd/src/http/anthropic_routes.rs` 的原生流式透传路径中：
  - 边透传上游 SSE
  - 边解析 `message_start` / `message_delta` 里的 `usage`
  - 流结束后把最终 `input_tokens/output_tokens/total_tokens/usage_json` 更新回同一条 `request_logs`

## 本次验证

已执行：

```bash
cargo test -p fluxd --test anthropic_native_streaming_test -q
cargo test -p fluxd --test anthropic_native_forwarding_test -q
cargo test -p fluxd --test openai_streaming_test -q
```

结果：

- 3 个针对性测试均通过
- 新增回归已验证：原生 Anthropic 流式请求在消费完整流后，会把 `12 / 3 / 15` 写入 `request_logs`

## 当前剩余范围

- `anthropic -> openai` 与 `openai -> openai` 的流式 token 统计仍未修复
- 这两条路径还缺少对上游 stream usage 的解析与持久化
- 当前提交已经足够解决 `GLMGLM` 这条 `anthropic -> anthropic` gateway 的 token 监测缺口

## 剩余范围排查结论

### 1. `anthropic -> openai`：需要修，且有实际流量影响

数据库统计：

```sql
SELECT inbound_protocol, upstream_protocol, stream, COUNT(*) AS total,
       SUM(CASE WHEN total_tokens IS NOT NULL THEN 1 ELSE 0 END) AS with_tokens
FROM request_logs
GROUP BY inbound_protocol, upstream_protocol, stream;
```

关键结果：

- `anthropic -> openai, stream=0`：`10` 条，`10` 条有 token
- `anthropic -> openai, stream=1`：`64` 条，`0` 条有 token

这说明该链路不是理论缺口，而是已存在真实监测丢失。

### 2. `openai -> openai`：代码上同样有缺口，但本机暂未观察到实际 streaming 流量

当前本机 `request_logs` 没有明确的 `openai -> openai, stream=1` 样本。

但代码路径和 `anthropic -> anthropic` / `anthropic -> openai` 一样，成功流式请求仍然是：

- 先写一条 `usage: Default::default()` 的日志
- 再把上游 SSE 直接透传给客户端

因此只要未来有 `openai` inbound 的流式使用，这条链路同样会丢 token。

### 3. OpenAI 兼容上游拿到 streaming usage 的前提已确认

对 `aone_provider_id` 做最小直连验证：

- 请求参数：

```json
{
  "stream": true,
  "stream_options": { "include_usage": true }
}
```

- 上游返回最终 chunk：

```json
{
  "choices": [],
  "usage": {
    "prompt_tokens": 10,
    "completion_tokens": 8,
    "total_tokens": 18
  }
}
```

说明：

- `openai` 兼容上游支持 `stream_options.include_usage=true`
- 技术上可以通过最终 usage chunk 做持久化

## 剩余范围修复方案

### 方案 A：先修 `anthropic -> openai`，优先级最高

原因：

- 已有 64 条流式请求全部丢 token
- 影响真实监测面板
- 风险可控，收益明确

建议实现：

1. 在 `anthropic_routes.rs` 的 `anthropic -> openai` 流式请求发出前，确保上游 payload 带上：

```json
"stream_options": { "include_usage": true }
```

2. 在 `map_upstream_to_anthropic_stream(...)` 这条桥接链路中，同时做两件事：
   - 继续把 OpenAI SSE 转成 Anthropic SSE 输出给客户端
   - 在桥接过程中识别最终 usage chunk，并在流结束后 `update_usage(request_id, usage)`

3. 最小落地可以只做“日志补写”，不强制改动客户端可见的 Anthropic 事件结构；若要更完整协议对齐，再让桥接器额外输出带 usage 的 `message_delta`

### 方案 A 实施结果

- 已按“最小可见变化”方案落地：
  - 发往 OpenAI 兼容上游的流式请求现在会自动注入 `stream_options.include_usage=true`
  - `anthropic -> openai` 桥接流在内部解析最终 OpenAI usage chunk
  - 流结束后按 `request_id` 回写 `request_logs`
- 当前没有额外改变客户端可见的 Anthropic 事件序列，只补了监测落库

对应实现：

- `crates/fluxd/src/http/anthropic_routes.rs`
  - 在 `chat_completions_stream` 请求前补 `stream_options.include_usage`
  - 新增 OpenAI stream usage tracker
  - 在桥接流结束后调用 `RequestLogService::update_usage(...)`

新增回归：

- `crates/fluxd/tests/anthropic_streaming_test.rs`
  - 验证上游收到 `stream_options.include_usage=true`
  - 验证消费完整流后 `request_logs` 写入 `10 / 2 / 12`

针对性验证：

```bash
cargo test -p fluxd --test anthropic_streaming_test -q
cargo test -p fluxd --test anthropic_native_streaming_test -q
cargo test -p fluxd --test anthropic_forwarding_test -q
```

结果：

- `anthropic_streaming_test`: 4/4 通过
- `anthropic_native_streaming_test`: 1/1 通过
- `anthropic_forwarding_test`: 10/10 通过

### 方案 B：再修 `openai -> openai`，但要明确兼容性取舍

原因：

- 代码缺口真实存在
- 但本机当前没有观察到 streaming 实流量

技术要求：

1. 上游请求必须加入：

```json
"stream_options": { "include_usage": true }
```

2. 透传流时要额外解析最终 OpenAI usage chunk，并在流结束后补写 `request_logs`

兼容性取舍：

- 开启 `include_usage` 后，客户端会看到额外的最终 usage chunk
- 这通常符合 OpenAI 官方语义，但属于对当前 passthrough 行为的可见变化

因此推荐两种落地方式：

- 保守：仅先修 `anthropic -> openai`
- 完整：同时修 `openai -> openai`，必要时用 `protocol_config_json` 开关控制是否强制注入 `include_usage`

### 方案 B 实施结果

- 已按“完整”方案落地 `openai -> openai` streaming usage 持久化
- 发往 OpenAI 上游的流式请求现在同样会自动注入 `stream_options.include_usage=true`
- 透传过程中解析最终 usage chunk，并在流结束后回写 `request_logs`

对应实现：

- `crates/fluxd/src/http/openai_routes.rs`
  - 在流式请求发出前补 `stream_options.include_usage`
  - 新增 OpenAI stream usage tracker
  - 在流结束后调用 `RequestLogService::update_usage(...)`

新增回归：

- `crates/fluxd/tests/openai_streaming_test.rs`
  - 验证上游收到 `stream_options.include_usage=true`
  - 验证消费完整流后 `request_logs` 写入 `10 / 2 / 12`

针对性验证：

```bash
cargo test -p fluxd --test openai_streaming_test -q
cargo test -p fluxd --test anthropic_streaming_test -q
cargo test -p fluxd --test anthropic_native_streaming_test -q
cargo test -p fluxd --test anthropic_forwarding_test -q
```

结果：

- `openai_streaming_test`: 2/2 通过
- `anthropic_streaming_test`: 4/4 通过
- `anthropic_native_streaming_test`: 1/1 通过
- `anthropic_forwarding_test`: 10/10 通过

## 当前结论

- `anthropic -> anthropic`、`anthropic -> openai`、`openai -> openai` 三条流式链路的 token 持久化都已补齐
- 已完成仓库要求的完整验证，其中 Rust 与 E2E 通过，前端测试存在一条与本次改动无关的既有失败
- 后续若要关闭某些 OpenAI 客户端可见的最终 usage chunk，需要单独讨论兼容性策略或配置开关

## 完整验证结果

已执行：

```bash
cargo test -q
cd apps/desktop && bun run test
./scripts/e2e/smoke.sh
```

结果：

- `cargo test -q`：通过
- `./scripts/e2e/smoke.sh`：通过，输出 `smoke ok`
- `cd apps/desktop && bun run test`：失败

前端失败详情：

- 文件：`apps/desktop/src/ui/monitor/TrendPanel.test.tsx`
- 用例：`TrendPanel > renders trend headings, time filters, and svg chart primitives`
- 断言：期望渲染结果包含 `<svg>`
- 实际：`apps/desktop/src/ui/monitor/TrendPanel.tsx` 在 `loading` 分支只渲染 `trend-panel__loading`，不会输出 `<svg>`

判断：

- 该失败位于前端监控面板静态渲染测试
- 本次改动仅涉及 `crates/fluxd/` 流式 usage 持久化与对应 Rust 测试
- 因此这条前端失败不属于本次流式 token 统计修复引入的问题
