# FluxDeck 当前产品状态

本文档是当前产品目标、成功标准、关键约束与主要风险的权威入口；历史阶段目标应保留在对应计划文档中，不应反向覆盖当前判断。

## 当前目标

FluxDeck 当前阶段的主线目标是交付一个本地优先、可观测、可维护的 macOS LLM Gateway 工作台：

- 以 `fluxd` 承载 Provider / Gateway 管理、运行时与转发链路
- 以 `apps/desktop-macos-native` 提供当前主线桌面体验
- 以 `fluxctl` 提供脚本化与终端运维入口
- 为 OpenAI / Anthropic 兼容客户端提供稳定本地入口

## 成功标准

当前阶段达到以下条件，才应被视为方向正确：

- 原生桌面端覆盖 Provider / Gateway / Logs / Traffic 等主流程
- `fluxd` 与 `fluxctl` 可作为稳定基础设施使用
- 主线质量门禁可快速定位并执行
- API 契约、运行手册、产品入口与架构入口之间相互印证
- 关键技术债已进入仓库内可追踪记录，而不是停留在聊天或个人记忆

## 非目标

当前阶段明确不作为主线目标的事项：

- 恢复 `apps/desktop` 的新增功能开发或体验优化
- 在边界尚未收敛前进行大规模平台化重写
- 在没有契约与验证配套前继续快速扩张协议面
- 把一次性本地操作、临时调试说明当作长期系统记录

## 关键约束

- 仓库内容是唯一系统记录
- `apps/desktop-macos-native` 是当前桌面主线，`apps/desktop` 是遗留兼容消费者
- 当前唯一权威质量门禁入口是 `docs/testing/quality-gates.md`
- 当前唯一权威 Admin API 契约入口是 `docs/contracts/admin-api-v1.md`
- 新的复杂工作必须先进入 `docs/plans/`
- 中高风险架构调整先形成方案，再推进实现

## 主要风险

### 1. 架构边界仍偏紧耦合

- `fluxd` 仍把控制面配置、运行时决策、协议转发与统计查询压在较近边界上
- 原生端应用层还没有稳定收口到 store / adapter / view-state 边界

### 2. 文档入口尚未完全收敛

- 架构与产品入口此前缺位，近期才开始补齐
- `docs/plans` 生命周期规则尚未稳定执行
- 历史阶段文档仍可能误导当前优先级判断

### 3. 可靠性与安全约束仍未充分机械化

- Admin API 错误契约尚未统一为稳定 envelope
- Provider secret boundary 仍偏宽，`api_key` 仍通过标准配置链路回传
- 部分治理规则仍停留在文档层，而未转化为脚本或检查

## 当前权威入口

- 产品与使用入口：`README.md`
- 架构入口：`ARCHITECTURE.md`
- API 契约：`docs/contracts/admin-api-v1.md`
- 质量门禁：`docs/testing/quality-gates.md`
- 本地运维：`docs/ops/local-runbook.md`
- 架构问题清单：`docs/plans/active/2026-03-12-architecture-issue-backlog.md`
