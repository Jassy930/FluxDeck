# 2026-03-13 代理自检与整备记录

## 本次目标

- 建立项目现状的真实基线
- 识别代码、文档、测试、计划与实现方向之间的漂移
- 直接修复低风险、高收益的系统记录问题

## 主要发现

- 仓库根缺少 `ARCHITECTURE.md`，导致“架构入口”只能分散在 `AGENTS.md`、`README.md` 和历史评审文档中查找。
- `README.md`、`docs/testing/quality-gates.md`、`apps/desktop-macos-native/README.md` 已经基本对齐“原生端主线、Web 遗留”的现实。
- `docs/USAGE.md` 仍保留 `apps/desktop` 开发入口、并行交付清单引用和重复尾部段落，属于明显过时与腐化。
- `docs/testing/frontend-parallel-checklist.md` 属于历史阶段交付物，但缺少显式“历史文档”标记。
- `docs/plans/active/2026-03-12-architecture-issue-backlog.md` 中关于 `quality-gate-realignment` 与 `smoke-vs-legacy-web-coupling` 的问题陈述已部分过时，需要补充实施状态。
- 代码层面的主要风险依然成立：
  - `apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift` 约 2500 行，根视图状态过载
  - `apps/desktop-macos-native/FluxDeckNative/Networking/AdminApiClient.swift` 约 1200 行，DTO/传输/错误语义集中
  - `crates/fluxd/src/http/admin_routes.rs` 仍承担较重的控制面编排
  - `crates/fluxctl/src/client.rs` 仍以 `serde_json::Value` 为主消费契约

## 本次直接落地

- 新增 `ARCHITECTURE.md` 作为稳定架构入口
- 新增 `docs/product/current-state.md` 作为当前产品目标与约束入口
- 新增 `docs/plans/README.md` 作为计划生命周期规则入口
- 修正文档入口与交叉引用，使 `README` / `ARCHITECTURE` / `docs/README` / `quality-gates` 更容易互相印证
- 清理 `docs/USAGE.md` 中的旧主线叙事与重复段落
- 给历史性的前端并行验收文档增加“仅供历史参考”标记
- 为架构问题清单补充已实施状态说明，避免继续把已解决问题当作现状
- 新增 `scripts/check_docs_plan_layout.sh`，把计划目录生命周期中的常见漂移转成可执行检查
- 完成一轮 `docs/plans` 归位：根目录普通计划分流到 `active/` / `completed/`，并将多份已完成计划从 `active/` 迁出

## 本次未动

- 未修改 `crates/fluxd/src/http/passthrough.rs` 等当前工作区已有未提交实现代码
- 未推进中高风险的架构拆分或接口重塑

## 后续建议

- 单独启动 `docs-information-architecture-cleanup`，处理 `docs/plans/` 根目录与历史 testing 文档的归档策略
- 单独启动 `native-admin-client-decomposition` 与 `native-root-store-split`
- 为 `quality-gates` 增加 capability-to-test 映射，减少靠记忆理解覆盖面的风险
- 视情况把 `./scripts/check_docs_plan_layout.sh` 纳入后续 `ci-gate` 或独立文档治理检查
