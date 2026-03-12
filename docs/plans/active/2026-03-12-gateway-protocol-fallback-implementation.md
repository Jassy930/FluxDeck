# Gateway Protocol Fallback Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 让 FluxDeck 在保持协议网关主架构的前提下，支持协议类型集合对齐，并为同协议未专门实现端点提供自动透传兜底。

**Architecture:** 保留现有 OpenAI / Anthropic 专门路由和上游客户端实现，在 HTTP 层补一层 passthrough fallback。只有 `inbound_protocol == upstream_protocol` 且未命中专门 handler 时，才触发通用透传；跨协议场景仍要求显式适配器。

**Tech Stack:** Rust, Axum, reqwest, SQLite, FluxDeck runtime/admin/test stack

---

## Execution Status

- Date: 2026-03-12
- Status: completed and locally verified
- Note: plan-step `git commit` actions were intentionally not executed in this session

## Verification Results

- `cargo test -q`：PASS
- `./scripts/e2e/smoke.sh`：PASS，输出包含 `cli-desktop consistency ok`、`anthropic compat ok`、`smoke ok`

## Completion Notes

- 已将 Gateway `inbound_protocol` / `upstream_protocol` 的协议值集合与 Provider `kind` 对齐
- 已在 `GatewayRepo` 增加协议值校验
- 已新增同协议 passthrough fallback：
  - `openai` 入口对未命中路径会走 fallback
  - 其它已支持但尚无专门 handler 的协议会使用通用 passthrough router
- 已补齐 OpenAI 系 `/responses` 与 `/v1/responses` 兼容
- 已为 passthrough 链路补最小请求日志
- 已同步更新契约、运行手册与 README

## Deferred Behavior

- 目前 passthrough 链路仅记录最小观测信息，不做深度 usage 解析
- 方案 C 仍保留为独立架构议题，未纳入本轮实现

### Task 1: 固化设计与待讨论 Issue

**Files:**
- Create: `docs/plans/active/2026-03-12-gateway-protocol-fallback-design.md`
- Modify: `docs/plans/active/2026-03-12-codex-gateway-responses-investigation.md`

**Step 1: 更新设计稿**

记录：

- 采用方案 B
- 方案 C 作为待讨论 issue 保留
- 同协议 passthrough fallback 的边界

**Step 2: 更新调查文档**

把修复入口调整为“协议网关优先 + 同协议透传兜底”，不再只停留于 `/responses` 单点补洞。

**Step 3: 自检**

确认设计文档与调查文档口径一致。

### Task 2: 先写协议集合与 fallback 分发红测试

**Files:**
- Modify: `crates/fluxd/tests/gateway_manager_test.rs`
- Create: `crates/fluxd/tests/openai_passthrough_fallback_test.rs`

**Step 1: 写协议集合/分发红测试**

新增测试覆盖：

- `openai-response` 可作为 Gateway 协议值保存并启动
- 未命中专门 handler 时不会立即 404

**Step 2: 写 fallback 透传红测试**

新增测试覆盖：

- `POST /responses`
- `POST /v1/responses`
- 原始响应状态码和 body 被透传

**Step 3: 运行测试确认失败**

Run: `cargo test -q -p fluxd --test gateway_manager_test --test openai_passthrough_fallback_test`

Expected: FAIL，原因是当前无 fallback 路由或协议值限制。

### Task 3: 实现协议类型集合对齐

**Files:**
- Modify: `crates/fluxd/src/domain/provider.rs`
- Modify: `crates/fluxd/src/domain/gateway.rs`
- Modify: `crates/fluxd/src/http/admin_routes.rs`
- Modify: `docs/contracts/admin-api-v1.md`

**Step 1: 收敛协议值常量**

抽出 Gateway 可用协议值集合，并与 Provider 类型定义对齐。

**Step 2: 更新 Admin API 校验与说明**

确保 `inbound_protocol` / `upstream_protocol` 的允许值与文档一致。

**Step 3: 运行相关测试**

Run: `cargo test -q -p fluxd --test admin_api_test --test gateway_manager_test`

Expected: PASS。

### Task 4: 为 OpenAI 系协议加入 passthrough fallback

**Files:**
- Create: `crates/fluxd/src/http/passthrough.rs`
- Modify: `crates/fluxd/src/http/openai_routes.rs`
- Modify: `crates/fluxd/src/forwarding/target_resolver.rs`
- Modify: `crates/fluxd/src/upstream/openai_client.rs`

**Step 1: 实现通用透传执行器**

支持：

- 原方法
- 原路径
- 原查询
- 原 body
- 过滤 hop-by-hop 头

**Step 2: 接入 OpenAI Router fallback**

优先保留显式路由，再对未命中路径使用 fallback。

**Step 3: 兼容 `/responses` 与 `/v1/responses`**

根据 provider `base_url` 规范化转发目标，避免双 `/v1`。

**Step 4: 运行测试**

Run: `cargo test -q -p fluxd --test openai_passthrough_fallback_test --test openai_forwarding_test`

Expected: PASS。

### Task 5: 补最小日志与错误语义

**Files:**
- Modify: `crates/fluxd/src/service/request_log_service.rs`
- Modify: `crates/fluxd/src/http/openai_routes.rs`
- Modify: `crates/fluxd/tests/request_log_service_test.rs`

**Step 1: 为 fallback 链路补最小观测**

至少记录：

- 协议维度
- 状态码
- 延迟
- 错误文本

**Step 2: 明确未支持跨协议错误**

对于未实现的跨协议组合，返回清晰错误而非 404。

**Step 3: 运行测试**

Run: `cargo test -q -p fluxd --test request_log_service_test --test openai_passthrough_fallback_test`

Expected: PASS。

### Task 6: 文档同步与阶段收尾

**Files:**
- Modify: `docs/USAGE.md`
- Modify: `docs/ops/local-runbook.md`
- Modify: `README.md`
- Modify: `docs/plans/active/2026-03-12-gateway-protocol-fallback-implementation.md`

**Step 1: 更新说明文档**

明确：

- Gateway 协议集合
- 同协议 fallback 行为
- `/responses` 兼容策略

**Step 2: 回填验证结果**

记录测试命令与结果。

**Step 3: 整理工作区**

Run: `git status --short`

Expected: 只包含本轮相关文档与代码变更。
