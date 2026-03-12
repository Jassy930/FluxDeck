# FluxDeck Repository Architecture Review Plan

**Goal:** 对整个仓库进行一次架构层面的深度评审，识别影响未来 6-18 个月演进的结构性风险，并提出分阶段调整建议。

**Scope:** `crates/fluxd`、`crates/fluxctl`、`apps/desktop-macos-native`、核心文档与测试资产；不深入逐行挑错，以模块边界、职责分配、数据契约、运行时模型和长期维护成本为主。

**Review Method:**
- 先阅读系统记录文档，确认项目自述、契约边界与当前开发优先级
- 再检查核心实现入口、分层目录与关键服务/运行时代码
- 对原生桌面端与 Admin API 的耦合方式做单独审查
- 最后汇总测试面、运维面和长期演进风险，形成建议清单

**Deliverables:**
- 一份面向长期演进的架构评审结论
- 明确列出高优先级结构性问题、影响范围与建议方案
- 同步一份 `docs/progress/` 记录，便于后续追踪

**Focus Questions:**
1. `fluxd` 当前分层是否真正形成稳定边界，还是仍有“单体内部耦合”风险？
2. 管理面（Admin API）与数据面（Gateway forwarding/runtime）是否需要进一步解耦？
3. 原生桌面端是否已经形成稳定的应用层边界，还是仍然直接承接后端契约波动？
4. 测试、文档与运行手册是否足以支撑未来持续迭代和协议扩展？
