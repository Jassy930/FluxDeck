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
