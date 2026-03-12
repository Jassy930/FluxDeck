# Docs Gardening Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 清理 `docs/` 目录，尤其是 `docs/plans/` 的归档状态，使其更符合 `AGENTS.md` 与 `docs/README.md` 规定的系统记录结构。

**Architecture:** 不改写历史文档内容，优先通过文件归档与最小文档修正完成整理。将已完成计划移动到 `docs/plans/completed/`，将仍在推进的调查类计划移动到 `docs/plans/active/`，必要时再同步更新 `docs/README.md` 与进度记录。

**Tech Stack:** Markdown, git file moves

---

### Task 1: 盘点并分类 `docs/plans/` 根目录文件

**Files:**
- Read: `docs/plans/*.md`

**Step 1: 标记已完成文档**

根据是否已对应代码落地、进度记录存在且任务已完成，列出应移动到 `completed/` 的文档。

**Step 2: 标记进行中文档**

根据 investigation / 调研性质，列出应移动到 `active/` 的文档。

### Task 2: 移动计划文档到正确目录

**Files:**
- Move: `docs/plans/*.md`

**Step 1: 将已完成文档移动到 `docs/plans/completed/`**

使用保守的文件移动，不修改正文内容。

**Step 2: 将进行中的 investigation 文档移动到 `docs/plans/active/`**

确保 `active/` 不再是空目录。

### Task 3: 同步目录说明与进度记录

**Files:**
- Modify: `docs/README.md`（如有必要）
- Create: `docs/progress/2026-03-12-docs-gardening.md`

**Step 1: 检查 `docs/README.md` 是否仍与整理后的结构一致**

若一致，则不改。

**Step 2: 新增一条进度记录**

记录：

- 发现的问题
- 归档规则
- 本轮移动了哪些文档

### Task 4: 检查工作区与结果

**Files:**
- Modify: 无

**Step 1: 检查 `git status --short --branch`**

Expected: 只出现本次文档整理相关变更与原有未提交文件。

**Step 2: 人工确认 `docs/plans/` 根目录明显收敛**

Expected:

- 根目录只保留当前真正未归档的极少数文件或为空
- `active/` 与 `completed/` 语义清晰
