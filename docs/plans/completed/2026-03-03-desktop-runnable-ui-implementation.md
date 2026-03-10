# FluxDeck 可运行桌面前端 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将 `apps/desktop` 从占位逻辑改造成可运行的管理台界面，支持 Provider/Gateway/Logs 展示与创建操作。

**Architecture:** 保持单页结构，新增轻量 UI Shell 与分区组件。所有数据访问统一经由 `src/api/admin.ts` 调用 `fluxd` Admin API，创建动作后执行最小刷新。样式采用本地 tokens + 组件化样式文件，不引入重型 UI 框架。

**Tech Stack:** Bun, TypeScript, React + Vite（最小化脚手架）, Fluxd Admin API。

---

### Task 1: 搭建可运行前端脚手架（Vite + React 入口）

**Files:**
- Create: `apps/desktop/index.html`
- Create: `apps/desktop/vite.config.ts`
- Create: `apps/desktop/tsconfig.json`
- Create: `apps/desktop/src/entry.tsx`
- Modify: `apps/desktop/package.json`
- Test: `apps/desktop/src/App.test.tsx`

**Step 1: Write the failing test**

```tsx
it('mounts app root into #root', () => {
  // 断言入口挂载行为存在
})
```

**Step 2: Run test to verify it fails**

Run: `cd apps/desktop && bun run test`
Expected: FAIL（缺少真实挂载入口）

**Step 3: Write minimal implementation**

- 引入 `react`, `react-dom`, `vite`, `@vitejs/plugin-react`, `typescript`。
- 建立 `index.html` + `entry.tsx`，挂载到 `#root`。
- `package.json` 增加：
  - `dev`: `vite`
  - `build`: `vite build`
  - `preview`: `vite preview`

**Step 4: Run test to verify it passes**

Run: `cd apps/desktop && bun run test`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/desktop/package.json apps/desktop/index.html apps/desktop/vite.config.ts apps/desktop/tsconfig.json apps/desktop/src/entry.tsx apps/desktop/src/App.test.tsx
git commit -m "feat(desktop): bootstrap runnable react shell"
```

### Task 2: 实现 App Shell 与页面布局

**Files:**
- Create: `apps/desktop/src/styles/tokens.css`
- Create: `apps/desktop/src/styles/app.css`
- Create: `apps/desktop/src/ui/layout/AppShell.tsx`
- Modify: `apps/desktop/src/App.tsx`
- Test: `apps/desktop/src/App.test.tsx`

**Step 1: Write the failing test**

```tsx
it('renders app shell with header sidebar and content sections', () => {
  // 断言 Header/Sidebar/Providers/Gateways/Logs 区块
})
```

**Step 2: Run test to verify it fails**

Run: `cd apps/desktop && bun run test`
Expected: FAIL

**Step 3: Write minimal implementation**

- 新建 `AppShell` 负责布局框架。
- 引入 `tokens.css` 与 `app.css`。
- App 渲染三大区块容器。

**Step 4: Run test to verify it passes**

Run: `cd apps/desktop && bun run test`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/desktop/src/styles/tokens.css apps/desktop/src/styles/app.css apps/desktop/src/ui/layout/AppShell.tsx apps/desktop/src/App.tsx apps/desktop/src/App.test.tsx
git commit -m "feat(desktop): add app shell layout"
```

### Task 3: Provider 区块可视化（列表 + 创建表单）

**Files:**
- Create: `apps/desktop/src/ui/providers/ProviderSection.tsx`
- Modify: `apps/desktop/src/components/ProviderForm.tsx`
- Modify: `apps/desktop/src/App.tsx`
- Test: `apps/desktop/src/App.test.tsx`

**Step 1: Write the failing test**

```tsx
it('creates provider from ui and refreshes provider list', async () => {
  // 断言 createProvider 调用与刷新
})
```

**Step 2: Run test to verify it fails**

Run: `cd apps/desktop && bun run test`
Expected: FAIL

**Step 3: Write minimal implementation**

- `ProviderSection` 展示列表、空态、错误态。
- 调用 `ProviderForm` 提交后执行 `listProviders` 刷新。

**Step 4: Run test to verify it passes**

