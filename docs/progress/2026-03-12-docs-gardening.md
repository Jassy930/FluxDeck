# 2026-03-12 文档整理

## 目标

检查仓库文档是否整齐且符合 `AGENTS.md` / `docs/README.md` 描述的系统记录结构，并对明显偏离的目录进行归档整理。

## 发现的问题

- `docs/contracts/`、`docs/ops/`、`docs/progress/`、`docs/testing/` 基本整齐
- 主要问题集中在 `docs/plans/`
  - 多份已经完成的计划仍停留在 `docs/plans/` 根目录
  - `docs/plans/active/` 为空，但仓库里存在仍在进行中的 investigation 文档

## 处理原则

- 已完成并已合入主线的计划文档移入 `docs/plans/completed/`
- 仍在推进的 investigation 文档移入 `docs/plans/active/`
- 不改写历史正文内容，优先做结构归档

## 本轮归档

### 移入 `docs/plans/completed/`

- `2026-03-11-anthropic-base-url-normalization.md`
- `2026-03-11-gateway-auto-restart-on-update-design.md`
- `2026-03-11-gateway-auto-restart-on-update.md`
- `2026-03-11-gateway-form-redesign-design.md`
- `2026-03-11-gateway-form-redesign.md`
- `2026-03-12-readme-refresh-design.md`
- `2026-03-12-readme-refresh.md`
- 本次文档治理的设计与实现计划

### 移入 `docs/plans/active/`

- `2026-03-11-glmglm-token-monitoring-investigation.md`
- `2026-03-12-packaging-distribution-investigation.md`

## 结果

- `docs/plans/active/` 不再为空，能够表达当前仍在推进的任务
- `docs/plans/completed/` 承接了历史已完成计划
- `docs/plans/` 根目录不再堆放历史计划文件
- 当前 `docs/` 的整体布局已经与 `AGENTS.md` 和 `docs/README.md` 更一致
