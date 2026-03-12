# 2026-03-12 Quality Gate Realignment 调研与计划

## 本次完成内容

- 基于 `quality-gate-realignment` 问题完成一轮详细调研
- 与用户确认采用“分层门禁方案”
- 形成设计文档与实施计划文档

## 结论

本次问题不直接绑定某个具体 CI 平台，而是先建立：

- 唯一权威质量门禁定义
- 主线文档统一引用关系
- 主线 smoke 与 legacy Web 校验的职责拆分
- 原生端正式进入主线门禁的定义位置

## 新增文档

- `docs/plans/active/2026-03-12-quality-gate-realignment-design.md`
- `docs/plans/active/2026-03-12-quality-gate-realignment.md`

## 后续实施重点

1. 新增 `docs/testing/quality-gates.md`
2. 对齐 `README.md`、`docs/USAGE.md`、`docs/testing/mvp-e2e.md`
3. 调整 `scripts/e2e/smoke.sh` 并迁出 legacy Web 校验
4. 把原生端测试正式纳入主线门禁定义

## 未在本次处理的内容

- 具体 CI 平台接入
- 正式分发级 release gate 自动化
- 实现代码层面的脚本与文档改造

## 本次实施

- 新增唯一权威门禁文档 `docs/testing/quality-gates.md`
- 将 `README.md`、`docs/USAGE.md`、`docs/README.md`、`docs/testing/mvp-e2e.md` 对齐到同一套门禁口径
- 将 `scripts/e2e/validate_cli_desktop_consistency.ts` 从主线 `scripts/e2e/smoke.sh` 中迁出，改由 `scripts/e2e/legacy_web_consistency.sh` 承接
- 新增 `docs/testing/legacy-web-checks.md`，明确 `apps/desktop` 仅作为遗留兼容消费者存在
- 在 `apps/desktop-macos-native/README.md` 中固化原生端与 `ci-gate` / `release-gate` 的映射关系
- 将执行依据计划 `docs/plans/active/2026-03-12-quality-gate-realignment.md` 补入版本化文档

## 实施结果

- `quality-gates.md` 成为唯一权威定义
- 主线默认门禁不再包含 `apps/desktop`
- 原生端测试被正式提升到 `ci-gate`
- 原生端发布前需满足 `release-gate`

## 当前未做项

- 尚未接入具体 CI 平台
- 尚未实现正式分发级 `release-gate` 自动化