Run: `cd apps/desktop && bun run test`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/desktop/src/ui/providers/ProviderSection.tsx apps/desktop/src/components/ProviderForm.tsx apps/desktop/src/App.tsx apps/desktop/src/App.test.tsx
git commit -m "feat(desktop): add provider section with create flow"
```

### Task 4: Gateway 区块可视化（列表 + 创建 + 运行状态）

**Files:**
- Create: `apps/desktop/src/ui/gateways/GatewaySection.tsx`
- Modify: `apps/desktop/src/components/GatewayForm.tsx`
- Modify: `apps/desktop/src/App.tsx`
- Test: `apps/desktop/src/App.test.tsx`

**Step 1: Write the failing test**

```tsx
it('shows gateway runtime status and last error in ui', async () => {
  // 断言 runtime_status / last_error 文案
})
```

**Step 2: Run test to verify it fails**

Run: `cd apps/desktop && bun run test`
Expected: FAIL

**Step 3: Write minimal implementation**

- `GatewaySection` 渲染 gateway 列表与状态标签。
- `GatewayForm` 创建后触发刷新。
- 状态显示规则：running/stopped/error。

**Step 4: Run test to verify it passes**

Run: `cd apps/desktop && bun run test`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/desktop/src/ui/gateways/GatewaySection.tsx apps/desktop/src/components/GatewayForm.tsx apps/desktop/src/App.tsx apps/desktop/src/App.test.tsx
git commit -m "feat(desktop): add gateway section with runtime status"
```

### Task 5: Logs 区块与统一刷新

**Files:**
- Create: `apps/desktop/src/ui/logs/LogSection.tsx`
- Modify: `apps/desktop/src/App.tsx`
- Modify: `apps/desktop/src/api/admin.ts`
- Test: `apps/desktop/src/App.test.tsx`

**Step 1: Write the failing test**

```tsx
it('loads providers gateways logs in one refresh action', async () => {
  // 断言三组 list API 并发调用
})
```

**Step 2: Run test to verify it fails**

Run: `cd apps/desktop && bun run test`
Expected: FAIL

**Step 3: Write minimal implementation**

- 新增 `LogSection`。
- App 提供统一 `refreshAll()`。
- 创建动作后统一调用 `refreshAll()`。

**Step 4: Run test to verify it passes**

Run: `cd apps/desktop && bun run test`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/desktop/src/ui/logs/LogSection.tsx apps/desktop/src/App.tsx apps/desktop/src/api/admin.ts apps/desktop/src/App.test.tsx
git commit -m "feat(desktop): add logs section and unified refresh flow"
```

### Task 6: 文档收口与验收

**Files:**
- Modify: `README.md`
- Modify: `docs/USAGE.md`
- Modify: `docs/testing/frontend-parallel-checklist.md`
- Modify: `docs/progress/2026-03-02-dev-log.md`

**Step 1: Write the failing test**

- 以验收命令作为失败基线。

**Step 2: Run test to verify it fails**

Run: `cargo test -q && (cd apps/desktop && bun run test) && ./scripts/e2e/smoke.sh`
Expected: 任一失败则不通过。

**Step 3: Write minimal implementation**

- 补齐“可运行界面启动步骤 + 验收步骤 + 限制说明”。

**Step 4: Run test to verify it passes**

Run: `cargo test -q && (cd apps/desktop && bun run test) && ./scripts/e2e/smoke.sh`
Expected: PASS

**Step 5: Commit**

```bash
git add README.md docs/USAGE.md docs/testing/frontend-parallel-checklist.md docs/progress/2026-03-02-dev-log.md
git commit -m "docs: finalize runnable desktop ui verification guide"
```

## 执行约束

- 严格 TDD：先红后绿。
- 每个 Task 完成后更新 `docs/progress/2026-03-02-dev-log.md`。
- 每个 Task 完成后检查并汇报 `git status`。
- JS/TS 一律使用 `bun`。
- 不复制后端业务逻辑到前端，统一走 `fluxd` Admin API。

## 总验收命令

```bash
cargo test -q
cd apps/desktop && bun run test
cd ../..
./scripts/e2e/smoke.sh
```

