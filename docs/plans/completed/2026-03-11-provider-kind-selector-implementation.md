# Provider Kind Selector Implementation Plan

## Execution Status

- Date: 2026-03-11
- Status: completed and locally verified
- Note: plan-step `git commit` actions were intentionally not executed in this session

## Verification Results

- `cargo test -q -p fluxd --test provider_service_test --test admin_api_test`：PASS
- `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`：PASS

## Completion Notes

- 已完成后端 provider kind 白名单校验
- 已统一 `POST /admin/providers` 和 `PUT /admin/providers/{id}` 的非法输入错误语义为 `400 + {"error": ...}`
- 已将 macOS 原生 Provider 表单中的 `kind` 改为固定 `Picker`
- 已补充 Swift 测试锁定 provider kind 的机器值与展示标签
- 已更新 Admin API 契约与原生 README

## Deferred Behavior

- Web 前端 Provider 表单仍保持现状，本次仅覆盖 macOS 原生前端
- 不自动清洗数据库中的历史非法 `kind` 值；若用户编辑此类 Provider，需要重新选择合法值

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将 Provider `kind` 从原生前端自由文本输入改为固定选择，并在后端强制校验只接受 7 个允许值。

**Architecture:** 保持数据库与 Admin API 字段结构不变，使用字符串机器值承载 `kind`。在 Rust 服务层集中校验，在 Swift 原生表单层收敛为固定选项，并用测试锁定允许值与错误语义。

**Tech Stack:** Rust, Axum, anyhow, SwiftUI, XCTest, 现有 FluxDeck Admin API / macOS Native 测试栈

---

### Task 1: 记录设计与约束

**Files:**
- Create: `docs/plans/active/2026-03-11-provider-kind-selector-design.md`
- Modify: `docs/contracts/admin-api-v1.md`

**Step 1: 写入设计稿**

在设计稿中记录：

- 允许的 7 个 `kind` 机器值
- 原生前端显示标签
- 前端选择器与后端白名单校验方案
- `POST /admin/providers` 错误响应统一为 JSON 错误对象

**Step 2: 更新契约草案**

在契约文档 Provider 章节补充：

- `kind: string` 的允许值列表
- `POST /admin/providers` 的错误返回为 `400` + `{ "error": string }`
- `PUT /admin/providers/{id}` 非法 `kind` 返回 `400`

**Step 3: 自检**

确认文档与代码目标一致，不引入额外范围。

### Task 2: 先写后端失败测试

**Files:**
- Modify: `crates/fluxd/tests/provider_service_test.rs`
- Modify: `crates/fluxd/tests/admin_api_test.rs`

**Step 1: 写 `provider_service_test` 红测试**

新增两个测试：

- `create_provider_rejects_unknown_kind`
- `update_provider_rejects_unknown_kind`

断言：

- 返回 `Err`
- 错误消息包含非法值和允许值提示

**Step 2: 写 `admin_api_test` 红测试**

新增两个接口测试：

- `POST /admin/providers` 发送非法 `kind`
- `PUT /admin/providers/{id}` 发送非法 `kind`

断言：

- 状态码 `400`
- body 含 `error`

**Step 3: 运行红测试**

Run: `cargo test -q -p fluxd --test provider_service_test --test admin_api_test`

Expected:

- 新增的 provider kind 用例失败
- 失败原因是校验尚未实现或返回结构不匹配

### Task 3: 实现后端 provider kind 校验

**Files:**
- Modify: `crates/fluxd/src/domain/provider.rs`
- Modify: `crates/fluxd/src/service/provider_service.rs`
- Modify: `crates/fluxd/src/http/admin_routes.rs`

**Step 1: 在领域层定义允许值**

增加：

- `SUPPORTED_PROVIDER_KINDS`
- `is_supported_provider_kind`
- `validate_provider_kind`

**Step 2: 在服务层接入校验**

在 `create_provider` 和 `update_provider` 中调用校验函数，非法值直接返回错误。

**Step 3: 统一 create/update 错误响应**

修改 `create_provider` 路由错误返回为：

```json
{ "error": "..." }
```

保持 `update_provider` 的 `400` 错误对象模式一致。

**Step 4: 运行绿测试**

Run: `cargo test -q -p fluxd --test provider_service_test --test admin_api_test`

Expected:

- 新增 provider kind 用例通过
- 相关已有 provider / admin API 用例继续通过

### Task 4: 先写原生前端失败测试

**Files:**
- Modify: `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`

**Step 1: 写 kind 选项红测试**

新增测试验证：

- 选项值集合与顺序稳定
- `openai-response` 对应 `OpenAI-Response`
- `azure-openai` 对应 `Azure OpenAI`

**Step 2: 运行红测试**

Run: `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`

Expected:

- 新增测试因缺少 provider kind 元数据而失败

### Task 5: 实现原生前端选择器

**Files:**
- Modify: `apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative/Networking/AdminApiClient.swift`

**Step 1: 定义 Provider kind 选项元数据**

在原生端增加：

- `ProviderKindOption`
- 固定选项数组
- label/helper

**Step 2: 把文本输入改为 Picker**

在 `ProviderFormSheet` 中：

- `Kind` 改为 `Picker`
- 创建默认 `openai`
- 编辑按现有值回填
- summary card 可继续显示当前值或友好标签

**Step 3: 保持提交结构不变**

`CreateProviderInput` / `UpdateProviderInput` 继续发送机器值字符串。

**Step 4: 运行绿测试**

Run: `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`

Expected:

- 新增 kind 选择器测试通过
- 现有原生测试继续通过

### Task 6: 同步文档与进度记录

**Files:**
- Modify: `docs/contracts/admin-api-v1.md`
- Modify: `apps/desktop-macos-native/README.md`
- Create or Modify: `docs/progress/2026-03-11-provider-kind-selector.md`

**Step 1: 更新契约**

补充 `kind` 允许值和错误语义。

**Step 2: 更新原生说明**

说明 Provider kind 改为固定选项。

**Step 3: 记录开发日志**

写明：

- 改动范围
- 测试命令
- 验证结果

### Task 7: 验证与收尾

**Files:**
- Modify: `docs/plans/active/2026-03-11-provider-kind-selector-implementation.md`

**Step 1: 运行针对性验证**

Run:

- `cargo test -q -p fluxd --test provider_service_test --test admin_api_test`
- `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`

**Step 2: 回填验证结果**

在实现计划中记录：

- 通过/失败状态
- 若失败，记录阻塞项

**Step 3: 整理工作区**

- 检查 `git status --short`
- 确认只包含本次变更和已有用户改动
- 如本次工作完成，将计划文件移入 `docs/plans/completed/`
