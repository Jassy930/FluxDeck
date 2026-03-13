# Passthrough First Byte 缺失调查

**Goal:** 调查 `gateway_codex` 日志中 `first_byte_ms` 缺失的根因，并明确后续修复入口。

**Architecture:** 先对比显式协议处理链路与 passthrough 链路的日志写入路径，再确认 `gateway_codex` 实际使用的运行时 Router。重点核对 `request_logs.first_byte_ms` 在各条链路中的赋值位置。

**Tech Stack:** Rust, Axum, reqwest, SQLite, SwiftUI

---

## Execution Status

- Date: 2026-03-12
- Status: investigation completed
- Note: 本轮仅完成根因定位与修复入口梳理，未修改运行时代码

## 已确认现象

- 原生日志工作台在 `gateway_codex` 请求详情里显示 `First Byte = -`
- `request_logs` 表与 Admin API 契约都已经具备 `first_byte_ms` 字段

## 证据链

1. 原生前端会直接显示后端返回的 `first_byte_ms`
   - `apps/desktop-macos-native/FluxDeckNative/Features/LogsWorkbenchView.swift`
   - `first_byte_ms == null` 时会渲染为 `-`

2. 显式 OpenAI / Anthropic 协议链路都会写入 `observation.first_byte_ms`
   - `crates/fluxd/src/http/openai_routes.rs`
   - `crates/fluxd/src/forwarding/openai_inbound.rs`
   - `crates/fluxd/src/forwarding/anthropic_inbound.rs`

3. passthrough 链路统一走 `append_passthrough_log()`
   - `crates/fluxd/src/http/passthrough.rs`
   - 该函数会写入 `status_code` 与 `latency_ms`
   - 但没有任何地方给 `observation.first_byte_ms` 赋值

4. `gateway_codex` 当前使用 passthrough Router
   - `crates/fluxd/src/runtime/gateway_manager.rs`
   - 对 `openai-response` 等协议，运行时会挂载 `build_passthrough_router(...)`

## 根因结论

- `gateway_codex` 的请求日志不是前端漏显示，而是后端 passthrough 链路根本没有持久化 `first_byte_ms`
- 因为 `append_passthrough_log()` 不写 `observation.first_byte_ms`，所以所有走 passthrough 的请求都会在日志里丢失该字段
- 这不是 `gateway_codex` 独有问题，而是 passthrough 链路的通用字段遗漏

## 影响范围

- `openai-response` / Codex 类 Gateway
- 其他所有走 `build_passthrough_router(...)` 的协议
- 包括非流式 JSON passthrough 与流式 SSE passthrough

## 修复入口

1. 在 `crates/fluxd/src/http/passthrough.rs` 的 `append_passthrough_log()` 中补齐 `first_byte_ms`
2. 语义与现有链路保持一致：
   - 流式请求：使用 `upstream.send().await` 返回后、开始转发响应前的耗时
   - 非流式请求：与当前 OpenAI/Anthropic 非流式实现保持一致，可回落为 `latency_ms`
3. 在 `crates/fluxd/tests/openai_passthrough_fallback_test.rs` 中增加回归测试，覆盖：
   - `/responses` 非流式请求会写入 `first_byte_ms`
   - `/responses` 流式请求会写入 `first_byte_ms`
