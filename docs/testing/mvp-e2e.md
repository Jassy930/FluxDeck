# MVP E2E 验证（历史入口）

`docs/testing/mvp-e2e.md` 已不再维护独立门禁定义。

当前 FluxDeck 的唯一权威质量门禁文档是：

- [docs/testing/quality-gates.md](./quality-gates.md)

迁移说明：

- 原先混合 Rust、Web 桌面与 smoke 的旧口径已废弃
- `apps/desktop` 不再属于主线默认门禁
- 原生端测试已提升到 `ci-gate` / `release-gate`

如果你是从旧文档跳转过来，请直接以 `quality-gates.md` 为准。
