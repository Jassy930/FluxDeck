# FluxDeck

FluxDeck 是一个本地运行的 LLM API 转发与管理工具（macOS 优先，MVP）。

## 当前能力（MVP 进行中）

- `fluxd`：本地服务，提供 Admin API 与 OpenAI 入站转发
- `fluxctl`：CLI 管理 Provider/Gateway/Logs
- Desktop（可运行 UI）：Provider/Gateway/Logs 管理面板，支持创建与统一刷新
- Desktop macOS Native（并行验证）：SwiftUI 原生壳，读取 Provider/Gateway 列表
- 持久化：SQLite（`~/.fluxdeck/fluxdeck.db` 或 `FLUXDECK_DB_PATH`）

## 快速验证

```bash
cargo test -q
cd apps/desktop && bun run test
./scripts/e2e/smoke.sh
```

## 本地运行

```bash
FLUXDECK_DB_PATH="$HOME/.fluxdeck/fluxdeck.db" \
FLUXDECK_ADMIN_ADDR="127.0.0.1:7777" \
cargo run -p fluxd
```

另开终端启动桌面前端（开发模式）：

```bash
cd apps/desktop
bun install
bun run dev
```

默认访问：`http://127.0.0.1:5173`

## 常见恢复

如果在工具链切换后出现 `cargo test` 里 `E0463 can't find crate`：

```bash
cargo clean
```

然后重新执行验收命令。

更多操作见：

- `docs/USAGE.md`
- `docs/ops/local-runbook.md`
- `docs/testing/mvp-e2e.md`
- `docs/testing/frontend-parallel-checklist.md`
