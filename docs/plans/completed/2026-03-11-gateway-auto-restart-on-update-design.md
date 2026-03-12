# FluxDeck Gateway 更新后自动重启设计

## 目标

当 Gateway 当前处于 `running`，且用户保存的配置相对旧配置确实发生了变化时，系统自动执行 `stop -> start`，避免“保存成功但运行时仍沿用旧 listener/协议参数”的隐性错误。

本次设计覆盖两个对外入口：

- 原生桌面端 UI
- `fluxctl`

统一的运行时语义由 `fluxd` 提供，客户端只负责展示结果与提醒用户。

## 根因与设计动机

当前 `PUT /admin/gateways/{id}` 只更新数据库，不影响已运行的 Gateway 实例。实际 listener 仍继续使用旧配置，直到用户手动执行 `stop -> start`。这会导致如下问题：

- UI 中看到的新 `listen_host` / `listen_port` 与真实监听地址不一致
- 用户误以为配置已经生效
- 远程访问或协议切换等场景产生“保存成功但请求失败”的隐蔽问题

该行为已经在文档中有说明，但实际使用中依然容易漏掉，因此需要改为系统默认兜底。

## 方案选择

### 方案 A：由 `fluxd` 在 Gateway 更新后统一判定并自动重启

优点：

- 单一真相来源，原生 UI、`fluxctl` 和未来其他客户端都复用同一语义
- 服务端最容易拿到“更新前运行态”和“配置是否变化”的准确信息
- 可以将“是否自动重启”作为稳定返回字段提供给各客户端

缺点：

- 需要扩展 `PUT /admin/gateways/{id}` 返回结构

### 方案 B：原生 UI 与 `fluxctl` 分别自行执行 `stop -> start`

优点：

- 服务端接口看起来改动较小

缺点：

- 逻辑重复
- 容易在多个客户端间出现行为不一致
- 未来增加新入口时继续漏掉

### 结论

采用方案 A。

## 行为规则

仅当以下两个条件同时满足时自动重启：

1. 更新前 Gateway 运行态为 `running`
2. 新旧 Gateway 配置存在实质差异

以下情况不触发自动重启：

- Gateway 当前不是 `running`
- 提交内容与数据库中的现有配置完全一致

“实质差异”按整个 `UpdateGatewayInput` 对应字段比较：

- `name`
- `listen_host`
- `listen_port`
- `inbound_protocol`
- `upstream_protocol`
- `protocol_config_json`
- `default_provider_id`
- `default_model`
- `enabled`
- `auto_start`

## API 设计

`PUT /admin/gateways/{id}` 从“直接返回 Gateway 对象”扩展为返回带运行时元信息的对象：

```json
{
  "gateway": { "...": "更新后的 Gateway" },
  "runtime_status": "running",
  "last_error": null,
  "restart_performed": true,
  "config_changed": true,
  "user_notice": "Gateway 配置已保存。检测到该实例正在运行且配置发生变化，系统已自动重启以应用变更。"
}
```

字段语义：

- `gateway`：更新后的持久化配置
- `runtime_status`：更新完成后的运行状态
- `last_error`：自动重启失败时提供错误细节
- `restart_performed`：本次是否实际执行了 `stop -> start`
- `config_changed`：本次提交是否真的改动了配置
- `user_notice`：供 UI / CLI 直接展示的人类可读提示

## 服务端实现思路

`fluxd` 的 `update_gateway` 流程调整为：

1. 读取更新前 Gateway
2. 读取更新前运行态
3. 计算 `config_changed`
4. 更新数据库
5. 如果 `running && config_changed`：
   - 调用 `gateway_manager.stop_gateway`
   - 再调用 `gateway_manager.start_gateway`
6. 返回扩展后的更新结果对象

若自动重启失败：

- `PUT` 返回 `200`
- `runtime_status` 根据当前实际状态回填
- `last_error` 包含失败信息
- `user_notice` 明确提示“配置已保存，但自动重启失败”

理由：

- 配置持久化与运行态应用是两个层面
- 只要数据库更新成功，就不应把整个请求视为持久化失败
- 客户端可基于 `last_error` 与 `user_notice` 提示用户下一步动作

## 原生桌面端 UI

原生端不再假设 `updateGateway` 只返回 `AdminGateway`，而是解码新的更新结果对象。

交互更新：

- 保存成功且 `restart_performed=false`
  - 关闭编辑弹窗
  - 正常刷新列表
  - 显示轻量成功提示：`Gateway 配置已保存`
- 保存成功且 `restart_performed=true`
  - 关闭编辑弹窗
  - 刷新列表
  - 显示提示：`Gateway 配置已保存，运行中的实例已自动重启`
- 保存成功但 `last_error != nil`
  - 保持成功路径，但提示内容改为“配置已保存，自动重启失败：...”

同时移除或改写当前表单里的“需手动 stop/start”说明文案。

## fluxctl

`fluxctl gateway update` 继续请求同一个 `PUT /admin/gateways/{id}`。

输出策略：

- 始终打印完整 JSON 结果
- 若 `user_notice` 存在，再额外打印一行可读提示，便于终端快速识别

这样既保留机器可解析输出，也保留人类可读反馈。

## 测试策略

### fluxd

- 运行中且配置变化 -> 自动重启，且新监听地址生效
- 运行中但配置未变化 -> 不重启
- 停止态且配置变化 -> 不重启
- 自动重启失败 -> 持久化成功，返回 `last_error`

### 原生桌面端

- 解码新的 Gateway 更新结果
- 根据 `restart_performed` / `user_notice` 生成正确提示文案

### fluxctl

- 为 Gateway 更新结果对象增加解码覆盖
- 验证 update 输出仍包含 JSON，且在存在 `user_notice` 时额外打印提示

## 非目标

- 不修改 Provider 更新行为
- 不引入 Gateway 热更新
- 不改变 `create gateway` 的行为
- 不在本次引入 toast 组件系统级重构，只做最小提示集成
