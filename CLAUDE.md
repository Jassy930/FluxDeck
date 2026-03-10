# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

FluxDeck 是一个本地运行的 LLM API 转发与管理工具（macOS 优先，MVP）。核心功能是作为 LLM 请求的代理网关，支持 OpenAI 和 Anthropic 协议的入站/出站转换。

## 常用命令

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

### 运行单个测试
```bash
cargo test -p fluxd --test admin_api_test        # 运行指定测试文件
cargo test -p fluxd test_name                    # 运行指定测试函数
cd apps/desktop && bun test src/api/admin.test.ts
```

### 常见问题恢复
```bash
cargo clean                                      # 解决 E0463 can't find crate
```

## 架构概览

### 核心组件
- `crates/fluxd`：后端服务（Admin API + OpenAI/Anthropic 转发 + SQLite 持久化）
- `crates/fluxctl`：CLI 客户端（Provider/Gateway/Logs 管理）
- `apps/desktop`：React + Vite 桌面前端

### 数据流
1. **管理链路**：`desktop ui -> /admin API (fluxd) -> sqlite`
2. **转发链路**：`client -> gateway(openai/anthropic compatible) -> upstream provider`

### fluxd 模块结构
```
fluxd/
├── domain/          # 领域模型 (provider, gateway)
├── forwarding/      # 转发核心 (executor, target_resolver, inbound handlers)
├── protocol/        # 协议适配层 (adapters/, ir.rs, registry.rs)
│   └── adapters/    # openai/, anthropic/ 解码器/编码器
├── http/            # HTTP 路由 (admin_routes, openai_routes, anthropic_routes)
├── service/         # 业务服务层
├── repo/            # 数据访问层
├── runtime/         # Gateway 进程管理 (gateway_manager)
├── storage/         # SQLite 迁移
└── upstream/        # 上游客户端 (openai_client, anthropic_client)
```

### 协议转换
`protocol/ir.rs` 定义了统一的中间表示（`ProtocolIrRequest`, `ProtocolIrResponse`），入站协议解码为 IR，再从 IR 编码为出站协议。

## 代码约定

### 命名
- Rust：`snake_case` 函数/模块，`UpperCamelCase` 类型
- TypeScript/React：`UpperCamelCase` 组件，`camelCase` 变量/函数
- 测试文件：`*_test.rs` (Rust)，`*.test.ts/tsx` (前端)

### Admin API 契约
- 契约文档：`docs/contracts/admin-api-v1.md`
- 改动返回字段时：先更新契约文档，再更新 `fluxd` 测试与 `apps/desktop/src/api/admin.ts`
- 契约稳定性由 `admin_api_test.rs::admin_api_response_shape_is_stable` 保障

### 文档同步（强制）
**代码与文档必须同步更新**：任何涉及 API、数据结构、功能行为的代码变更，必须同时更新相关文档。

变更检查清单：
- 后端字段变更 → 更新 `docs/contracts/admin-api-v1.md`
- 前端类型变更 → 与契约对比确认一致性
- 新增 CLI 参数 → 更新 `docs/USAGE.md` 和 `docs/ops/local-runbook.md`
- 新增功能 → 更新 README.md

### 提交信息格式
`feat(scope): ...`、`fix(scope): ...`、`docs: ...`、`chore: ...`

## 环境变量

| 变量 | 用途 |
|------|------|
| `FLUXDECK_DB_PATH` | SQLite 数据库路径 |
| `FLUXDECK_ADMIN_ADDR` | Admin API 监听地址 |
| `FLUXDECK_DEBUG_ANTHROPIC_REQUEST_PAYLOAD` | 强制开启 Anthropic 请求日志 |

## 重要文件路径

- Admin API 契约：`docs/contracts/admin-api-v1.md`
- 使用文档：`docs/USAGE.md`
- E2E 脚本：`scripts/e2e/smoke.sh`
- 前端 API 客户端：`apps/desktop/src/api/admin.ts`
