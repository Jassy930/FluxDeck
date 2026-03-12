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
