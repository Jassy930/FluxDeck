# FluxDeck Frontend Parallel Track Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在不阻塞 MVP 首发的前提下，完成 Tauri 主线可发布 UI 与 SwiftUI 原生壳并行验证。

**Architecture:** 采用“单后端契约、双前端并行”的模式，所有前端均通过 `fluxd` Admin API 管理 Provider/Gateway/Logs。主线聚焦可发布能力，支线聚焦原生可行性验证，不复制业务逻辑。

**Tech Stack:** Rust (`axum/sqlx/tokio`), Tauri + TypeScript + bun, SwiftUI + URLSession, SQLite。

---

### Task 1: 固化 Admin API 契约文档

**Files:**
- Create: `docs/contracts/admin-api-v1.md`
- Modify: `docs/USAGE.md`
- Test: `crates/fluxd/tests/admin_api_test.rs`

**Step 1: Write the failing test**

```rust
#[tokio::test]
async fn admin_api_response_shape_is_stable() {
    // 断言核心字段存在：provider/gateway/logs
}
```

**Step 2: Run test to verify it fails**

Run: `cargo test -p fluxd admin_api_response_shape_is_stable -q`
Expected: FAIL（测试未实现）

**Step 3: Write minimal implementation**

- 增加契约测试
- 补齐文档字段说明

**Step 4: Run test to verify it passes**

Run: `cargo test -p fluxd admin_api_response_shape_is_stable -q`
Expected: PASS

**Step 5: Commit**

```bash
git add docs/contracts/admin-api-v1.md docs/USAGE.md crates/fluxd/tests/admin_api_test.rs
git commit -m "docs: lock admin api v1 contract"
```

### Task 2: Tauri 主线补齐可操作页面

**Files:**
- Modify: `apps/desktop/src/App.tsx`
- Create: `apps/desktop/src/components/ProviderForm.tsx`
- Create: `apps/desktop/src/components/GatewayForm.tsx`
- Modify: `apps/desktop/src/api/admin.ts`
- Test: `apps/desktop/src/App.test.tsx`

**Step 1: Write the failing test**

```tsx
it('can create provider and gateway from ui actions', async () => {
  // 断言表单动作会调用 admin api
})
```

**Step 2: Run test to verify it fails**

Run: `bun run test --cwd apps/desktop`
Expected: FAIL

**Step 3: Write minimal implementation**

- 增加 Provider/Gateway 创建表单
- 实现最小刷新逻辑

**Step 4: Run test to verify it passes**

Run: `bun run test --cwd apps/desktop`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/desktop/src
 git commit -m "feat: add actionable tauri management forms"
```

### Task 3: 主线补齐 Gateway 状态与错误提示

**Files:**
- Modify: `crates/fluxd/src/http/admin_routes.rs`
- Modify: `crates/fluxd/src/runtime/gateway_manager.rs`
- Modify: `apps/desktop/src/App.tsx`
- Test: `crates/fluxd/tests/admin_api_test.rs`

**Step 1: Write the failing test**

```rust
#[tokio::test]
async fn admin_api_returns_gateway_runtime_status() {
    // start/stop 后查询状态
}
```

**Step 2: Run test to verify it fails**

Run: `cargo test -p fluxd admin_api_returns_gateway_runtime_status -q`
Expected: FAIL

**Step 3: Write minimal implementation**

- 后端增加状态查询接口或字段
- 前端显示状态和错误

**Step 4: Run test to verify it passes**

Run: `cargo test -p fluxd admin_api_returns_gateway_runtime_status -q`
Expected: PASS

**Step 5: Commit**

```bash
git add crates/fluxd/src/http/admin_routes.rs crates/fluxd/src/runtime/gateway_manager.rs apps/desktop/src/App.tsx crates/fluxd/tests/admin_api_test.rs
git commit -m "feat: expose gateway runtime status to ui"
```

### Task 4: 新建 macOS 原生壳工程骨架

**Files:**
- Create: `apps/desktop-macos-native/README.md`
- Create: `apps/desktop-macos-native/FluxDeckNative.xcodeproj`（或最小工程文件）
- Create: `apps/desktop-macos-native/FluxDeckNative/App/FluxDeckNativeApp.swift`
- Create: `apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift`

**Step 1: Write the failing test**

- 使用构建命令作为失败验证

**Step 2: Run test to verify it fails**

Run: `xcodebuild -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`
Expected: FAIL（工程未创建）

**Step 3: Write minimal implementation**

- 创建可编译 SwiftUI App 壳

**Step 4: Run test to verify it passes**

Run: `xcodebuild -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/desktop-macos-native
git commit -m "feat: bootstrap macos native shell"
```

### Task 5: 原生壳打通 Provider/Gateway 列表读取

**Files:**
- Create: `apps/desktop-macos-native/FluxDeckNative/Networking/AdminApiClient.swift`
- Create: `apps/desktop-macos-native/FluxDeckNative/Features/ProviderListView.swift`
- Create: `apps/desktop-macos-native/FluxDeckNative/Features/GatewayListView.swift`
- Modify: `apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift`

**Step 1: Write the failing test**

- 添加最小网络层单元测试（JSON 解码）

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`
Expected: FAIL

**Step 3: Write minimal implementation**

- URLSession 调用 `/admin/providers` 与 `/admin/gateways`
- 列表渲染与错误提示

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/desktop-macos-native
git commit -m "feat: load provider and gateway list in native shell"
```

### Task 6: 并行交付验收与文档收口

**Files:**
- Modify: `README.md`
- Modify: `docs/USAGE.md`
- Create: `docs/testing/frontend-parallel-checklist.md`

**Step 1: Write the failing test**

- 以验收命令作为失败基线

**Step 2: Run test to verify it fails**

Run: `cargo test -q && bun run test --cwd apps/desktop && ./scripts/e2e/smoke.sh`
Expected: 若任一失败则不通过

**Step 3: Write minimal implementation**

- 补齐并行说明、使用与验证步骤

**Step 4: Run test to verify it passes**

Run: `cargo test -q && bun run test --cwd apps/desktop && ./scripts/e2e/smoke.sh`
Expected: PASS

**Step 5: Commit**

```bash
git add README.md docs/USAGE.md docs/testing/frontend-parallel-checklist.md
git commit -m "docs: finalize frontend parallel delivery checklist"
```

## 执行约束

- 严格 TDD：先红后绿。
- 每个 Task 完成后更新文档并检查 `git status`。
- JS/TS 统一使用 `bun`。
- Python 工具统一使用 `uv`。
- 原生壳只做 UI/网络壳，不复制 `fluxd` 业务逻辑。

## 总验收命令

```bash
cargo test -q
bun run test --cwd apps/desktop
./scripts/e2e/smoke.sh
```
