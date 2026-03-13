# 2026-03-13 provider_quan2go token 缺失调查

## 现象

- 用户反馈 `Traffic` 趋势图只有 `GLM-5` 的 token，没有 `GPT-5.4`
- 日志中 `provider_quan2go` 的 `input_tokens / output_tokens / total_tokens` 持续为空

## 现场结论

- 不是前端图表漏显示
- 不是 Admin 聚合 SQL 漏算
- 不是 quan2go 不返回 usage
- 真正的问题在 `fluxd` 的 passthrough 流式识别

## 关键证据

### 数据库侧

- `request_logs` 中最近 `provider_quan2go` 的成功请求：
  - `status_code = 200`
  - `model = gpt-5.4`
  - `input_tokens/output_tokens/cached_tokens/total_tokens/usage_json = NULL`
- 最近 1 小时聚合：
  - `GLM-5` 有非零 token
  - `gpt-5.4` 请求很多，但 token 总和为 `0`

### 客户端侧

- `~/.codex/config.toml`
  - `wire_api = "responses"`
  - `base_url = "http://127.0.0.1:18081"`
- Codex 日志中的真实请求是大体量 `/responses` payload，不是简单的测试 JSON

### 上游侧

- 用真实 Codex payload 重放到：
  - `gateway_codex`
  - `https://capi.quan2go.com/openai/responses`
- 两者都返回：
  - `status = 200`
  - `content-type = text/plain; charset=UTF-8`
- 但响应体内容实际是 SSE：
  - `event: response.created`
  - `event: response.completed`
  - 尾事件中带完整 `response.usage`

示例 usage 片段：

```json
{
  "usage": {
    "input_tokens": 58580,
    "input_tokens_details": {
      "cached_tokens": 57728
    },
    "output_tokens": 435,
    "output_tokens_details": {
      "reasoning_tokens": 21
    },
    "total_tokens": 59015
  }
}
```

## 根因

`crates/fluxd/src/http/passthrough.rs` 当前只把 `content-type` 以 `text/event-stream` 开头的响应当作流式：

- quan2go 返回的是 **SSE body + text/plain header**
- 所以 FluxDeck 把它误判成“非流式”
- 随后 `extract_passthrough_usage(...)` 会尝试把整段 SSE 文本当作单个 JSON 解析
- JSON 解析失败后直接返回空 `UsageSnapshot`
- 最终 token 没有落库

## 影响

- `gateway_codex` 的 `gpt-5.4` token 监控全部失真
- `request_logs`、overview、by model、trend 图都会显示 `0`

## 后续修复建议

1. passthrough 流式识别不要只依赖 `Content-Type`
2. 对 `openai-response` 响应增加 SSE body sniff
3. 命中 SSE 后复用现有 `PassthroughStreamUsageTracker`
4. 补回归测试，覆盖“`text/plain` 头但 body 是 SSE 且包含 `response.completed.response.usage`”场景

## 2026-03-13 修复落地

- 已在 `crates/fluxd/src/http/passthrough.rs` 补充：
  - `text/event-stream` 之外的 SSE body sniff
  - 对 `openai` / `openai-response` / `anthropic` 的整段 SSE body usage 提取
- 对于 quan2go 这类“`text/plain` 头 + SSE body”的响应：
  - 现在会把 `request_logs.stream` 记为 `1`
  - 会从 `response.completed.response.usage` 回写 token

## 验证

- `cargo test -q -p fluxd --test openai_passthrough_fallback_test`
- `cargo test -q -p fluxd --test openai_streaming_test`
- `cargo test -q -p fluxd --test admin_api_test`

结果：

- 全部通过
