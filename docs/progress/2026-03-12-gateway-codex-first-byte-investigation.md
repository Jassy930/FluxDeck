# 2026-03-12 Gateway Codex First Byte 缺失调查

## 现象

- `gateway_codex` 的日志详情中 `First Byte` 显示为 `-`
- 该字段并非 UI 被隐藏，而是后端返回值为 `null`

## 调查结论

- 原生前端在 `first_byte_ms == null` 时会显示 `-`
- 显式 OpenAI / Anthropic 协议链路都会设置 `observation.first_byte_ms`
- `gateway_codex` 当前走 `openai-response -> passthrough` 运行时链路
- passthrough 的统一日志函数 `append_passthrough_log()` 没有给 `observation.first_byte_ms` 赋值
- 因此所有 passthrough 请求都会缺失 `first_byte_ms`，`gateway_codex` 只是最先暴露出来的一个实例

## 修复结果

- 已在共享 passthrough 日志链路补齐 `first_byte_ms`
- 流式请求会记录拿到上游 `Response` 时的耗时
- 非流式请求会按现有 JSON 语义记录最终 `latency_ms` 作为 `first_byte_ms`
- 前端日志工作台无需改动，修复后会自动显示 `First Byte`

## 本地证据

- UI 展示逻辑：
  - `apps/desktop-macos-native/FluxDeckNative/Features/LogsWorkbenchView.swift`
- 显式协议链路会写 `first_byte_ms`：
  - `crates/fluxd/src/http/openai_routes.rs`
  - `crates/fluxd/src/forwarding/openai_inbound.rs`
  - `crates/fluxd/src/forwarding/anthropic_inbound.rs`
- passthrough 链路遗漏该字段：
  - `crates/fluxd/src/http/passthrough.rs`
- `openai-response` 使用 passthrough Router：
  - `crates/fluxd/src/runtime/gateway_manager.rs`

## 验证

- `cargo test -q -p fluxd --test openai_passthrough_fallback_test first_byte`：PASS
- `cargo test -q -p fluxd --test openai_passthrough_fallback_test`：PASS

## 历史数据补救评估

- 结论：只能部分补救，不能精确全补
- 原因：
  - `request_logs` 当前只持久化了 `latency_ms` 与最终日志维度
  - 仓库内没有额外保存“首个响应字节到达时间点”或原始流事件时间戳
  - `RequestLogService` 现有回写能力只覆盖 usage，不包含 `first_byte_ms`
- 本地数据库统计（`~/.fluxdeck/fluxdeck.db`）：
  - `gateway_codex` 非流式：`451` 条缺失 `first_byte_ms`
  - `gateway_codex` 流式：`527` 条缺失 `first_byte_ms`
- 可补部分：
  - 非流式历史记录可按当前语义用 `latency_ms` 回填 `first_byte_ms`
- 不可精确补部分：
  - 流式历史记录缺少首包时间证据，无法从现有字段精确反推出真实 `first_byte_ms`

## 历史数据补数执行结果

- 已备份数据库：
  - `~/.fluxdeck/fluxdeck.db.bak.first-byte-2026-03-12`
- 已执行一次性回填规则：
  - `first_byte_ms IS NULL AND latency_ms IS NOT NULL -> first_byte_ms = latency_ms`
- 实际更新行数：
  - `1159`
- 本次按全库同类缺口统一回填，不只限于 `gateway_codex`
- 回填后复核：
  - 全库 `first_byte_ms IS NULL AND latency_ms IS NOT NULL` 剩余 `0` 条
  - `gateway_codex` 非流式：`451` 条记录，缺失 `0`
  - `gateway_codex` 流式：`538` 条记录，缺失 `0`
- 说明：
  - 非流式属于等价回填
  - 流式属于用户确认接受的近似回填
