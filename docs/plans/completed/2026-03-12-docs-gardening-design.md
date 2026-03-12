# FluxDeck 文档整理设计

## 目标

将当前仓库中的文档布局整理到更符合 `AGENTS.md` 与 `docs/README.md` 描述的状态，重点清理 `docs/plans/` 目录，让计划文档的“进行中 / 已完成”状态更直观。

## 当前问题

`docs/` 的一级分类本身是清晰的：

- `contracts/`
- `ops/`
- `plans/`
- `progress/`
- `testing/`

但 `docs/plans/` 当前存在两个明显问题：

1. 多份已经完成并合入主线的计划文档仍然停留在 `docs/plans/` 根目录
2. `docs/plans/active/` 目录为空，但仓库里实际上存在仍在进行中的调查/设计文档

这会带来几个问题：

- 计划状态不透明
- `docs/README.md` 声明的结构与实际不一致
- 新进入仓库的人难以判断哪些任务已经结束，哪些仍在推进

## 整理原则

1. 已完成并已合入主线的计划文档应归档到 `docs/plans/completed/`
2. 仍在进行中的计划、调查和设计文档应放入 `docs/plans/active/`
3. 不改写文档主体内容，优先做结构归档
4. 若某份文档明显尚未完成，但已有对应 `progress/` 记录，也应优先归入 `active/`
5. `docs/README.md` 若因归档后仍有表述偏差，再做最小修正

## 归档判断

### 应归入 `completed/`

这类文档的共同特征：

- 对应功能已经提交并推送
- 有完整进度记录
- 不再作为当前待执行计划

本轮可明确归入 `completed/` 的文档包括：

- `2026-03-11-anthropic-base-url-normalization.md`
- `2026-03-11-gateway-auto-restart-on-update-design.md`
- `2026-03-11-gateway-auto-restart-on-update.md`
- `2026-03-11-gateway-form-redesign-design.md`
- `2026-03-11-gateway-form-redesign.md`
- `2026-03-12-readme-refresh-design.md`
- `2026-03-12-readme-refresh.md`

### 应归入 `active/`

这类文档的共同特征：

- 仍是调查、分析或尚未收敛为已完成结果
- 没有对应“已完成实现并归档”的结论

本轮可明确归入 `active/` 的文档包括：

- `2026-03-11-glmglm-token-monitoring-investigation.md`
- `2026-03-12-packaging-distribution-investigation.md`

## 非目标

- 不重写已有 `progress/` 文档内容
- 不合并历史 dev-log
- 不重构 `docs/testing/` 或 `docs/progress/` 命名体系
- 不修改根目录 `AGENTS.md`
