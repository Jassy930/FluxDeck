# Gateway Codex By Model 漏统计调查

**Goal:** 调查原生前端 `Traffic` 页面 `By Model` 维度未展示 `gateway_codex` 模型的根因，并在统计链路中补齐缺失的模型维度采集。

**Architecture:** 前端 `By Model` 直接消费 `/admin/stats/overview.by_model`，后端该字段按 `request_logs.model_effective` 聚合。调查重点放在 `gateway_codex` 使用的 OpenAI Responses passthrough 链路，确认模型名是否写入 `request_logs`。

**Tech Stack:** SwiftUI, Rust, Axum, SQLite, sqlx

---

## Execution Status

- Date: 2026-03-12
- Status: completed and locally verified
- Note: 本次未修改 Admin API 契约，只补齐 passthrough 日志中的模型维度采集

## 现象

- 前端 `Traffic -> By Model` 没有出现 `gateway_codex` 的模型
- `gateway_codex` 最近请求实际存在，且请求成功率正常

## 已确认根因

1. `/admin/stats/overview` 的 `by_model` 聚合只读取 `request_logs.model_effective`
2. `gateway_codex` 当前走 `openai-response -> passthrough` 链路
3. passthrough 写日志时只落了协议、状态码、usage，没有写入：
   - `model`
   - `model_requested`
   - `model_effective`
4. `by_model` 聚合对 `NULL model_effective` 会直接过滤，因此 `gateway_codex` 请求全部从模型维度消失

## 本地证据

- 数据库：`~/.fluxdeck/fluxdeck.db`
- 核对 SQL：

```sql
SELECT gateway_id, COUNT(*) AS total,
       SUM(CASE WHEN model_effective IS NULL OR model_effective = '' THEN 1 ELSE 0 END) AS missing_effective,
       SUM(CASE WHEN model IS NULL OR model = '' THEN 1 ELSE 0 END) AS missing_model
FROM request_logs
WHERE gateway_id = 'gateway_codex'
GROUP BY gateway_id;
```

- 当前结果：
  - `gateway_codex | 698 | 698 | 698`

## 修复范围

1. 为 passthrough 非流式响应补齐请求/响应模型提取
2. 为 passthrough SSE 响应补齐模型维度回写
3. 增加回归测试，确保 `openai-response` fallback 日志具备模型维度
4. 更新调查与进度文档

## Verification Results

- `cargo test -q -p fluxd persists_model_dimensions_for_non_stream_openai_responses_fallback --test openai_passthrough_fallback_test`：PASS
- `cargo test -q -p fluxd --test openai_passthrough_fallback_test`：PASS
