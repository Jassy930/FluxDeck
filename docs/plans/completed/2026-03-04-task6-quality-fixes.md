# Task6 质量修复记录（本轮）

日期：2026-03-04  
范围：Anthropic `stream=true` 增量流式转发与上游 SSE 错误提取

## 修复目标

1. 修复 `stream=true` 路径整包读取后一次性返回的问题，改为边读上游边输出 Anthropics SSE。
2. 优化上游流式错误体解析：若错误在 `data: {...}` SSE 包装中，优先提取结构化 `message`。

## 实施内容

### A) 真正增量流式输出

- 在 OpenAI 侧新增可增量喂入的 `OpenAiSseDecoder`：
  - 支持 `push_chunk(&[u8])` 按块解码 `data:` 行；
  - 支持 `finish()` 收尾补齐 `MessageStart/MessageStop`。
- 在 Anthropic 侧新增状态化 `AnthropicSseEncoder`：
  - `encode_event(&StreamEvent)` 按事件即时编码；
  - 保证 `message_start -> content_block_start/delta -> content_block_stop -> message_stop` 顺序。
- `anthropic_routes` 的 `stream=true` 分支改为：
  - 上游成功后直接 `bytes_stream()`；
  - 经 `map_upstream_to_anthropic_stream(...)` 实时转换；
  - 下游以 `Body::from_stream(...)` + `text/event-stream` 返回。

### B) SSE 包装错误提取

- `extract_upstream_error_message_from_text` 增强：
  - 先尝试整段 JSON；
  - 再逐行识别 `data: ...` 并对每个 JSON 片段提取 `error.message`/`message`；
  - 避免把整段 `data: {...}` 原文直接回传给客户端。

## TDD 证据

### RED

命令：

```bash
cargo test -p fluxd --test anthropic_streaming_test -q
```

失败点：
- `streams_first_anthropic_event_before_upstream_completes`（网关未在短超时内返回首包）
- `extracts_sse_wrapped_upstream_error_message`（错误消息被回传为原始 `data: {...}`）

### GREEN

命令：

```bash
cargo test -p fluxd --test anthropic_streaming_test -q
cargo test -p fluxd -q
```

结果：全部通过。
