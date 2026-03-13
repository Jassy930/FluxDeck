# Provider quan2go Token 修复计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 修复 `gateway_codex -> provider_quan2go` 链路中 `gpt-5.4` token 未落库的问题，使错误 `Content-Type` 的 SSE `/responses` 响应也能被识别并回写 usage。

**Architecture:** 保持现有 `openai-response` passthrough 透传行为不变，只补充对“body 是 SSE、header 却不是 `text/event-stream`”的识别。先用红测固定 `text/plain + response.completed.usage` 场景，再在 `passthrough` 中增加流式 sniff，并复用现有 `PassthroughStreamUsageTracker` 做最终 usage 回写。

**Tech Stack:** Rust, Axum, reqwest, SSE, SQLite, sqlx

---

## Execution Status

- Date: 2026-03-13
- Status: completed and locally verified
- Note: 本次只修运行时 token 落库，不改 Admin API 契约字段

### Task 1: 用红测固定错误 `Content-Type` 的 SSE usage 缺口

**Files:**
- Modify: `crates/fluxd/tests/openai_passthrough_fallback_test.rs`

**Step 1: 新增 `text/plain` SSE fallback usage 测试**

覆盖：

- upstream `/v1/responses` 返回 `content-type = text/plain; charset=utf-8`
- body 实际是 SSE 事件流
- 尾事件是 `response.completed`
- `response.completed.response.usage` 携带 token

**Step 2: 新增 `stream` 字段断言**

确认修复后：

- `request_logs.stream = 1`
- `input_tokens / output_tokens / cached_tokens / total_tokens` 已回写

**Step 3: 运行测试确认失败**

Run:

```bash
cargo test -q -p fluxd --test openai_passthrough_fallback_test text_plain_sse
```

Expected:

- FAIL
- 当前行为会把该响应误判为非流式

### Task 2: 为 passthrough 增加 SSE body sniff

**Files:**
- Modify: `crates/fluxd/src/http/passthrough.rs`

**Step 1: 提取流式判定逻辑**

把“是否按流式处理”的判断从单纯的 `Content-Type` 检查升级为：

- `text/event-stream` 直接判定为流式
- 对 `openai` / `openai-response` 成功响应，如果 body 看起来以 `event:` / `data:` 开头，也判定为流式

**Step 2: 为被 sniff 命中的响应走 usage tracker**

要求：

- 继续原样透传 header 和 body
- 保留 `response.completed.response.usage` 提取逻辑
- 最终调用 `update_usage()`

**Step 3: 避免破坏原有 JSON fallback**

非 SSE JSON 响应仍走现有 `extract_passthrough_usage(...)` 逻辑，不扩大行为面。

### Task 3: 验证回归并同步文档

**Files:**
- Modify: `docs/progress/2026-03-13-provider-quan2go-token-investigation.md`

**Step 1: 运行针对性测试**

Run:

```bash
cargo test -q -p fluxd --test openai_passthrough_fallback_test
```

Expected:

- PASS

**Step 2: 运行核心回归**

Run:

```bash
cargo test -q -p fluxd --test openai_streaming_test
cargo test -q -p fluxd --test admin_api_test
```

Expected:

- PASS

**Step 3: 更新进展文档**

补充：

- quan2go 的根因是 `text/plain` 头误导了流式识别
- 现在 passthrough 已支持该类 SSE 响应的 usage 回写

**Step 4: 整理工作区并检查 git 状态**

Run:

```bash
git status --short
```

Expected:

- 只包含本轮相关代码与文档改动

## Verification Results

- `cargo test -q -p fluxd --test openai_passthrough_fallback_test`：PASS
- `cargo test -q -p fluxd --test openai_streaming_test`：PASS
- `cargo test -q -p fluxd --test admin_api_test`：PASS
