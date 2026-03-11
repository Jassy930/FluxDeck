# 2026-03-11 Provider Kind Selector

## 变更摘要

- 后端为 Provider `kind` 增加白名单校验，仅允许以下机器值：
  - `openai`
  - `openai-response`
  - `gemini`
  - `anthropic`
  - `azure-openai`
  - `new-api`
  - `ollama`
- `POST /admin/providers` 与 `PUT /admin/providers/{id}` 在非法 `kind` 时统一返回 `400` 与错误对象
- macOS 原生 Provider 表单中的 `Kind` 输入由自由文本改为固定选择器
- 原生端增加 provider kind 展示标签映射，锁定 UI 与提交值的一致性

## 代码范围

- `crates/fluxd/src/domain/provider.rs`
- `crates/fluxd/src/service/provider_service.rs`
- `crates/fluxd/src/http/admin_routes.rs`
- `crates/fluxd/tests/provider_service_test.rs`
- `crates/fluxd/tests/admin_api_test.rs`
- `apps/desktop-macos-native/FluxDeckNative/Networking/AdminApiClient.swift`
- `apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift`
- `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`
- `docs/contracts/admin-api-v1.md`
- `apps/desktop-macos-native/README.md`

## 验证

- `cargo test -q -p fluxd --test provider_service_test --test admin_api_test`：通过
- `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`：通过

## 备注

- 本次没有修改数据库 schema
- 本次没有修改 Web 前端 Provider 表单
