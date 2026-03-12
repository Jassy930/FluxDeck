# 2026-03-11 Gateway 更新后自动重启

## 目标

- 当运行中的 Gateway 保存编辑后确实发生配置变化时，自动执行 `stop -> start`
- 让原生桌面端 UI 与 `fluxctl` 明确提示用户是否发生了自动重启

## 背景

- 旧行为中，`PUT /admin/gateways/{id}` 只更新数据库
- 如果 Gateway 已经在运行，运行时 listener 仍继续使用旧配置
- 这会造成“界面显示已保存，但真实监听地址/协议仍是旧值”的错觉

## 实现

### fluxd

- 在 `crates/fluxd/src/http/admin_routes.rs` 中扩展 `PUT /admin/gateways/{id}`：
  - 先读取旧 Gateway 配置
  - 比较所有 Gateway 配置字段是否真的变化
  - 判断更新前实例是否为 `running`
  - 仅在 `running && config_changed` 时执行自动 `stop -> start`
- 返回结构扩展为：
  - `gateway`
  - `runtime_status`
  - `last_error`
  - `restart_performed`
  - `config_changed`
  - `user_notice`

### fluxctl

- `gateway update` 继续打印完整 JSON
- 如果返回里存在 `user_notice`，额外在 stderr 打印：

```text
Notice: ...
```

### 原生桌面端

- `AdminApiClient.updateGateway` 改为解码 `AdminGatewayUpdateResult`
- `ContentView` 在保存成功后显示 `user_notice`
- `Gateway` 表单说明文案改为“运行中且配置变化时会自动重启”

## 验证

已执行：

```bash
cargo test -p fluxd admin_api_ --test admin_api_test -q
cargo test -p fluxctl -q
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet
```

结果：

- `fluxd` 的 Gateway 更新行为测试通过
- `fluxctl` 测试通过
- 原生桌面端测试通过

## 行为说明

- 运行中且任一 Gateway 配置字段变化 -> 自动重启
- 运行中但无变化 -> 不重启
- 未运行 -> 只保存配置，不自动启动
- 自动重启失败 -> 配置仍保存成功，错误通过 `last_error` / `user_notice` 返回
