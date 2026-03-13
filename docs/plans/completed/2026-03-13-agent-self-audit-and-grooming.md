# 代理自检与整备循环实施计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 基于仓库内系统记录完成一次项目级代理自检，输出现状判断与治理建议，并直接实施低风险高收益的文档整备。

**Architecture:** 先以仓库内版本化内容建立单一事实基线，再对齐产品目标、架构边界、质量门禁、计划体系与技术债入口，最后只落地不改变实现语义的系统记录修复，例如入口文档补齐、历史文档标记、交叉引用修正与治理记录更新。

**Tech Stack:** Markdown、Git、Rust/SwiftUI 仓库结构审查、Shell

---

### Task 1: 建立系统记录基线

**Files:**
- Read: `AGENTS.md`
- Read: `README.md`
- Read: `docs/README.md`
- Read: `docs/contracts/admin-api-v1.md`
- Read: `docs/ops/local-runbook.md`
- Read: `docs/testing/quality-gates.md`
- Read: `docs/plans/completed/2026-03-12-repository-architecture-review.md`
- Read: `docs/plans/active/2026-03-12-architecture-issue-backlog.md`

### Task 2: 识别漂移与风险

**Files:**
- Read: `docs/USAGE.md`
- Read: `docs/testing/frontend-parallel-checklist.md`
- Read: `apps/desktop-macos-native/README.md`
- Read: `apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift`
- Read: `apps/desktop-macos-native/FluxDeckNative/Networking/AdminApiClient.swift`
- Read: `crates/fluxd/src/http/admin_routes.rs`
- Read: `crates/fluxd/src/runtime/gateway_manager.rs`
- Read: `crates/fluxctl/src/client.rs`

### Task 3: 实施低风险治理

**Files:**
- Create: `ARCHITECTURE.md`
- Create: `docs/product/current-state.md`
- Create: `docs/plans/README.md`
- Modify: `docs/README.md`
- Modify: `docs/USAGE.md`
- Modify: `docs/contracts/admin-api-v1.md`
- Modify: `docs/testing/frontend-parallel-checklist.md`
- Modify: `docs/plans/active/2026-03-12-architecture-issue-backlog.md`
- Create: `docs/progress/2026-03-13-agent-self-audit-and-grooming.md`

### Task 4: 整理与报告

**Files:**
- Read: `git status --short`
- Read: `git diff --stat`

**Acceptance:**
- 核心目标、边界、门禁、计划与技术债入口都能在仓库内快速定位
- `ARCHITECTURE.md` 成为稳定架构入口，不与 `README.md`/`AGENTS.md` 重复造百科
- `docs/product/current-state.md` 成为当前产品判断入口，不再依赖历史计划拼接
- `docs/plans/README.md` 明确计划目录生命周期规则
- `docs/USAGE.md` 与当前“原生端主线、Web 遗留”的产品现实一致
- 历史性并行前端验收文档被明确标记，不再伪装成当前标准
