# Anthropic Base URL Normalization Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 修复 `anthropic` 上游在 provider `base_url` 未包含 `/v1` 时的路径拼接错误，避免 Claude Code 经由 `anthropic -> anthropic` 网关出现“发消息无反馈、无显式报错”。

**Architecture:** 保持现有 provider 存储结构不变，只在 `AnthropicClient` 内部统一规范化 URL 前缀：若 `base_url` 未以 `/v1` 结尾，则自动补上 `/v1` 后再拼接 `messages` 与 `messages/count_tokens`。回归测试覆盖非流式、流式、count_tokens 三条路径，文档补充 `anthropic` provider 的 `base_url` 语义。

**Tech Stack:** Rust, axum, reqwest, sqlx, SQLite

---

### Task 1: 记录并固化回归场景

**Files:**
- Modify: `crates/fluxd/tests/anthropic_native_forwarding_test.rs`
- Modify: `crates/fluxd/tests/anthropic_native_streaming_test.rs`
- Modify: `crates/fluxd/tests/anthropic_count_tokens_test.rs`

**Step 1: 写失败测试，覆盖 provider `base_url` 不带 `/v1` 的 anthropic native 请求**

新增测试至少覆盖：

- `/v1/messages` 非流式可成功返回 Anthropic `message`
- `/v1/messages` 流式可返回 Anthropic SSE 事件
- `/v1/messages/count_tokens` 可命中上游 count_tokens

**Step 2: 运行针对性测试，确认它们先失败**

Run: `cargo test -p fluxd anthropic_native -- --nocapture`

Expected: FAIL，表现为请求落到错误路径或返回 `404_NOT_FOUND` / `missing input_tokens`。

### Task 2: 实现最小修复

**Files:**
- Modify: `crates/fluxd/src/upstream/anthropic_client.rs`

**Step 1: 在 AnthropicClient 中抽出 URL 归一化逻辑**

实现内容：

- 去掉尾部 `/`
- 若 base URL 未以 `/v1` 结尾，则自动追加 `/v1`
- 统一由 helper 生成 `messages` / `messages/count_tokens` URL

**Step 2: 运行针对性测试，确认回归通过**

Run: `cargo test -p fluxd anthropic_native -- --nocapture`

Expected: PASS

### Task 3: 同步文档与排查记录

**Files:**
- Modify: `docs/ops/local-runbook.md`
- Modify: `docs/contracts/admin-api-v1.md`
- Modify: `docs/progress/2026-03-11-fluxd-stats-debug.md`

**Step 1: 补充 anthropic provider `base_url` 语义说明**

说明：

- FluxDeck 现在兼容 `https://host/api/anthropic` 与 `https://host/api/anthropic/v1`
- 运行中的 Gateway 仍需 `stop -> start` 才会加载新配置

**Step 2: 记录这次 GLMGLM 根因与验证证据**

记录内容：

- `GLMGLM` 最近请求为 `anthropic -> anthropic`
- 错误路径返回 `{"code":500,"msg":"404_NOT_FOUND","success":false}`
- 正确路径 `/v1/messages` 可直接返回 Anthropic message

**Step 3: 运行验证并整理工作区**

Run: `cargo test -p fluxd anthropic_native -- --nocapture`

Expected: PASS
