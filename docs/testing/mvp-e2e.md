# MVP E2E 验证

## 前置要求

- Rust 工具链可用
- `uv` 可用
- `bun` 可用（桌面端测试）

## 执行命令

```bash
cargo test -q
bun run test --cwd apps/desktop
./scripts/e2e/smoke.sh
```

## 通过标准

- `cargo test -q` 全部通过
- 桌面端测试通过
- `smoke.sh` 输出 `smoke ok`
