# Quality Gate Realignment Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为 FluxDeck 建立统一的质量门禁定义，完成主线文档、主线脚本与原生端验证口径的重新对齐。

**Architecture:** 先建立唯一权威门禁文档，再把 README/USAGE/testing 文档改成引用同一套定义，最后收敛 `smoke.sh` 的职责并把遗留 Web 校验迁出主线。当前仓库没有现成 CI 工作流，因此本次实现聚焦“稳定门禁语义 + 稳定命令入口”，不给具体 CI 平台绑死。

**Tech Stack:** Markdown, Bash, Bun/TypeScript, Rust test commands, Xcodebuild

---

### Task 1: 建立唯一权威质量门禁文档

**Files:**
- Create: `docs/testing/quality-gates.md`
- Modify: `docs/README.md`
- Reference: `AGENTS.md`

**Step 1: 写出门禁定义文档**

在 `docs/testing/quality-gates.md` 中明确写出：

- `dev-gate`
- `ci-gate`
- `release-gate`
- `legacy-check`

并为每层写明：

- 适用场景
- 具体命令
- 是否强制包含原生端测试
- Web 桌面是否属于主线

**Step 2: 更新文档索引**

修改 `docs/README.md`：

- 把 `testing/mvp-e2e.md` 从“核心文档入口”降级
- 增加 `testing/quality-gates.md` 为测试门禁主入口

**Step 3: 人工检查语义是否唯一**

确认以下事实已经成立：

- `quality-gates.md` 是唯一权威定义
- 其他文档只引用，不重复定义不同版本

**Step 4: 验证**

检查：

```bash
sed -n '1,220p' docs/testing/quality-gates.md
sed -n '1,220p' docs/README.md
```

预期：

- 文档存在
- 四层门禁定义完整
- `docs/README.md` 已指向新入口

### Task 2: 对齐 README / USAGE / testing 文档口径

**Files:**
- Modify: `README.md`
- Modify: `docs/USAGE.md`
- Modify: `docs/testing/mvp-e2e.md`
- Reference: `apps/desktop-macos-native/README.md`

**Step 1: 重写 README 的提交前验证段**

修改 `README.md`：

- 不再直接写旧三条命令
- 改为简要说明三层门禁，并链接到 `docs/testing/quality-gates.md`

**Step 2: 重写 USAGE 的一键自检段**

修改 `docs/USAGE.md`：

- 不再把 Web 桌面测试写成默认推荐自检
- 改为引用 `dev-gate / ci-gate / release-gate`

**Step 3: 处理 `mvp-e2e.md`**

两种允许结果，选更简洁的一种：

- 方案 A：把 `mvp-e2e.md` 改成轻量重定向文档，明确“已被 `quality-gates.md` 取代”
- 方案 B：保留文件名，但内容完全改为引用新门禁文档，并明确自己不再是独立权威来源

推荐：方案 A。

**Step 4: 验证**

检查：

```bash
sed -n '120,190p' README.md
sed -n '400,470p' docs/USAGE.md
sed -n '1,220p' docs/testing/mvp-e2e.md
```

预期：

- 三份文档口径一致
- 主线默认门禁不再包含 `apps/desktop`
- 原生端验证已经被提升到主线正式门禁中

### Task 3: 收敛主线 smoke，迁出 legacy Web 校验

**Files:**
- Modify: `scripts/e2e/smoke.sh`
- Create: `scripts/e2e/legacy_web_consistency.sh`
- Modify or Create: `docs/testing/legacy-web-checks.md`
- Reference: `scripts/e2e/validate_cli_desktop_consistency.ts`

**Step 1: 从主 smoke 中移出 Web legacy 校验**

修改 `scripts/e2e/smoke.sh`：

- 保留 `cargo` / `fluxd` / `fluxctl` / OpenAI / Anthropic 主线 smoke
- 移除对 `validate_cli_desktop_consistency.ts` 的直接调用

**Step 2: 为 legacy Web 校验建立独立入口**

创建 `scripts/e2e/legacy_web_consistency.sh`：

- 单独调用现有 `validate_cli_desktop_consistency.ts`
- 明确这是 `legacy-check`

如果脚本不值得保留，也可只写文档并把 `.ts` 文件保留为手动入口；但推荐建独立 shell 入口。

**Step 3: 建立 legacy 文档归宿**

新增或修改 `docs/testing/legacy-web-checks.md`：

- 说明 Web 桌面当前是遗留兼容消费者
- 说明何时需要运行该检查
- 不再把它描述为主线门禁

**Step 4: 验证**

运行：

```bash
./scripts/e2e/smoke.sh
```

预期：

- 主 smoke 仍通过
- 输出 `smoke ok`
- 不再依赖 `apps/desktop`

### Task 4: 固化原生端在主线门禁中的位置

**Files:**
- Modify: `apps/desktop-macos-native/README.md`
- Modify: `docs/testing/quality-gates.md`
- Optional Create: `docs/testing/native-release-gate.md`

**Step 1: 在原生端 README 中补充门禁映射**

修改 `apps/desktop-macos-native/README.md`：

- 明确 `xcodebuild test` 属于 `ci-gate`
- 明确发布前至少要满足 `release-gate`

**Step 2: 在 `quality-gates.md` 中写清原生端责任**

明确：

- 原生端为何进入 `ci-gate`
- 为什么它不进入 `dev-gate`

**Step 3: 如有必要，预留 release 文档位置**

如果 `release-gate` 需要更细说明但暂不展开，可新增 `docs/testing/native-release-gate.md` 并标注待补充项。

推荐：

- 本轮先不新增该文档，避免空文档扩散
- 只在 `quality-gates.md` 中保留 release-gate 占位说明

**Step 4: 验证**

检查：

```bash
sed -n '1,220p' apps/desktop-macos-native/README.md
sed -n '1,260p' docs/testing/quality-gates.md
```

预期：

- 原生端测试已被明确提升到主线正式门禁
- 文档之间没有再次形成第二套说法

### Task 5: 形成最终验收与文档清理记录

**Files:**
- Modify: `docs/progress/2026-03-12-architecture-issue-backlog.md`
- Create: `docs/progress/2026-03-12-quality-gate-realignment.md`

**Step 1: 记录本次实施结果**

在进度文档中记录：

- 新增了哪份权威门禁文档
- 哪些主文档已完成口径统一
- 哪个脚本从主线迁移为 legacy

**Step 2: 明确未做项**

记录以下未做项，避免后续误解：

- 尚未接入具体 CI 平台
- 尚未实现正式分发级 release gate 自动化

**Step 3: 最终验证**

运行：

```bash
cargo test -q
./scripts/e2e/smoke.sh
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet
git status --short
```

预期：

- Rust 测试通过
- 主 smoke 通过
- 原生端测试通过
- 工作区只包含本次预期修改
