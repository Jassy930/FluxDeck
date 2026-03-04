# Anthropic 兼容模式 E2E 校验

本文档说明如何验证 Anthropic 入站网关在三种兼容模式下的行为：

- `strict`：拒绝不受支持的扩展能力（返回 `capability_error`）
- `compatible`：在上游不支持时降级（例如 `count_tokens` 本地估算）
- `permissive`：允许扩展字段透传到上游

## 前置条件

1. `fluxd` 已启动，Admin API 可访问
2. 可访问一个 OpenAI 兼容上游（本仓库可使用 `scripts/e2e/mock_openai.py`）

## 直接执行

```bash
uv run python scripts/e2e/anthropic_compat.py \
  --admin-url http://127.0.0.1:7777 \
  --upstream-base-url http://127.0.0.1:18000/v1
```

成功输出：

```text
anthropic compat ok
```

## 覆盖场景

脚本会自动创建 1 个 Provider + 3 个 Anthropics Gateway（strict/compatible/permissive），并验证：

1. strict：`POST /v1/messages` 携带扩展字段时返回 `422 + capability_error`
2. compatible：`POST /v1/messages/count_tokens` 在上游不支持时返回 `estimated=true` 且 `notice=degraded_to_estimate`
3. permissive：`POST /v1/messages` 的扩展字段可透传到上游（mock 返回 `passthrough-ok`）

## 与 smoke 集成

`scripts/e2e/smoke.sh` 已集成本脚本，标准烟测会自动执行兼容模式校验。
