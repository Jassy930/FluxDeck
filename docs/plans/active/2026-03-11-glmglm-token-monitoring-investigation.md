# GLMGLM Token Monitoring Investigation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 调查 `GLMGLM` gateway 的 token 数量为何未进入 FluxDeck 监测面板，并给出根因与修复方向。

**Architecture:** 先以 `request_logs` 为系统事实源，核对 `GLMGLM` 最近请求的 `stream/input_tokens/output_tokens/total_tokens` 落库情况；再沿 `gateway route -> protocol adapter -> request_log_service -> admin stats` 单向追踪 token 使用量，确认问题发生在上游响应、流式解码还是统计聚合阶段。

**Tech Stack:** Rust, axum, reqwest, sqlx, SQLite

---

### Task 1: 固化现场证据

**Files:**
- Modify: `docs/progress/2026-03-11-glmglm-token-monitoring.md`

**Step 1: 查询本地 `fluxdeck.db` 中 `GLMGLM` gateway 与最近请求记录**

关注字段：

- `gateway_id`
- `inbound_protocol`
- `upstream_protocol`
- `stream`
- `status_code`
- `input_tokens`
- `output_tokens`
- `total_tokens`
- `usage_json`

**Step 2: 统计“流式请求是否存在 token”与“非流式请求是否存在 token”**

目标：

- 判断是否为监测聚合问题，还是 `request_logs` 源数据就缺失 token
- 记录时间范围内 `GLMGLM` 的成功请求模式

### Task 2: 追踪 token 数据流

**Files:**
- Modify: `docs/progress/2026-03-11-glmglm-token-monitoring.md`
- Read: `crates/fluxd/src/http/openai_routes.rs`
- Read: `crates/fluxd/src/http/anthropic_routes.rs`
- Read: `crates/fluxd/src/forwarding/openai_inbound.rs`
- Read: `crates/fluxd/src/forwarding/anthropic_inbound.rs`
- Read: `crates/fluxd/src/protocol/adapters/openai/stream_decoder.rs`
- Read: `crates/fluxd/src/service/request_log_service.rs`
- Read: `crates/fluxd/src/http/admin_routes.rs`

**Step 1: 对照非流式路径**

确认：

- 哪些路径调用 `extract_usage` / `extract_anthropic_usage`
- 哪些字段最终写入 `request_logs`

**Step 2: 对照流式路径**

确认：

- 成功流式请求是否始终以 `usage: Default::default()` 写库
- 现有 stream decoder / encoder 是否解析 usage 事件但未落库

### Task 3: 形成结论与修复方向

**Files:**
- Modify: `docs/progress/2026-03-11-glmglm-token-monitoring.md`

**Step 1: 给出根因分类**

至少区分：

- FluxDeck 流式链路自身未统计 token
- GLM Anthropic 兼容响应可能未返回非流式 usage
- Admin 统计层并非首要故障点

**Step 2: 记录后续修复候选**

至少包含：

- 为流式 OpenAI / Anthropic 路由追加 usage 采集与落库
- 若上游不返回 usage，则评估 fallback 估算或额外 count_tokens 补采

**Step 3: 整理工作区并检查 git 状态**

Run: `git status --short`

Expected: 仅包含本次新增或修改的文档文件，若无代码修复则不引入额外变更。
