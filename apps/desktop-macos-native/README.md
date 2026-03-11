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

说明：

- 现阶段重点是统一原生桌面壳层与页面风格
- 仍复用 `fluxd` Admin API 的现有数据流
- Provider 表单中的 `kind` 已改为固定选择，不再允许自由文本输入
- Provider `kind` 提交机器值：`openai | openai-response | gemini | anthropic | azure-openai | new-api | ollama`
- `Traffic` 页面现已接入 `/admin/stats/overview` 与 `/admin/stats/trend`
- `Traffic` 支持 `1h / 6h / 24h` 时间范围切换、关键指标、趋势、维度分布和异常摘要
- `Traffic` 已进一步压缩为高密度监控台布局，优先首屏扫描 KPI 与趋势主区
- `Traffic` 的 4 个主要 KPI 现已合并为单条连续指标栏，减少首屏留白
- 复杂实时拓扑与更细粒度图表留待后续阶段扩展

## 构建

```bash
xcodebuild -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet
```

## 测试

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet
```
