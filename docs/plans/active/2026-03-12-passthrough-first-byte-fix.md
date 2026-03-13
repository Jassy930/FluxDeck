# Passthrough First Byte 修复计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 修复共享 passthrough 转发链路未持久化 `first_byte_ms` 的问题，使 `/responses` 等 fallback 请求在日志中恢复首包耗时字段。

**Architecture:** 保持现有显式协议处理链路不变，只在共享 `passthrough` 日志层补齐 `first_byte_ms`。语义与现有实现保持一致：流式请求记录拿到上游 `Response` 的时间，非流式请求回落为最终 `latency_ms`，从而避免改变对客户端的转发行为。

**Tech Stack:** Rust, Axum, reqwest, SQLite, sqlx

---

## Execution Status

- Date: 2026-03-12
- Status: completed and locally verified
- Note: 本次仅修复共享 passthrough 的 `first_byte_ms` 持久化，不改 Admin API 契约字段

### Task 1: 用红测固定 passthrough first byte 缺口

**Files:**
- Modify: `crates/fluxd/tests/openai_passthrough_fallback_test.rs`

**Step 1: 新增非流式 `/responses` first byte 落库测试**

覆盖：

- passthrough 非流式请求完成后，`request_logs.first_byte_ms` 不再为空
- 非流式场景下 `first_byte_ms` 与当前实现语义一致，可等于最终 `latency_ms`

**Step 2: 新增流式 `/responses` first byte 落库测试**

覆盖：

- passthrough SSE 请求在开始转发前即写入日志
- `request_logs.first_byte_ms` 不再为空

**Step 3: 运行测试确认失败**

Run: `cargo test -q -p fluxd --test openai_passthrough_fallback_test first_byte`

Expected: FAIL，原因是当前 passthrough 日志没有写入 `first_byte_ms`

### Task 2: 为共享 passthrough 日志补齐 first byte

**Files:**
- Modify: `crates/fluxd/src/http/passthrough.rs`

**Step 1: 扩展 `append_passthrough_log()` 参数**

- 增加 `first_byte_ms: Option<i64>`
- 在构造 `ForwardObservation` 时写入 `observation.first_byte_ms`

**Step 2: 在成功转发路径传入一致的 first byte 语义**

- 流式请求：使用 `upstream.send().await` 返回后、写日志前的耗时
- 非流式请求：沿用当前 JSON 路径语义，回落为最终 `latency_ms`

**Step 3: 错误路径维持最小日志**

- 解析/网络失败等错误路径保持 `None`
- 不额外改变现有错误分类与响应行为

### Task 3: 运行验证并同步文档

**Files:**
- Modify: `docs/progress/2026-03-12-gateway-codex-first-byte-investigation.md`

**Step 1: 运行针对性测试**

Run:

- `cargo test -q -p fluxd --test openai_passthrough_fallback_test`

Expected: PASS

**Step 2: 更新进度文档**

- 记录共享 passthrough 已补齐 `first_byte_ms`
- 明确覆盖了 `/responses` 的流式与非流式场景

**Step 3: 整理工作区并检查 git 状态**

Run: `git status --short`

Expected: 只包含本轮相关代码与文档变更

## Verification Results

- `cargo test -q -p fluxd --test openai_passthrough_fallback_test first_byte`：PASS
- `cargo test -q -p fluxd --test openai_passthrough_fallback_test`：PASS
