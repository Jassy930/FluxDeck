# MVP E2E 验证

## 前置要求

- Rust 工具链可用
- `uv` 可用
- `bun` 可用（桌面端测试）

## 执行命令

```bash
cargo test -q
cd apps/desktop && bun run test
cd ../..
./scripts/e2e/smoke.sh
```

> 说明：`bun run test --cwd apps/desktop` 在当前 bun 版本下会被解析为脚本参数，建议使用上面的等价写法。

## 通过标准

- `cargo test -q` 全部通过
- 桌面端测试通过
- `smoke.sh` 输出 `smoke ok`
