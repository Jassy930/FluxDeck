# Quality Gates

`docs/testing/quality-gates.md` 是 FluxDeck 当前唯一权威质量门禁定义。其他文档只能引用本页，不应再各自维护独立版本。

## 总则

- 主线范围：`fluxd`、`fluxctl`、共享 E2E 脚本、`apps/desktop-macos-native`
- 非主线范围：`apps/desktop` 当前仅作为遗留兼容消费者，不属于默认质量门禁
- 命令入口优先保持稳定，不绑定具体 CI 平台实现

## Gate Matrix

| Gate | 适用场景 | 命令 | 是否强制包含原生端测试 | `apps/desktop` 是否属于主线 |
|------|----------|------|------------------------|-----------------------------|
| `dev-gate` | 本地日常开发、自测、提交前快速回归 | `cargo test -q`<br>`./scripts/e2e/smoke.sh` | 否 | 否 |
| `ci-gate` | 分支合并前、共享流水线、需要覆盖主线交付链路时 | `cargo test -q`<br>`./scripts/e2e/smoke.sh`<br>`xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet` | 是 | 否 |
| `release-gate` | 原生桌面发布前、打包前、候选版本验收 | `cargo test -q`<br>`./scripts/e2e/smoke.sh`<br>`xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`<br>`xcodebuild -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet` | 是 | 否 |
| `legacy-check` | 修改遗留 Web 桌面消费者、排查 CLI 与 Web 一致性问题时按需执行 | `./scripts/e2e/legacy_web_consistency.sh <admin-url>` | 否 | 否，属于兼容性专项检查 |

## Gate Definitions

### `dev-gate`

- 适用场景：本地开发期间的默认自检，以及不涉及原生端交付面的快速回归。
- 具体命令：

```bash
cargo test -q
./scripts/e2e/smoke.sh
```

- 原生端测试：不强制纳入。原因是 `xcodebuild test` 成本较高，不适合作为每次本地迭代的默认门禁。
- Web 桌面定位：`apps/desktop` 不属于主线门禁。

### `ci-gate`

- 适用场景：分支合并前、共享验证环境、需要确认主线交付物完整性时。
- 具体命令：

```bash
cargo test -q
./scripts/e2e/smoke.sh
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet
```

- 原生端测试：强制纳入。原因是当前仓库的桌面主线已切换到原生端，主线质量门禁必须覆盖它。
- Web 桌面定位：仍不属于主线，仅在兼容性专项检查中出现。

### `release-gate`

- 适用场景：原生桌面发布前、候选版本验收、需要确认可交付构建产物时。
- 具体命令：

```bash
cargo test -q
./scripts/e2e/smoke.sh
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet
xcodebuild -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet
```

- 原生端测试：强制纳入，并要求额外完成原生壳构建验证。
- Web 桌面定位：不属于发布主线。
- 说明：当前仅固化命令语义，尚未把正式分发级校验自动化接入具体 CI 平台。

### `legacy-check`

- 适用场景：仅在修改 `apps/desktop` 或排查 CLI 与遗留 Web 消费者的数据一致性时执行。
- 具体命令：

```bash
./scripts/e2e/legacy_web_consistency.sh <admin-url>
```

- 原生端测试：不包含。
- Web 桌面定位：这是遗留兼容检查，不是主线门禁。
- 说明：`legacy-check` 依赖 `scripts/e2e/validate_cli_desktop_consistency.ts`，但该校验已从主线 `smoke.sh` 中迁出。

## 原生端责任映射

- `apps/desktop-macos-native` 已是当前桌面主线交付物，因此必须进入 `ci-gate`
- 原生端不进入 `dev-gate`，是为了保留本地快速回归速度；`xcodebuild test` 与原生构建成本更适合作为共享验证和发布前门禁
- 发布前至少满足 `release-gate`，否则不能把原生端视为已完成交付验证
