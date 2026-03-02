# FluxDeck macOS 原生壳（并行验证）

本目录提供 SwiftUI 原生壳，用于并行验证桌面端技术路线。

约束：

- 只实现 UI 与网络壳。
- Provider/Gateway/Logs 统一通过 `fluxd` Admin API 读取与操作。
- 不复制后端业务逻辑到前端。

## 构建

```bash
xcodebuild -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet
```

## 测试

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet
```
