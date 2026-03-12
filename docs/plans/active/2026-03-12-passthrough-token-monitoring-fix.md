# Passthrough Token 监测修复计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 修复同协议 passthrough 链路的 token usage 未落库问题，使 `/responses` 等 fallback 请求在日志与监测面板中恢复 token 统计。

**Architecture:** 继续保留现有显式协议路由的 usage 采集逻辑，只补 passthrough 链路。对于非流式 JSON 响应，在返回客户端前解析 response body 中的 usage 并直接落库；对于 SSE 流式响应，先写入最小日志，再在流消费完成后解析最终 usage 并回写同一条 `request_logs` 记录。

**Tech Stack:** Rust, Axum, reqwest, SSE, SQLite, sqlx

---

## Execution Status

- Date: 2026-03-12
- Status: completed and locally verified
- Note: 本次只补 passthrough usage 持久化，不改 Admin API 契约字段

## Verification Results

- `cargo test -q -p fluxd --test openai_passthrough_fallback_test`：PASS
- `cargo test -q -p fluxd --test openai_streaming_test`：PASS
- `cargo test -q -p fluxd --test request_log_service_test`：PASS

### Task 1: 用红测固定 passthrough usage 缺口

**Files:**
- Modify: `crates/fluxd/tests/openai_passthrough_fallback_test.rs`

**Step 1: 新增非流式 `/responses` usage 落库测试**

覆盖：

- upstream JSON 响应携带 `usage.input_tokens/output_tokens/total_tokens`
- fallback 请求完成后，`request_logs` 中对应 token 字段不再为空

**Step 2: 新增流式 `/responses` usage 回写测试**

覆盖：

- upstream SSE 最终发送 `response.completed`
- 事件中的 `response.usage` 会在流结束后回写到 `request_logs`

**Step 3: 运行测试确认失败**

Run: `cargo test -q -p fluxd --test openai_passthrough_fallback_test`

Expected: FAIL，原因是当前 passthrough 只记最小日志，不解析 usage。

### Task 2: 扩展 OpenAI usage 提取口径

**Files:**
- Modify: `crates/fluxd/src/forwarding/openai_inbound.rs`

**Step 1: 支持 Responses API usage 形状**

兼容提取：

- `prompt_tokens` / `completion_tokens`
- `input_tokens` / `output_tokens`
- `input_tokens_details.cached_tokens`

**Step 2: 保持现有 chat completions 行为不回退**

确保已有 OpenAI chat/completions 测试继续通过。

### Task 3: 为 passthrough 链路补 usage 持久化

**Files:**
- Modify: `crates/fluxd/src/http/passthrough.rs`
- Modify: `crates/fluxd/src/service/request_log_service.rs`

**Step 1: 非流式 JSON 响应在返回前解析 usage**

仅在成功响应且内容可解析时写入 usage，错误路径保持最小日志。

**Step 2: 流式 SSE 响应增加 usage tracker**

至少支持 OpenAI Responses SSE：

- 解析 `data:` 行中的 JSON 事件
- 从 `response.completed` 的 `response.usage` 提取 token
- 流结束后调用 `update_usage()`

**Step 3: 保持原始状态码、头与 body 透传**

不能因为补 usage 而改变 passthrough 对客户端的协议表现。

### Task 4: 验证、文档同步与收尾

**Files:**
- Modify: `docs/progress/2026-03-12-gateway-protocol-fallback.md`
- Modify: `docs/progress/2026-03-12-native-logs-workbench-redesign.md`
- Modify: `docs/contracts/admin-api-v1.md`（如需调整契约说明）

**Step 1: 运行针对性测试**

Run:

- `cargo test -q -p fluxd --test openai_passthrough_fallback_test`
- `cargo test -q -p fluxd --test openai_streaming_test --test request_log_service_test`

Expected: PASS。

**Step 2: 更新进展文档**

明确：

- passthrough 现在支持 usage 解析与回写
- 当前已覆盖 OpenAI `/responses` JSON 与 SSE 两类 usage

**Step 3: 整理工作区并检查 git 状态**

Run: `git status --short`

Expected: 只包含本轮相关代码与文档变更。
