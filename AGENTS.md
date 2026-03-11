# AGENTS.md

## 核心信念 (Core Beliefs)
1. **Repository is the only reality:** 任何不在本代码库中版本化的信息（包括人类脑子里的想法、外部链接）均不存在。如需外部上下文，请要求人类将其转换为 `docs/references/` 下的 `.txt` 文件。
2. **机械化执行 (Mechanical Enforcement):** 不要凭借直觉绕过架构边界。所有领域层级（Types → Config → Repo → Service → Runtime → UI）必须单向依赖。如果被 Linter 拦截，阅读错误信息中的 remediation 自行修复。
3. **消除猜测 (No YOLO):** 必须通过解析边界数据形状（如 Zod）或强类型 SDK 来处理数据，严禁瞎猜数据结构。

## 系统记录地图 (System of Record Map)
不要在此文件寻找答案。你的上下文分布在以下结构中，请按需（Depth-first）检索：

```
├── docs/
│   ├── contracts/            # API 契约文档（前端消费的稳定接口定义）
│   ├── ops/                  # 运维手册与本地运行指南
│   ├── plans/                # 【重要】执行计划与设计文档
│   ├── progress/             # 开发日志与进度记录
│   └── testing/              # 测试策略与验收清单
├── crates/
│   ├── fluxd/                # 后端服务（Admin API + OpenAI/Anthropic 转发）
│   └── fluxctl/              # CLI 客户端
├── apps/desktop/             # React + Vite 桌面前端
└── scripts/e2e/              # 端到端测试脚本
```

## 架构与数据流概览
- **管理链路：** `desktop ui -> /admin API (fluxd) -> sqlite`
- **转发链路：** `client -> gateway(openai/anthropic compatible) -> upstream provider`
- **协议转换：** `protocol/ir.rs` 定义统一中间表示，入站协议解码为 IR，再从 IR 编码为出站协议

## 当前开发优先级
- 当前阶段暂停 `apps/desktop/`（React + Vite 桌面前端）的新增功能开发与体验优化，除非是为原生桌面端迁移提供必要支持的阻塞性修复。
- 当前阶段全力专注于原生桌面端的设计、实现、测试与交付；涉及资源分配、任务排序、缺陷修复优先级时，原生桌面端始终高于 Web 技术栈桌面端。

## 构建、测试与开发命令

### 全量验证（提交前必跑）
```bash
cargo test -q                                    # Rust 单元/集成测试
cd apps/desktop && bun run test                  # 前端测试
./scripts/e2e/smoke.sh                           # E2E 验证（成功输出 "smoke ok"）
```

### 启动服务
```bash
# 后端服务
FLUXDECK_DB_PATH="$HOME/.fluxdeck/fluxdeck.db" \
FLUXDECK_ADMIN_ADDR="127.0.0.1:7777" \
cargo run -p fluxd

# 前端开发服务器（另开终端）
cd apps/desktop && bun install && bun run dev    # http://127.0.0.1:5173
```

### 常见问题恢复
```bash
cargo clean                                      # 解决 E0463 can't find crate
```

## 代码风格与命名约定
- **Rust：** 4 空格缩进，遵循 Rust 2021；函数/模块使用 `snake_case`，类型使用 `UpperCamelCase`
- **TypeScript/React：** 开启 `strict`；组件文件与组件名使用 `UpperCamelCase`，普通变量/函数使用 `camelCase`
- **测试文件：** `*_test.rs`（Rust），`*.test.ts/tsx`（前端）
- **API 字段：** 保持 `snake_case` JSON 字段，参考 `docs/contracts/admin-api-v1.md`

## 文档同步规范（强制）
**代码与文档必须同步更新**：任何涉及 API、数据结构、功能行为的代码变更，必须同时更新相关文档。

| 代码变更类型 | 必须更新的文档 |
|-------------|---------------|
| 后端字段变更 | `docs/contracts/admin-api-v1.md` |
| 前端类型变更 | `apps/desktop/src/api/admin.ts`（与契约对比） |
| 新增 CLI 参数 | `docs/USAGE.md` + `docs/ops/local-runbook.md` |
| 新增功能 | `README.md` + 相关 `docs/` |

**变更检查清单：**
- [ ] 后端字段变更 → 更新契约文档
- [ ] 前端类型变更 → 与契约对比确认一致性
- [ ] 新增 CLI 参数 → 更新使用说明和运行手册
- [ ] 新增功能 → 更新 README 和相关文档
- [ ] 提交前验证：确保文档与代码描述一致

## 基础工作流 (Agent Workflow)
1. **制定计划：** 任何复杂工作开始前，必须先在 `docs/plans/` 下创建或更新执行计划，记录决策。
2. **隔离执行：** 针对当前计划编写代码与测试，确保所有 cross-cutting concerns（如 Auth、Telemetry）仅通过 Providers 接口进入。
3. **闭环验证：** 运行本地构建 -> 触发测试 -> 启动本地环境 -> 验证功能。
4. **清理与同步 (Doc-Gardening)：** 如果你的代码使某些文档、契约或 Schema 过时，你必须在同一个 PR 中提交对它们的修改。

## 提交与 Pull Request 规范
- **提交信息格式：** `feat(scope): ...`、`fix(scope): ...`、`docs: ...`、`chore: ...`
- **单次提交：** 聚焦单一主题；文档变更与代码变更应同批提交
- **PR 必须包含：**
  - 变更摘要与动机
  - 验证命令与结果
  - 涉及 UI 的截图/GIF
  - 若改动契约，附契约文档的更新说明

## 配置与安全
- **不要提交：** 真实上游 `api_key` 或本地数据库文件
- **环境变量：** `FLUXDECK_DB_PATH`、`FLUXDECK_ADMIN_ADDR`、`FLUXDECK_DEBUG_ANTHROPIC_REQUEST_PAYLOAD`
