# 2026-03-12 Provider / Gateway 删除功能进度

## 已完成

- `fluxd` 新增 Provider / Gateway 删除接口
- Provider 删除支持“被 Gateway 引用时返回冲突与引用列表”
- Gateway 删除支持“运行中自动 stop -> delete”
- 修复 `request_logs` 外键导致的误拦截，历史日志不再阻止 Provider / Gateway 删除
- `fluxctl` 新增 `provider delete` / `gateway delete`
- `fluxctl` 删除命令支持默认确认与 `-y` / `--yes`
- 原生桌面端新增 Provider / Gateway 删除入口与确认弹窗
- 原生桌面端删除请求支持更可读的服务端错误解析

## 验证

- `cargo test -q`
- `./scripts/e2e/smoke.sh`
- `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`

说明：

- `apps/desktop` 当前处于暂缓处理阶段，本次及后续收尾流程默认跳过其实现变更与 `bun run test`
- 本次删除功能交付范围限定为 `fluxd`、`fluxctl` 与 `apps/desktop-macos-native`

## 当前限制

- 目前仅阻止删除仍被 Gateway 引用的 Provider，不做级联删除
- Gateway 删除结果只返回删除前运行态，不保留删除后的运行态快照
- 原生端删除冲突仍通过现有 `loadError` / `operationNotice` 展示，未引入新的 toast 系统
