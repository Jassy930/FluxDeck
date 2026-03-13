# Docs Information Architecture Cleanup Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 清理 `docs/plans` 生命周期漂移，把当前目录结构、活跃状态与路径引用重新对齐到可维护状态。

**Architecture:** 先将根目录普通计划文档重新分流到 `active/` 或 `completed/`，再把 `active/` 中带完成态信号的计划归档，最后统一修正文档内的显式路径引用与索引说明，并用守护脚本验证结果。整个过程只调整文档位置与文本引用，不改变产品或代码语义。

**Tech Stack:** Markdown、Shell、ripgrep、git

---

### Task 1: 归位根目录普通计划文档

**Files:**
- Move to `docs/plans/completed/`:
  - `docs/plans/2026-03-12-native-logs-density-polish-design.md`
  - `docs/plans/2026-03-12-native-logs-density-polish.md`
  - `docs/plans/2026-03-12-native-logs-workbench-redesign-design.md`
  - `docs/plans/2026-03-12-native-logs-workbench-redesign.md`
  - `docs/plans/2026-03-12-native-shell-header-merge-design.md`
  - `docs/plans/2026-03-12-native-shell-header-merge.md`
  - `docs/plans/2026-03-12-native-traffic-kpi-supplement-design.md`
  - `docs/plans/2026-03-12-native-traffic-kpi-supplement.md`
- Move to `docs/plans/active/`:
  - `docs/plans/2026-03-12-native-distribution-design.md`
  - `docs/plans/2026-03-13-native-traffic-model-token-trend-design.md`
  - `docs/plans/2026-03-13-native-traffic-model-token-trend.md`

**Step 1: 移动 2026-03-12 已完成原生端计划**

执行文件移动，将已完成且已有进度记录的原生端计划移入 `completed/`。

**Step 2: 移动仍在讨论或仍在当前工作区内推进的计划**

将 `native-distribution-design` 与 `native-traffic-model-token-trend*` 放入 `active/`。

**Step 3: 更新显式路径引用**

修正 `docs/progress/` 与相关计划中仍指向旧路径的链接。

### Task 2: 归档 `active/` 中已完成的计划

**Files:**
- Move to `docs/plans/completed/`:
  - `docs/plans/active/2026-03-12-codex-model-stats-investigation.md`
  - `docs/plans/active/2026-03-12-gateway-protocol-fallback-design.md`
  - `docs/plans/active/2026-03-12-gateway-protocol-fallback-implementation.md`
  - `docs/plans/active/2026-03-12-provider-gateway-delete-design.md`
  - `docs/plans/active/2026-03-12-provider-gateway-delete.md`
  - `docs/plans/active/2026-03-12-quality-gate-realignment-design.md`
  - `docs/plans/active/2026-03-12-quality-gate-realignment.md`
  - `docs/plans/active/2026-03-12-passthrough-first-byte-fix.md`
  - `docs/plans/active/2026-03-12-passthrough-token-monitoring-fix.md`
  - `docs/plans/active/2026-03-12-request-log-first-byte-backfill.md`

**Step 1: 按完成态信号归档**

将带有 `Status: completed and locally verified`、明确实施结果或已被进度文档确认完成的计划从 `active/` 迁出。

**Step 2: 更新残留引用**

修正 `docs/progress/`、`docs/plans/active/` 中仍指向旧 `active/` 路径的链接。

### Task 3: 收敛索引与守护脚本

**Files:**
- Modify: `docs/README.md`
- Modify: `docs/plans/README.md`
- Modify: `docs/progress/2026-03-13-agent-self-audit-and-grooming.md`
- Modify: `scripts/check_docs_plan_layout.sh`

**Step 1: 更新目录说明**

让 `docs/README.md` 和 `docs/plans/README.md` 与清理后的实际结构一致，不再把根目录普通计划文档描述成默认状态。

**Step 2: 调整脚本误报规则**

收窄 `scripts/check_docs_plan_layout.sh` 的完成态匹配规则，避免把 backlog 状态注记误判为待归档计划。

**Step 3: 记录本轮清理结果**

在 `docs/progress/2026-03-13-agent-self-audit-and-grooming.md` 中补充本轮归档治理动作。

### Task 4: 验证

**Files:**
- Reference: `git status --short`

**Step 1: 检查补丁格式**

Run:

```bash
git diff --check
```

Expected: 无格式错误。

**Step 2: 运行计划目录检查**

Run:

```bash
./scripts/check_docs_plan_layout.sh
```

Expected: 通过，不再报告根目录普通计划和 `active/` 完成态漂移。

**Step 3: 检查工作区**

Run:

```bash
git status --short
```

Expected: 只包含本轮文档治理改动和既有用户实现改动。
