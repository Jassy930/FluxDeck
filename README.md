# FluxDeck

FluxDeck 是一个本地运行的 LLM API 转发与管理工具（macOS 优先，MVP）。

## 当前能力（MVP 进行中）

- `fluxd`：本地服务，提供 Admin API 与 OpenAI 入站转发
- `fluxctl`：CLI 管理 Provider/Gateway/Logs
- Desktop（占位壳）：Provider/Gateway/Logs 三面板与 Admin API 调用封装
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

更多操作见：

- `docs/USAGE.md`
- `docs/ops/local-runbook.md`
- `docs/testing/mvp-e2e.md`
- `docs/testing/frontend-parallel-checklist.md`
