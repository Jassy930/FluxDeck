# FluxDeck Documentation

本目录是 FluxDeck 的系统记录。读取顺序建议从仓库根入口开始，再进入 `docs/` 深挖细节，而不是把某一份历史文档误当成唯一真相。

## 推荐入口顺序

1. `README.md`：产品目标、当前主线、快速开始
2. `ARCHITECTURE.md`：稳定架构边界、关键数据流、权威入口索引
3. `AGENTS.md`：协作约束、文档同步规则、当前优先级
4. `docs/`：契约、运维、计划、进度、测试等细节系统记录

## 目录语义

```text
docs/
├── product/              # 当前产品目标、成功标准与非目标
├── contracts/            # 稳定契约，面向 API 消费者
├── ops/                  # 运行、排障、操作手册
├── plans/                # 设计与实施计划
│   ├── README.md         # 计划命名、状态与归档规则
│   ├── active/           # 跨阶段、仍在追踪中的调查/治理项
│   ├── completed/        # 已完成计划归档
│   └── (root)            # 默认仅保留索引类文档，不存放普通计划
├── progress/             # 已发生工作的证据记录
├── testing/              # 质量门禁、专项验证、历史验收说明
├── references/           # 外部资料的纯文本归档
├── generated/            # 机械生成产物，禁止手改
└── USAGE.md              # 面向使用者的操作说明
```

## 当前已知目录债务

- `docs/testing/` 同时包含权威门禁与历史阶段性验收文档，阅读时必须优先看 `quality-gates.md`
- 仓库当前没有已版本化的 CI 平台配置；门禁语义以文档和稳定命令入口为准

## 文档更新规则

1. API 变更：更新 `contracts/`
2. 产品目标或主线变化：更新 `product/current-state.md`
3. 架构边界变化：更新仓库根 `ARCHITECTURE.md`
4. 复杂任务启动前：先补 `plans/`
5. 工作完成后：更新 `progress/`，并按需要归档计划
6. 新增质量要求：优先落为 `testing/` 中可执行的门禁、脚本或检查清单
7. 外部上下文：转换为 `references/*.txt`

## 核心文档入口

| 文档 | 用途 |
|------|------|
| `../ARCHITECTURE.md` | 当前稳定架构入口与阅读路径 |
| `product/current-state.md` | 当前产品目标、成功标准、非目标与主要风险 |
| `contracts/admin-api-v1.md` | Admin API 契约，CLI / 原生端 / 遗留 Web 消费者共同依赖 |
| `ops/local-runbook.md` | 本地运行、手动操作与常见排障 |
| `testing/quality-gates.md` | 当前唯一权威质量门禁定义 |
| `testing/legacy-web-checks.md` | 遗留 Web 消费者专项检查入口 |
| `plans/README.md` | 计划文档生命周期、命名与归档规则 |
| `plans/active/2026-03-12-architecture-issue-backlog.md` | 当前已知架构/治理问题清单 |
| `progress/2026-03-12-repository-architecture-review.md` | 最近一次仓库级架构评审结论 |

## 守护性检查

- `./scripts/check_docs_plan_layout.sh`：检查 `docs/plans` 根目录残留计划与 `active/` 完成态漂移
