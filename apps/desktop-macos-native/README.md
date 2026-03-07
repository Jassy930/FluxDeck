# FluxDeck macOS 原生壳（并行验证）

本目录提供 SwiftUI 原生壳，用于并行验证桌面端技术路线。

约束：

- 只实现 UI 与网络壳。
- Provider/Gateway/Logs 统一通过 `fluxd` Admin API 读取与操作。
- 不复制后端业务逻辑到前端。

当前原生界面已经切换到统一工作台式信息架构，包含：

- `Overview` 监控首页
- `Traffic` 流量分析页
- `Connections` 活跃连接页
- `Topology` 路由拓扑骨架页
- `Providers / Gateways / Logs / Settings` 统一深色工作台风格

说明：

- 现阶段重点是统一原生桌面壳层与页面风格
- 仍复用 `fluxd` Admin API 的现有数据流
- 复杂实时拓扑与更细粒度图表留待后续阶段扩展

## 构建

```bash
xcodebuild -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet
```

## 测试

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet
```
