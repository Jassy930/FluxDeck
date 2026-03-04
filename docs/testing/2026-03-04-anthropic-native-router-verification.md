# 2026-03-04 Anthropics 原生转发测试验证报告

## 1. 验证范围

本次验证覆盖 Task7-Task10 的核心改动：

- `/v1/messages/count_tokens` 与降级策略
- 按 `inbound_protocol` 选择运行时路由
- Admin/CLI/Desktop 协议图字段贯通
- `compatibility_mode`（strict/compatible/permissive）行为
- 兼容模式 E2E 与 smoke 集成

## 2. 执行环境

- 仓库：`FluxDeck`
- 分支：`feat/anthropic-native-router`
- 日期：2026-03-04
- 平台：macOS（本地开发环境）

## 3. 验证命令与结果

### 3.1 定向测试（功能级）

```bash
cargo test -p fluxd --test anthropic_count_tokens_test -q
cargo test -p fluxd --test gateway_manager_test -q
cargo test -p fluxd --test admin_api_test -q
cargo test -p fluxctl -q
cargo test -p fluxd --test compatibility_mode_test -q
cargo test -p fluxd --test request_log_retention_test -q
cd apps/desktop && bun run test
```

结果：全部通过。

### 3.2 回归测试（包级）

```bash
cargo test -p fluxd -q
```

结果：通过。

### 3.3 三段验收（阶段收尾）

```bash
cargo test -q
cd apps/desktop && bun run test
./scripts/e2e/smoke.sh
```

结果：

- `cargo test -q`：通过
- `bun run test`：`9 pass / 0 fail`
- `smoke.sh` 输出：
  - `cli-desktop consistency ok`
  - `anthropic compat ok`
  - `smoke ok`

## 4. 行为覆盖清单

1. count_tokens
- 上游支持返回 `input_tokens` -> `estimated=false`
- 上游 `404/405/501` -> 本地估算降级

2. 网关运行时协议路由
- `openai` 入站命中 OpenAI 路由
- `anthropic` 入站命中 Anthropics 路由
- 未知协议返回启动错误

3. 协议图配置入口贯通
- Admin API 创建网关可收发 `upstream_protocol`、`protocol_config_json`
- CLI `gateway create` 可传新参数
- Desktop 类型与提交 payload 含新字段

4. compatibility_mode
- `strict`：扩展字段拒绝（`422 + capability_error`）
- `compatible`：`count_tokens` 不支持时降级并返回 `notice=degraded_to_estimate`
- `permissive`：扩展字段透传上游

## 5. 结论

当前实现在测试覆盖范围内可用，主流程、降级策略和兼容模式链路均已可重复验证通过。

## 6. 审查问题修复验证（增量）

针对正式 code review 的 3 个问题，本次新增了以下验证与修复：

1. strict 模式误伤常见字段
- 新增用例：`strict_mode_allows_known_anthropic_fields`
- 验证：携带 `max_tokens/temperature/top_p/stream/metadata` 的请求在 strict 下应返回 `200`
- 命令：`cargo test -p fluxd --test compatibility_mode_test -q`

2. 成功日志误写 `error`
- 调整语义：仅失败日志（`status_code >= 400` 或显式错误）写入维度到 `error`
- 新增用例：`stores_dimensions_in_error_for_failed_log_entry`
- 现有保留测试更新：成功日志 `error` 必须保持 `null`
- 命令：`cargo test -p fluxd --test request_log_retention_test -q`

3. `anthropic_compat.py` 未清理网关
- 脚本改为 `try/finally`，结束时逆序调用 `/admin/gateways/{id}/stop`
- 通过烟测验证执行路径与清理流程未破坏
- 命令：`./scripts/e2e/smoke.sh`
