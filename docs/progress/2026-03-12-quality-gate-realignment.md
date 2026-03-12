# 2026-03-12 Quality Gate Realignment

## 目标

统一 FluxDeck 主线质量门禁定义，消除 README、USAGE、testing 文档与主 smoke 脚本之间的旧口径分裂。

## 本次实施

- 新增唯一权威门禁文档 `docs/testing/quality-gates.md`
- 将 `README.md`、`docs/USAGE.md`、`docs/README.md`、`docs/testing/mvp-e2e.md` 对齐到同一套门禁口径
- 将 `scripts/e2e/validate_cli_desktop_consistency.ts` 从主线 `scripts/e2e/smoke.sh` 中迁出，改由 `scripts/e2e/legacy_web_consistency.sh` 承接
- 新增 `docs/testing/legacy-web-checks.md`，明确 `apps/desktop` 仅作为遗留兼容消费者存在
- 在 `apps/desktop-macos-native/README.md` 中固化原生端与 `ci-gate` / `release-gate` 的映射关系
- 将执行依据计划 `docs/plans/active/2026-03-12-quality-gate-realignment.md` 补入版本化文档

## 结果

- `quality-gates.md` 成为唯一权威定义
- 主线默认门禁不再包含 `apps/desktop`
- 原生端测试被正式提升到 `ci-gate`
- 原生端发布前需满足 `release-gate`

## 未做项

- 尚未接入具体 CI 平台
- 尚未实现正式分发级 `release-gate` 自动化
