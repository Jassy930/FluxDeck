# 2026-03-12 Native Shell Header Merge

## 本次完成

- 将原生壳层 `TopModeBar` 扩展为统一工作区顶栏
- 将 `Admin` endpoint、最近刷新时间和全局 `Refresh` 入口合并进壳层顶栏
- 删除 `ContentView` 常驻的重复 admin 信息栏
- 将全局加载错误降级为按需显示的错误横幅，仅在失败时占用额外高度
- 为壳层顶栏新增最小模型测试，约束 endpoint 与刷新元信息输出

## 主要文件

- `apps/desktop-macos-native/FluxDeckNative/UI/TopModeBar.swift`
- `apps/desktop-macos-native/FluxDeckNative/UI/AppShellView.swift`
- `apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift`
- `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`

## 验证

已执行：

```bash
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testShellToolbarModelBuildsEndpointAndRefreshMetadata -quiet
xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet
```

结果：

- 通过
- 仍有 XCTest 链接到更高 macOS 版本的告警，不影响测试结果

## 设计结果

- 页面顶部常态下只保留一层壳级信息栏
- 业务内容区更早进入 `Traffic Monitor` 等主卡片
- 顶栏仍保留模式切换、全局状态胶囊和刷新能力
