# 前端并行交付验收清单

本文档用于验收「Tauri 主线 + macOS 原生壳支线」并行交付结果。

## 一、前置条件

- `fluxd` 与 `fluxctl` 代码可编译。
- 本机可用 `bun`、`cargo`、`xcodebuild`。
- 如需联调，请先启动 `fluxd` Admin API（默认 `127.0.0.1:7777`）。

## 二、契约一致性

- [ ] Admin API 契约文档已锁定：`docs/contracts/admin-api-v1.md`
- [ ] 契约测试通过：`cargo test -p fluxd admin_api_response_shape_is_stable -q`
- [ ] Gateway 运行状态测试通过：`cargo test -p fluxd admin_api_returns_gateway_runtime_status -q`

## 三、Tauri 主线

- [ ] 桌面端测试通过：`cd apps/desktop && bun run test`
- [ ] 可通过 UI 动作创建 Provider/Gateway，并触发刷新
- [ ] 能看到 Gateway 运行状态和错误信息
- [ ] CLI 与桌面 Admin API 结果一致：`./scripts/e2e/smoke.sh` 输出 `cli-desktop consistency ok`

## 四、macOS 原生壳支线

- [ ] 工程可构建：`xcodebuild -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`
- [ ] 单元测试通过：`xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`
- [ ] Provider/Gateway 列表来自 Admin API（不复制后端业务逻辑）

## 五、总验收命令

在仓库根目录执行：

```bash
cargo test -q
cd apps/desktop && bun run test
cd ../..
./scripts/e2e/smoke.sh
```

> 说明：`bun run test --cwd apps/desktop` 在当前 bun 版本下会被解析为脚本参数，建议使用上面的等价写法。
>
> 若 `cargo test -q` 出现 `E0463 can't find crate`，先执行 `cargo clean` 再重试。

## 六、交付标准

- [ ] 三段验收命令全部通过
- [ ] `docs/progress/2026-03-02-dev-log.md` 记录到最新阶段
- [ ] `git status --short` 干净或仅包含待交付改动
