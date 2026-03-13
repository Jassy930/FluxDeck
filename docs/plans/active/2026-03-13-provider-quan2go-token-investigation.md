# Provider quan2go Token 缺失调查

**Goal:** 调查 `provider_quan2go` / `gpt-5.4` 在 `request_logs`、监测概览与趋势图中 token 持续为 `0` 的根因，并明确修复入口。

**Architecture:** 沿 `Codex CLI -> gateway_codex(openai-response passthrough) -> provider_quan2go -> request_logs` 链路逐层取证，先确认源日志是否已有 token，再确认真实 upstream 响应形状与 `fluxd` passthrough 的流式识别条件是否匹配。

**Tech Stack:** Rust, Axum, reqwest, SQLite, Codex CLI, FluxDeck admin/runtime

---

## Execution Status

- Date: 2026-03-13
- Status: investigation completed
- Note: 本轮只完成根因定位与修复入口梳理，未修改运行时代码

## 已确认现象

- `provider_quan2go` 最近成功请求持续写入 `status_code=200`
- 但 `input_tokens / output_tokens / cached_tokens / total_tokens / usage_json` 全部为空
- 原生端 Traffic 图只出现 `GLM-5`，没有 `gpt-5.4`

## 证据链

### 1. 源日志没有 token，不是前端图表吞掉数据

- 数据库查询显示最近 `provider_quan2go` / `gpt-5.4` 请求的 token 字段全空
- 最近 1 小时按模型聚合：
  - `GLM-5` 有非零 `total_tokens`
  - `gpt-5.4` 请求数很多，但 `total_tokens=0`

### 2. `gateway_codex` 真实走的是 `openai-response -> passthrough`

- `providers.kind = openai-response`
- `gateways.id = gateway_codex`
- `gateways.inbound_protocol = openai-response`
- 运行时会落到 `build_passthrough_router(...)`

### 3. Codex CLI 的真实请求不是简单的 `{model,input}`

- `~/.codex/config.toml` 使用：
  - `wire_api = "responses"`
  - `base_url = "http://127.0.0.1:18081"`
- Codex 本地日志表明，真实请求是一个很大的 `/responses` payload，包含：
  - `model = gpt-5.4`
  - `instructions`
  - `tools`
  - `store = false`
  - `stream = true`

### 4. quan2go 对真实 Codex 请求返回的是 SSE 事件流，但 `Content-Type` 错了

- 用真实 Codex payload 重放到：
  - `http://127.0.0.1:18081/responses`
  - `https://capi.quan2go.com/openai/responses`
- 两边都返回：
  - `status = 200`
  - `content-type = text/plain; charset=UTF-8`
- 响应体内容却是标准 SSE 形状：
  - `event: response.created`
  - `event: response.completed`

### 5. SSE 尾事件里确实带了 usage

- 重放响应末尾能看到：
  - `event: response.completed`
  - `response.usage.input_tokens`
  - `response.usage.output_tokens`
  - `response.usage.total_tokens`
  - `response.usage.input_tokens_details.cached_tokens`
- 说明 upstream 并不是“不返回 usage”

### 6. `fluxd` 当前只把 `text/event-stream` 当成流式

- `crates/fluxd/src/http/passthrough.rs`
- `is_stream` 当前只判断：
  - `content-type.starts_with("text/event-stream")`
- quan2go 返回 `text/plain`
- 结果：
  - passthrough 把它误判为“非流式”
  - `request_logs.stream = 0`
  - 不会进入 `track_passthrough_stream_usage(...)`

### 7. 被误判为非流式后，usage 提取又要求整个 body 必须是 JSON

- `extract_passthrough_usage(...)` 先做：
  - `serde_json::from_slice(response_body)`
- 但 quan2go 实际返回的是整段 SSE 文本，不是单个 JSON 对象
- 因此 JSON 解析直接失败，函数返回 `Default::default()`

## 根因结论

`provider_quan2go` 的 token 为 `0`，不是因为图表没显示，也不是因为 quan2go 不返回 usage，而是因为：

1. quan2go 对真实 Codex `/responses` 请求返回了 **SSE 事件流**
2. 但响应头错误地标成了 **`text/plain; charset=UTF-8`**
3. `fluxd` passthrough 仅凭 `Content-Type == text/event-stream` 判断流式
4. 于是这条请求被误当成“非流式 JSON”
5. 随后的 usage 提取对整段 SSE 文本执行 JSON 解析，必然失败
6. 最终 `request_logs` 写入空 usage，导致日志、overview、trend、图表全部显示 `0`

## 影响范围

- `gateway_codex`
- 所有走 `openai-response` passthrough 且上游返回 `text/plain` SSE 的 provider
- 监测概览、By Model、趋势图、日志详情中的 token 指标

## 修复入口

1. 扩展 `crates/fluxd/src/http/passthrough.rs` 的流式识别逻辑
   - 不能只看 `text/event-stream`
   - 对 `openai-response` / `openai` 响应可增加 body 前缀或首块 sniff
   - 若响应体以 `event:` / `data:` 开头，应按 SSE 处理

2. 为“错误 `Content-Type` 的 SSE”复用现有 `PassthroughStreamUsageTracker`
   - 这样可以继续从 `response.completed.response.usage` 回写 token

3. 增加回归测试
   - `openai-response` 成功响应 `content-type=text/plain`
   - body 为 SSE
   - 末尾包含 `response.completed.response.usage`
   - 断言 `request_logs` 最终写入 token 且 `stream=1`
