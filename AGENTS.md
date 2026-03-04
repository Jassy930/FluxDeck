# Repository Guidelines

## 项目结构与模块组织
- `crates/fluxd`：后端服务（Admin API、OpenAI 转发、SQLite 迁移）。
- `crates/fluxctl`：CLI 客户端（Provider/Gateway/Logs 管理）。
- `apps/desktop`：React + Vite 桌面前端（`src/api`、`src/ui`、`src/components`、`src/styles`）。
- `scripts/e2e`：端到端脚本与一致性校验（含 `smoke.sh`、`mock_openai.py`）。
- `docs`：使用说明、契约文档、测试清单与计划文档。

## 构建、测试与开发命令
- 根目录全量验证：
  - `cargo test -q`
  - `cd apps/desktop && bun run test`
  - `./scripts/e2e/smoke.sh`（通过标志：输出 `smoke ok`）
- 启动后端：
  - `FLUXDECK_DB_PATH="$HOME/.fluxdeck/fluxdeck.db" FLUXDECK_ADMIN_ADDR="127.0.0.1:7777" cargo run -p fluxd`
- 启动前端开发：
  - `cd apps/desktop && bun install && bun run dev`
- Python 脚本统一使用 `uv run`（见 `scripts/e2e/smoke.sh`）。

## 代码风格与命名约定
- Rust：4 空格缩进，遵循 Rust 2021；函数/模块使用 `snake_case`，类型使用 `UpperCamelCase`。
- TypeScript/React：开启 `strict`；组件文件与组件名使用 `UpperCamelCase`，普通变量/函数使用 `camelCase`。
- 测试文件命名：`*.test.ts` / `*.test.tsx`（前端），`*_test.rs`（Rust 集成测试）。
- 涉及 Admin API 字段时保持契约一致（如 `snake_case` JSON 字段，参考 `docs/contracts/admin-api-v1.md`）。
- 新增文件命名建议：
  - 后端模块：`provider_service.rs`、`gateway_manager.rs`
  - 前端模块：`ProviderSection.tsx`、`admin.test.ts`
  - 文档：`docs/plans/YYYY-MM-DD-topic.md`

## 测试规范
- Rust 集成测试位于 `crates/*/tests`，前端测试位于 `apps/desktop/src`。
- 改动 API、网关状态或列表聚合逻辑时，必须补充/更新对应测试。
- 提交前至少运行一次“三段验收命令”（见上文），避免只跑局部测试。

## 提交与 Pull Request 规范
- 提交信息遵循历史风格：`feat(scope): ...`、`fix(scope): ...`、`docs: ...`、`chore: ...`。
- 单次提交聚焦单一主题；文档变更与代码变更应同批提交。
- PR 必须包含：
  - 变更摘要与动机
  - 验证命令与结果
  - 涉及 UI 的截图/GIF
  - 若改动契约，附 `docs/contracts/admin-api-v1.md` 的更新说明

## 架构与数据流概览
- 典型链路：`desktop ui -> /admin API (fluxd) -> sqlite`。
- 转发链路：`client -> gateway(openai compatible) -> upstream provider`。
- 变更建议：
  - 改动后端返回字段时，先更新契约文档，再更新 `fluxd` 测试与 `apps/desktop/src/api/admin.ts`。
  - 改动前端表单字段时，同步检查 `components/*Form.tsx` 与 `App.test.tsx` 的断言。

## 协作与交付流程
- 开始开发前：阅读 `README.md`、`docs/USAGE.md` 与相关 `docs/plans/*`。
- 开发中：小步提交，确保 `git status --short` 仅包含当前任务文件。
- 交付前建议顺序：
  - `cargo test -q`
  - `cd apps/desktop && bun run test`
  - `./scripts/e2e/smoke.sh`
- 若出现 `E0463 can't find crate`，先执行 `cargo clean` 后重试全量验证。

## 配置与安全
- 不要提交真实上游 `api_key` 或本地数据库文件。
- 使用环境变量管理运行参数（如 `FLUXDECK_DB_PATH`、`FLUXDECK_ADMIN_ADDR`）。
