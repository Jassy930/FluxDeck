# Task5 审查问题修复记录（本轮）

日期：2026-03-04  
范围：Anthropic 非流式转发映射与本地编码错误分类

## 修复目标

1. 修复 OpenAI `message.tool_calls` 到 Anthropic `content.tool_use` 的映射缺失。
2. 修复 IR->OpenAI 本地编码失败被误归类为 `502/api_error` 的问题，改为 `400/invalid_request_error`。

## 实施内容

### A) `tool_calls` 映射

- 在 `anthropic` 非流式响应映射中读取 `choices[0].message.tool_calls`。
- 生成 Anthropic `tool_use` block，包含：
  - `type: "tool_use"`
  - `id`
  - `name`
  - `input`
- 对 `function.arguments` 做 JSON 解析：
  - 可解析时输出结构化 JSON；
  - 不可解析时回退为 `{ "raw": ... }`。
- 仅当 `content` 内存在 `tool_use` block 时，`stop_reason` 才映射为 `tool_use`，避免出现不一致状态。

### B) 本地编码失败分类

- 在路由层先执行 `encode_openai_chat_request`。
- 若编码失败（请求尚未发往上游）：
  - 返回 `400`
  - 返回 `invalid_request_error`
- 仅上游网络/HTTP 层失败继续保持 `502/api_error`。

## TDD 证据

### RED（先失败）

命令：

```bash
cargo test -p fluxd --test anthropic_forwarding_test -q
```

结果：新增 2 条用例失败
- `maps_openai_tool_calls_to_anthropic_tool_use_blocks`
- `returns_bad_request_for_local_openai_encoding_failure`

### GREEN（修复后通过）

命令：

```bash
cargo test -p fluxd --test anthropic_forwarding_test -q
cargo test -p fluxd -q
```

结果：均通过。

## 本轮补充（tool_use.input 对象化）

- 问题：当 OpenAI `function.arguments` 为合法 JSON 但非对象（例如数组）时，之前会直接透传，导致 Anthropic `tool_use.input` 不是 object。
- 修复：
  - 若 arguments 是 object：直接使用；
  - 若是合法 JSON 但非 object：包装为 `{ "_value": <parsed> }`；
  - 若解析失败：包装为 `{ "_raw": "..." }`。
- 结果：`tool_use.input` 始终为 JSON object。

### 本轮 TDD

- RED：新增 `wraps_non_object_tool_call_arguments_into_object_input`，先失败（`input.is_object()` 断言失败）。
- GREEN：修复后定向测试与 `cargo test -p fluxd -q` 全部通过。
