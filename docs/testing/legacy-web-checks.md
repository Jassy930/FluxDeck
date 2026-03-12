# Legacy Web Checks

`apps/desktop` 当前是 FluxDeck 的遗留兼容消费者，不属于主线默认质量门禁。

## 何时需要运行

仅在以下场景执行：

- 修改 `apps/desktop` 的 Admin API 消费逻辑
- 排查 CLI 与遗留 Web 桌面数据展示不一致
- 需要确认旧桌面消费者仍可读取当前后端返回结构

## 命令入口

```bash
./scripts/e2e/legacy_web_consistency.sh <admin-url>
```

该脚本会调用：

- `scripts/e2e/validate_cli_desktop_consistency.ts`

## 与主线门禁的关系

- 它属于 `legacy-check`
- 它不属于 `dev-gate`
- 它不属于 `ci-gate`
- 它不属于 `release-gate`

如果需要查看主线门禁定义，统一参考：

- [docs/testing/quality-gates.md](./quality-gates.md)
