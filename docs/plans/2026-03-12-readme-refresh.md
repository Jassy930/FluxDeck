# README Refresh Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将根目录 `README.md` 更新为面向使用者的项目首页，准确反映 FluxDeck 当前的产品状态、可用能力、快速开始路径与文档入口。

**Architecture:** 不改代码与接口，只重组 README 的信息架构和语气。内容以使用者视角组织，突出当前主线能力：`fluxd`、`fluxctl`、原生桌面端、OpenAI / Anthropic 兼容链路、日志与监控，以及运行中 Gateway 更新自动重启。

**Tech Stack:** Markdown

---

### Task 1: 重写 README 内容结构

**Files:**
- Modify: `README.md`

**Step 1: 将开头改为产品简介与当前状态**

加入：

- 项目定位
- macOS / 本地优先
- 原生桌面端优先的当前方向

**Step 2: 重写“当前能力”与“适用场景”**

覆盖：

- Provider / Gateway 管理
- OpenAI / Anthropic 入站兼容
- 请求日志与流量指标
- 运行中 Gateway 更新自动重启

**Step 3: 重写“快速开始”**

保留最核心命令：

- 启动 `fluxd`
- 启动原生或 Web 桌面端
- 指向 `docs/USAGE.md` / `docs/ops/local-runbook.md`

### Task 2: 同步进度文档

**Files:**
- Create: `docs/progress/2026-03-12-readme-refresh.md`

**Step 1: 记录 README 改写意图与范围**

内容包括：

- 目标读者
- 新增章节
- 为什么要从开发态说明转向使用者首页

### Task 3: 校对并整理工作区

**Files:**
- Modify: 无

**Step 1: 人工校对 README**

检查：

- 文风是否面向使用者
- 是否与当前项目状态一致
- 是否没有把已降级为次优先级的 Web 桌面端写成主线

**Step 2: 整理 git 状态**

Run: `git status --short --branch`

Expected: 只新增 README 与本次文档变更，以及工作区原有未提交内容
