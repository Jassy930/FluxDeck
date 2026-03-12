# 2026-03-12 Gateway Codex By Model 漏统计

## 现象

- 原生前端 `Traffic` 页面 `By Model` 没有出现 `gateway_codex`
- 但 `gateway_codex` 实际持续有请求，且最近 1 小时存在成功记录

## 调查结论

- 前端 `By Model` 来自 `/admin/stats/overview.by_model`
- 后端 `by_model` 维度在 `crates/fluxd/src/http/admin_routes.rs` 中按 `request_logs.model_effective` 聚合
- `gateway_codex` 使用 `openai-response` passthrough 链路
- 该链路此前只记录协议、状态与 usage，没有写入：
  - `model`
  - `model_requested`
  - `model_effective`
- 因为 `by_model` 会过滤 `NULL model_effective`，所以 `gateway_codex` 的请求全部从模型统计中消失

## 本地证据

数据库：

- `~/.fluxdeck/fluxdeck.db`

核对结果：

```sql
SELECT gateway_id, COUNT(*) AS total,
       SUM(CASE WHEN model_effective IS NULL OR model_effective = '' THEN 1 ELSE 0 END) AS missing_effective,
       SUM(CASE WHEN model IS NULL OR model = '' THEN 1 ELSE 0 END) AS missing_model
FROM request_logs
WHERE gateway_id = 'gateway_codex'
GROUP BY gateway_id;
```

返回：

- `gateway_codex | 698 | 698 | 698`

## 修复

- 在 `crates/fluxd/src/http/passthrough.rs` 中新增 passthrough 模型提取
  - 从请求体提取 `model` 作为 `model` / `model_requested`
  - 非流式响应优先从响应体提取 `model` 作为 `model_effective`
  - 如果响应体没有显式模型，则回退到请求模型
- 新增回归测试：
  - `persists_model_dimensions_for_non_stream_openai_responses_fallback`

## 验证

已执行：

```bash
cargo test -q -p fluxd --test openai_passthrough_fallback_test
```

结果：

- 6 个用例全部通过
- 新增模型维度回归测试通过
