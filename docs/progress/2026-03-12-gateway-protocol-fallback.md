# 2026-03-12 Gateway Protocol Fallback

## 背景

- `gateway_codex` 在访问 `http://127.0.0.1:18081/responses` 时返回 `404 Not Found`
- 根因是 Provider 已支持 `openai-response`，但 Gateway 运行时没有对应完整协议能力

## 本轮完成

- Gateway `inbound_protocol` / `upstream_protocol` 协议值集合与 Provider `kind` 对齐
- `GatewayRepo` 新增协议值校验
- `openai` 入站路由新增 fallback passthrough
- 新增通用 `passthrough` router，用于其它已支持但暂无专门 handler 的协议
- OpenAI 系兼容：
  - `/responses`
  - `/v1/responses`
- passthrough 链路新增最小请求日志：
  - `inbound_protocol`
  - `upstream_protocol`
  - `status_code`
  - `latency_ms`
  - `error`
- macOS 原生 Gateway 表单已将协议 Picker 与 `ProviderKindOption` 对齐：
  - `Inbound Protocol` = 七种 Provider 类型
  - `Upstream Protocol` = `provider_default + 七种 Provider 类型`
  - Picker 选项改为从共享定义派生，避免再次分叉

## 关键文件

- `crates/fluxd/src/domain/gateway.rs`
- `crates/fluxd/src/repo/gateway_repo.rs`
- `crates/fluxd/src/http/openai_routes.rs`
- `crates/fluxd/src/http/passthrough.rs`
- `crates/fluxd/src/runtime/gateway_manager.rs`
- `apps/desktop-macos-native/FluxDeckNative/Networking/AdminApiClient.swift`
- `apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift`
- `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`

## 测试

- `cargo test -q -p fluxd --test gateway_manager_test --test openai_passthrough_fallback_test`
- `cargo test -q -p fluxd --test gateway_manager_test --test openai_forwarding_test --test admin_api_test --test openai_passthrough_fallback_test`
- `cargo test -q`
- `./scripts/e2e/smoke.sh`
- `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`

结果：

- 全部通过

## 未完成

- passthrough 当前只做最小观测，不做 usage 深度提取
- 方案 C 仍保留为后续架构讨论 issue

## 2026-03-12 补充：passthrough token 监测修复

### 现象

- 用户反馈最近日志中的 `input_tokens / output_tokens / total_tokens` 持续为空
- 监测页 `Total Tokens` 也因此聚合为 `0`

### 根因

- 3 月 12 日早些时候引入的同协议 passthrough fallback 只记录了最小请求日志
- `/responses` 等 fallback 请求虽然已经能被成功转发，但没有解析 upstream response 的 `usage`
- 对于流式 SSE，请求在流开始时就已落库，后续也没有在 `response.completed` 后回写 usage

### 本次修复

- `crates/fluxd/src/forwarding/openai_inbound.rs`
  - `extract_usage()` 兼容 OpenAI Responses API 的 `usage.input_tokens / output_tokens`
  - 继续兼容 Chat Completions 的 `prompt_tokens / completion_tokens`
- `crates/fluxd/src/http/passthrough.rs`
  - 非流式 JSON 成功响应：在返回客户端前解析 usage 并直接写入 `request_logs`
  - 流式 SSE 成功响应：保留透传，额外跟踪 `data:` 事件；当收到 `response.completed.response.usage` 后，在流结束时回写 usage
  - passthrough 日志会正确标记 `stream`
- `crates/fluxd/tests/openai_passthrough_fallback_test.rs`
  - 新增 `/responses` 非流式 usage 落库回归
  - 新增 `/responses` SSE `response.completed` usage 回写回归

### 验证

- `cargo test -q -p fluxd --test openai_passthrough_fallback_test`
- `cargo test -q -p fluxd --test openai_streaming_test`
- `cargo test -q -p fluxd --test request_log_service_test`

结果：

- 全部通过

### 当前口径

- OpenAI `/responses` passthrough 现在会把 token usage 写入 `request_logs`
- 因为 `/admin/stats/overview` 直接聚合 `request_logs.total_tokens`，所以同类请求的监测面板 token 统计会恢复
