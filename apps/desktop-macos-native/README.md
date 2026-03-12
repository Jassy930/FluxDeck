# FluxDeck macOS 原生壳（并行验证）

本目录提供 SwiftUI 原生壳，用于并行验证桌面端技术路线。

约束：

- 只实现 UI 与网络壳。
- Provider/Gateway/Logs 统一通过 `fluxd` Admin API 读取与操作。
- 不复制后端业务逻辑到前端。

当前原生界面已经切换到统一工作台式信息架构，包含：

- `Overview` 监控首页
- `Traffic` 真实统计监控页
- `Connections` 活跃连接页
- `Topology` 路由拓扑骨架页
- `Providers / Gateways / Logs / Settings` 统一深色工作台风格
- `Logs` 已重构为单列可展开紧凑日志行，折叠态优先显示状态、路由、模型映射、错误摘要、token 摘要与延迟

说明：

- 现阶段重点是统一原生桌面壳层与页面风格
- 仍复用 `fluxd` Admin API 的现有数据流
- Provider 表单中的 `kind` 已改为固定选择，不再允许自由文本输入
- Provider `kind` 提交机器值：`openai | openai-response | gemini | anthropic | azure-openai | new-api | ollama`
- Gateway 表单中的 `Inbound Protocol` 已与 Provider `kind` 使用同一组七种协议类型
- Gateway 表单中的 `Upstream Protocol` 使用：`provider_default | openai | openai-response | gemini | anthropic | azure-openai | new-api | ollama`
- Gateway 协议 Picker 选项已改为从共享的 `ProviderKindOption` 派生，避免前后不一致
- `Traffic` 页面现已接入 `/admin/stats/overview` 与 `/admin/stats/trend`
- `Traffic` 支持 `1h / 6h / 24h` 时间范围切换、关键指标、趋势、维度分布和异常摘要
- `Traffic` 已进一步压缩为高密度监控台布局，优先首屏扫描 KPI 与趋势主区
- `Traffic` 的 4 个主要 KPI 现已合并为单条连续指标栏，减少首屏留白
- `Providers / Gateways` 工作台支持删除操作
- 删除 Provider 时若仍被 Gateway 引用，界面会直接展示冲突错误与引用方信息
- Gateway 可独立删除；删除运行中的 Gateway 时，服务端会先停机再删除，原生端优先展示服务端返回的删除提示
- 复杂实时拓扑与更细粒度图表留待后续阶段扩展

## 构建

```bash
xcodebuild -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet
```

## 测试

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet
```

## 质量门禁映射

- `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet` 属于主线 `ci-gate`
- 发布前至少满足 `release-gate`，即在 `ci-gate` 基础上再完成原生端构建验证
- 完整定义统一参考 `docs/testing/quality-gates.md`
