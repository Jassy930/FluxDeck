# FluxDeck Quality Gate Realignment Design

日期：2026-03-12  
状态：已评审通过（用户确认）

## 1. 背景

当前仓库对“什么才算验证通过”存在多套定义：

- 仓库约定已经明确 `apps/desktop` 暂停，原生端为当前主线
- `README.md`、`docs/USAGE.md`、`docs/testing/mvp-e2e.md` 仍把 Web 桌面测试作为默认门禁
- `scripts/e2e/smoke.sh` 仍依赖 `apps/desktop/src/api/admin`
- 原生端已是主产品，但没有进入仓库默认主线验收口径

这会导致：

- 文档之间相互冲突
- 后端与原生端架构演进持续被遗留 Web 桌面实现绑住
- 后续接入 CI 或发布门禁时缺少唯一权威语义

## 2. 目标

本次设计目标：

1. 定义唯一官方质量门禁体系
2. 同时覆盖本地开发、CI、原生端发布前三种场景
3. 让主线门禁与当前产品优先级重新对齐
4. 把遗留 Web 桌面校验降级为显式 legacy 检查
5. 为后续接入任何 CI 平台保留稳定命令接口

## 3. 非目标

本次不做：

- 立即接入某个具体 CI 提供商
- 一次性重做所有测试脚本
- 立即删除所有 Web 桌面相关代码
- 把原生端发布流程补齐到正式分发级别

## 4. 方案对比

### 方案 A：单一重门禁

做法：

- 所有场景统一跑：
  - `cargo test -q`
  - `./scripts/e2e/smoke.sh`
  - `xcodebuild test ...`

优点：

- 定义最简单
- 文档最统一

缺点：

- 日常开发成本过高
- 小改动也要承担原生端全量验证成本

### 方案 B：分层门禁

做法：

- 定义三层主线门禁：
  - `dev-gate`
  - `ci-gate`
  - `release-gate`
- 另设 `legacy-check`

优点：

- 与当前项目阶段最匹配
- 能统一语义，又不把日常开发拖慢
- 便于后续接入 CI / 发布流程

缺点：

- 需要额外写清楚每层职责

### 方案 C：双主线门禁

做法：

- 后端/CLI 一套门禁
- 原生端另一套门禁

优点：

- 表面上分工清晰

缺点：

- 容易重新形成多套真相
- 不利于仓库层面的统一叙事

## 5. 方案选择

结论：采用方案 B。

原因：

- 当前仓库已不是纯后端项目，但也尚未到“每次开发都必须跑发布级验证”的阶段
- 原生端已是主产品，必须进入正式主线门禁
- 遗留 Web 校验仍可保留，但必须退出默认主线

## 6. 详细设计

### 6.1 门禁分层定义

#### `dev-gate`

用途：

- 本地日常开发快速验证

建议命令：

- `cargo test -q`
- `./scripts/e2e/smoke.sh`

原则：

- 不默认包含 `xcodebuild test`
- 目标是快速确认核心链路未明显损坏

#### `ci-gate`

用途：

- PR / 主分支合并前验证

建议命令：

- `cargo test -q`
- `./scripts/e2e/smoke.sh`
- `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`

原则：

- 原生端已纳入主线产品质量门禁
- 不再把 Web 桌面测试作为默认组成部分

#### `release-gate`

用途：

- 原生端发布前验证

建议范围：

- 包含 `ci-gate` 全部内容
- 再叠加原生端构建与发布前专项检查

原则：

- 本次先定义门位与责任，不强行一次写满全部发布细节
- 与正式分发方案逐步衔接

#### `legacy-check`

用途：

- 对遗留 Web 桌面或历史兼容链路做额外检查

原则：

- 只能作为附加检查存在
- 不能继续出现在主线默认门禁中

### 6.2 权威文档入口

新增：

- `docs/testing/quality-gates.md`

职责：

- 只定义四个概念：`dev-gate`、`ci-gate`、`release-gate`、`legacy-check`
- 作为唯一权威入口

其他文档的处理原则：

- `README.md` 只保留简版说明并引用该文档
- `docs/USAGE.md` 不再单独定义一套门禁
- `docs/testing/mvp-e2e.md` 合并或重定向到新入口

### 6.3 脚本职责收敛

`scripts/e2e/smoke.sh` 的角色调整为：

- 只承担主线 `core smoke`
- 仅验证后端、CLI、核心转发与协议兼容链路
- 不再依赖 `apps/desktop`

遗留 Web 一致性校验处理方式：

- 独立迁出为单独脚本或单独 testing 文档
- 例如：
  - `scripts/e2e/legacy_web_consistency.sh`
  - `docs/testing/legacy-web-checks.md`

### 6.4 CI 对接策略

当前仓库尚未发现既有 `.github/workflows` 或其他 CI 配置。

因此本次不直接绑定具体平台，而是先建立：

- 稳定的门禁语义
- 稳定的命令入口
- 稳定的文档引用结构

后续无论接 GitHub Actions、其他 CI 还是本地自动化，都直接映射：

- `dev-gate`
- `ci-gate`
- `release-gate`
- `legacy-check`

### 6.5 原生端角色修正

原生端目前已是主线产品，因此其验证规则应从“附属说明”提升为“主线门禁组成部分”。

调整原则：

- `apps/desktop-macos-native/README.md` 保留原生端自身构建/测试命令
- 主线文档必须把原生端验证放入 `ci-gate` 或更高层
- 不再允许主线验收只覆盖后端与遗留 Web 消费者

## 7. 迁移顺序

建议顺序：

1. 新建 `docs/testing/quality-gates.md`
2. 修改 `README.md`、`docs/USAGE.md`、`docs/testing/mvp-e2e.md`
3. 调整 `scripts/e2e/smoke.sh`，剥离 Web legacy 校验
4. 新建 legacy 校验的脚本或文档归宿
5. 在原生端 README 与 testing 文档中补齐映射关系

## 8. 风险与控制

### 风险 1：移除 Web 校验后短期少一条跨消费者一致性检查

控制：

- 不直接删除
- 先迁出为 `legacy-check`

### 风险 2：把原生端纳入主线门禁后，团队感知到验证变重

控制：

- `dev-gate` 不包含 `xcodebuild test`
- 只在 `ci-gate` / `release-gate` 强制纳入原生端

## 9. 验收标准

- 所有主入口文档对质量门禁的描述一致
- Web 桌面不再出现在主线默认门禁中
- `smoke.sh` 不再依赖 `apps/desktop`
- 原生端正式进入 `ci-gate` 或更高层门禁
- legacy Web 校验有明确归宿，而不是隐式删除
