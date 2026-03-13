# Request Log First Byte 历史补数计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为本地 `request_logs` 历史数据中缺失的 `first_byte_ms` 做一次性补数，恢复日志工作台对旧记录的展示。

**Architecture:** 不修改数据库 schema，不引入迁移。仅对本地 SQLite 数据库执行一次事务性回填：凡是 `first_byte_ms IS NULL` 且 `latency_ms IS NOT NULL` 的记录，统一用 `latency_ms` 填充。对非流式这是等价回填；对流式这是用户接受的近似值。

**Tech Stack:** SQLite, sqlite3 CLI

---

## Execution Status

- Date: 2026-03-12
- Status: completed and locally verified
- Note: 这是本地数据修复动作，不会影响仓库 schema 与 API 契约

### Task 1: 核对影响范围并备份数据库

**Files:**
- Modify: `~/.fluxdeck/fluxdeck.db`（运行时数据库）

**Step 1: 统计待补数行数**

Run:

- `sqlite3 "$HOME/.fluxdeck/fluxdeck.db" "SELECT COUNT(*) FROM request_logs WHERE first_byte_ms IS NULL AND latency_ms IS NOT NULL;"`

**Step 2: 备份数据库**

Run:

- `cp "$HOME/.fluxdeck/fluxdeck.db" "$HOME/.fluxdeck/fluxdeck.db.bak.first-byte-2026-03-12"`

### Task 2: 执行一次性回填

**Files:**
- Modify: `~/.fluxdeck/fluxdeck.db`

**Step 1: 用事务执行回填**

Run:

- `sqlite3 "$HOME/.fluxdeck/fluxdeck.db" "BEGIN; UPDATE request_logs SET first_byte_ms = latency_ms WHERE first_byte_ms IS NULL AND latency_ms IS NOT NULL; SELECT changes(); COMMIT;"`

**Step 2: 按 gateway / stream 复核结果**

Run:

- `sqlite3 "$HOME/.fluxdeck/fluxdeck.db" "SELECT gateway_id, COALESCE(stream,0) AS stream, COUNT(*) AS remaining FROM request_logs WHERE first_byte_ms IS NULL AND latency_ms IS NOT NULL GROUP BY gateway_id, COALESCE(stream,0) ORDER BY gateway_id, stream;"`

Expected: 无结果

### Task 3: 更新文档并整理工作区

**Files:**
- Modify: `docs/progress/2026-03-12-gateway-codex-first-byte-investigation.md`

**Step 1: 记录补数范围与结果**

- 写明本次回填规则与影响行数

**Step 2: 检查工作区状态**

Run:

- `git status --short`

## Verification Results

- 备份已创建：`~/.fluxdeck/fluxdeck.db.bak.first-byte-2026-03-12`
- `SELECT COUNT(*) FROM request_logs WHERE first_byte_ms IS NULL AND latency_ms IS NOT NULL;`（回填前）：`1159`
- `UPDATE request_logs SET first_byte_ms = latency_ms WHERE first_byte_ms IS NULL AND latency_ms IS NOT NULL;` 实际更新：`1159`
- `SELECT COUNT(*) FROM request_logs WHERE first_byte_ms IS NULL AND latency_ms IS NOT NULL;`（回填后）：`0`
