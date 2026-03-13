# FluxDeck 架构入口

FluxDeck 是一个本地优先的 LLM Gateway 工作台。当前主线交付物是 `fluxd`、`fluxctl` 与 `apps/desktop-macos-native`；`apps/desktop` 仅作为遗留兼容消费者保留。

## 当前目标

- 为本机工具提供稳定的 OpenAI / Anthropic 兼容 Gateway 入口
- 通过 Admin API 管理 Provider、Gateway、日志与统计
- 以原生 macOS 工作台作为主要操作与观测界面

## 系统分层

- `crates/fluxd`
  - 控制面：`/admin` API、配置持久化、统计查询
  - 数据面：Gateway runtime、协议解码/编码、请求转发
- `crates/fluxctl`
  - 面向操作者的 CLI 管理入口
- `apps/desktop-macos-native`
  - 只消费 Admin API，不复制后端业务逻辑
- `apps/desktop`
  - 遗留 Web 消费者，仅在 `legacy-check` 下按需验证

仓库默认遵守单向依赖约束：

`Types -> Config -> Repo -> Service -> Runtime -> UI`

## 关键数据流

- 管理链路：`desktop / fluxctl -> /admin API -> sqlite`
- 转发链路：`client -> gateway -> upstream provider`
- 协议转换：`crates/fluxd/src/protocol/ir.rs` 作为统一中间表示

## 权威入口

- 项目目标与当前状态：`README.md`
- 仓库协作规则：`AGENTS.md`
- 文档目录与入口：`docs/README.md`
- Admin API 契约：`docs/contracts/admin-api-v1.md`
- 质量门禁：`docs/testing/quality-gates.md`
- 本地运行：`docs/ops/local-runbook.md`

## 当前已知结构性风险

以下问题已被记录为后续治理入口，而不是隐含在聊天或习惯中：

- 架构评审结论：`docs/progress/2026-03-12-repository-architecture-review.md`
- 架构问题清单：`docs/plans/active/2026-03-12-architecture-issue-backlog.md`

当前优先关注：

- `fluxd` 控制面与数据面耦合仍偏高
- 原生端 `ContentView` 与 `AdminApiClient.swift` 仍是高复杂度集中点
- 文档与计划目录仍存在历史阶段遗留的分类漂移

## 不在本文展开的内容

- 详细 API 字段定义：看 `docs/contracts/`
- 功能级设计与实施细节：看 `docs/plans/`
- 历史执行证据：看 `docs/progress/`
