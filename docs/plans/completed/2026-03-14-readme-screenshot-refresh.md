# README Screenshot Refresh Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将新的原生端界面截图纳入仓库，并把根目录 `README.md` 刷新为符合 2026-03-14 当前产品进展的项目首页。

**Architecture:** 本轮只做文档与静态资源整理，不改产品行为。截图统一收敛到仓库内稳定路径，`README.md` 以“项目定位 -> 当前状态 -> 核心能力 -> 快速开始 -> 文档入口”的顺序重组，并与 `docs/product/current-state.md`、近期 `docs/progress/` 记录保持一致。

**Tech Stack:** Markdown、JPEG 静态资源

---

### Task 1: 固定截图资源路径

**Files:**
- Create: `docs/assets/readme/fluxdeck-native-traffic-2026-03-14.jpeg`

**Step 1: 创建 README 资源目录**

Run: `mkdir -p docs/assets/readme`
Expected: 目录存在，可用于存放 README 引用的静态图

**Step 2: 复制截图到仓库内稳定路径**

Run: `cp /Users/jassy/Downloads/SCR-20260314-tmvp.jpeg docs/assets/readme/fluxdeck-native-traffic-2026-03-14.jpeg`
Expected: README 不再依赖用户本地 Downloads 路径

### Task 2: 刷新 README 首页内容

**Files:**
- Modify: `README.md`

**Step 1: 在简介区域加入当前原生端截图**

要求：

- 使用仓库内相对路径引用图片
- 为图片添加能表达当前界面的 alt 文本
- 在图片附近说明这是当前原生桌面端 `Traffic` 工作台

**Step 2: 更新当前状态与能力描述**

覆盖：

- 当前主线是 `apps/desktop-macos-native`
- `fluxd` / `fluxctl` 继续作为稳定基础设施
- 多 Provider 有序链路、Gateway 级健康状态、请求级故障切流
- 原生端 `Traffic` token 趋势图与 `Topology` Sankey 主舞台
- Web 技术栈桌面端暂停开发

**Step 3: 校正快速开始与文档入口**

覆盖：

- 启动 `fluxd`
- 使用 `fluxctl` 创建 Provider / Gateway
- 打开原生桌面端
- 指向 `docs/USAGE.md`、`docs/ops/local-runbook.md`、`docs/contracts/admin-api-v1.md`

### Task 3: 同步记录并校验

**Files:**
- Create: `docs/progress/2026-03-14-readme-screenshot-refresh.md`

**Step 1: 记录本轮 README 刷新范围**

内容包括：

- 新增截图资源
- README 对当前项目阶段的重新表述
- 为什么要补充原生端流量/拓扑与多 Provider 能力说明

**Step 2: 校验改动与整理 git 状态**

Run: `git diff -- README.md docs/progress/2026-03-14-readme-screenshot-refresh.md docs/plans/completed/2026-03-14-readme-screenshot-refresh.md`
Expected: 仅出现本轮文档与资源接入相关改动

Run: `git status --short`
Expected: 仅包含本轮新增/修改文件，以及仓库已有未跟踪的 `.DS_Store`
