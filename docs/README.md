# FluxDeck Documentation

本目录是 FluxDeck 项目的系统记录，所有上下文分布在此结构中。

## 目录结构

```
docs/
├── contracts/            # API 契约文档（前端消费的稳定接口定义）
│   └── admin-api-v1.md   # Admin API v1 契约
│
├── ops/                  # 运维手册与本地运行指南
│   └── local-runbook.md  # 本地开发运行手册
│
├── plans/                # 执行计划与设计文档
│   ├── active/           # 当前活跃/进行中的计划（空目录表示无活跃任务）
│   └── completed/        # 已完成的计划和设计
│
├── progress/             # 开发日志与进度记录
│   └── YYYY-MM-DD-*.md
│
├── testing/              # 测试策略与验收清单
│   ├── quality-gates.md  # 统一质量门禁定义（权威入口）
│   ├── mvp-e2e.md        # 旧门禁说明重定向
│   ├── legacy-web-checks.md
│   └── anthropic-compat-e2e.md
│
├── references/           # 外部依赖的纯文本化文档（LLM-friendly）
│                         # 将外部链接内容转换为 .txt 文件存放于此
│
├── generated/            # 机械生成的产物（如 db-schema.md）
│                         # 切勿手动修改
│
└── USAGE.md              # 使用说明（面向终端用户）
```

## 文档更新规则

1. **API 变更** → 更新 `contracts/` 中的契约文档
2. **新增功能** → 在 `plans/active/` 创建设计文档
3. **完成功能** → 将计划移动到 `plans/completed/`
4. **外部依赖** → 将内容转换为 `.txt` 存放于 `references/`

## 核心文档入口

| 文档 | 用途 |
|------|------|
| `contracts/admin-api-v1.md` | Admin API 契约，前端类型定义必须与此一致 |
| `ops/local-runbook.md` | 本地运行与开发指南 |
| `USAGE.md` | 面向终端用户的使用说明 |
| `testing/quality-gates.md` | 统一质量门禁定义，所有提交/CI/发布口径都以此为准 |
| `testing/mvp-e2e.md` | 历史文档，现仅保留为重定向入口 |
