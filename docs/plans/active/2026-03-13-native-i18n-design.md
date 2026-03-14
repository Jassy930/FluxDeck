# FluxDeck Native 多语言支持设计

## 文档状态

- 状态：已确认方案，待实现
- 类型：设计文档
- 适用范围：`apps/desktop-macos-native`

## 背景

当前原生桌面端 `apps/desktop-macos-native/FluxDeckNative` 已成为桌面交付主线，但还没有任何本地化基础设施：

- 未使用 `NSLocalizedString`
- 未使用 `String(localized:)`
- 未配置 `Localizable.strings` 或 `Localizable.xcstrings`
- 未提供语言偏好设置，也没有根级 `Locale` 注入

同时，用户可见文案并不只存在于 SwiftUI 视图层，还分散在：

- 导航枚举：`AppNavigation.swift`
- 派生模型：`SettingsModels.swift`、`OverviewModels.swift`、`ResourceWorkspaceModels.swift`
- 网络与协议说明：`AdminApiClient.swift`
- 根视图状态编排：`ContentView.swift`

这意味着本次工作不能只做 `Text("...")` 替换，而需要建立一套可扩展、可测试、可持续迁移的多语言框架。

## 已确认产品决策

- 第一阶段目标不是“只做中英硬编码切换”，而是搭建可扩展多语言框架。
- 第一版需要同时支持：
  - 跟随系统语言
  - 应用内手动覆盖语言
- 第一阶段至少提供：
  - `system`
  - `en`
  - `zh-Hans`
- 后续应能平滑扩展到：
  - `zh-Hant`
  - `ja`
  - `ko`
- 语言切换应立即生效，不要求重启应用。

## 目标

1. 为原生端建立长期可扩展的本地化基础设施。
2. 支持系统语言自动选择与设置页手动覆盖。
3. 降低后续新增语言与新增页面时的维护成本。
4. 让测试更多断言语义与数据，而不是脆弱地绑定英文展示文案。
5. 明确“哪些内容应翻译，哪些内容必须保留原样”的边界。

## 非目标

- 本次不修改暂停中的 `apps/desktop/` Web 桌面端实现。
- 本次不尝试把所有上游返回错误原文机器翻译成多语言。
- 本次不引入第三方跨平台 i18n 框架。
- 本次不重构后端 Admin API 契约。
- 本次不顺带做视觉 redesign。

## 方案对比

### 方案 A：Apple 原生本地化主路 + 轻量语言偏好层（推荐）

做法：

- 使用 `Localizable.xcstrings` 管理字符串资源
- 在应用根部注入 `Locale`
- 使用 `@AppStorage` 持久化语言偏好
- 通过稳定 key 暴露导航、按钮、提示、空态、状态文本
- 使用轻量 helper 处理模型层与格式化场景

优点：

- 顺应 SwiftUI / Xcode 工具链，后续维护成本最低
- 支持字符串插值、复数与预览场景
- 后续增加语言只需扩资源，不必重造框架
- 与 macOS 原生生态一致，利于长期交付

缺点：

- 首轮需要清理若干“模型层直接拼英文”的现有代码
- 测试需要从断言英文切换到断言语义

### 方案 B：自研 `I18nStore + JSON/Plist` 字典

优点：

- 切换逻辑完全自控
- 对前端同学理解门槛低

缺点：

- 重复造轮子
- 插值、复数、格式化与预览支持较弱
- 后续维护会偏离 Apple 平台最佳实践

### 方案 C：先加 `L10n.tr("key")` 包装器，后续再演进

优点：

- 改造上手快

缺点：

- 只是隐藏硬编码，没有真正理顺文案归属
- 对模型层、测试和语言切换机制帮助有限

## 推荐方案

采用 **方案 A**，必要时借用少量 **方案 C** 的过渡技巧：

- 主资源层使用 `Localizable.xcstrings`
- 语言选择与持久化放在应用状态层
- 需要格式化的展示文本使用本地化 key + 参数，而不是在模型层直接拼完整英文句子

## 架构设计

### 1. 语言状态层

新增 `AppLanguage`：

- `system`
- `english`
- `simplifiedChinese`

职责：

- 表达用户选择的语言偏好
- 提供 `Locale` 映射
- 提供设置页展示标签 key
- 预留未来语言扩展位

持久化：

- 使用 `@AppStorage("fluxdeck.native.language_preference")`

解析规则：

- `system`：跟随系统语言
- 非 `system`：强制注入对应 `Locale`

### 2. 根级环境注入

在 `FluxDeckNativeApp` 根节点注入：

- `ContentView()`
- `.environment(\.locale, resolvedLocale)`

效果：

- 侧栏、工具栏、sheet、对话框、空态和详情页一并响应语言切换
- 不要求用户重启应用

### 3. 资源组织

新增本地化资源目录，推荐使用：

- `apps/desktop-macos-native/FluxDeckNative/Resources/Localizable.xcstrings`

key 组织规则：

- `common.*`：通用按钮、状态、布尔值、空值
- `nav.*`：导航与分组名称
- `settings.*`：设置页文案
- `overview.*`：概览页文案
- `traffic.*`：流量监控页文案
- `logs.*`：日志页文案
- `providers.*` / `gateways.*`：资源页文案
- `topology.*`：拓扑与路由图页文案
- `error.*`：用户可见错误摘要

### 4. 文案归属规则

#### 应翻译

- 页面标题
- 卡片标题
- 按钮文本
- 空态与加载态
- 诊断提示与用户操作说明
- 状态标签（如 `Connected`、`Syncing`、`Ready`）
- 计数类描述（如 `1 model` / `2 models`）

#### 不翻译

- `provider id`
- `gateway id`
- `model name`
- `host:port`
- API 原始错误 payload
- 上游厂商或协议名称中具有标识语义的字段值

#### 条件翻译

- 用户可见错误摘要：翻译
- 原始错误详情：保留原样，放在诊断区

### 5. 代码层改造原则

#### 导航层

`SidebarSection` 与 `AppMode` 不再把显示文案塞进 `rawValue`。

改造方向：

- `rawValue` / 标识只保留稳定身份用途
- 新增 `titleKey` / `groupTitleKey`
- 视图层用 key 渲染本地化标题

这样可以避免：

- 身份值与展示文本耦合
- 切换语言时任务 key / 选择状态被误伤

#### 视图模型层

`SettingsModels.swift`、`OverviewModels.swift`、`ResourceWorkspaceModels.swift` 等文件应优先返回：

- 原始值
- 状态枚举
- 数量
- 需要展示的 key 或格式化参数

尽量不直接返回完整英文句子。

#### 网络层

`AdminApiClient.swift` 中的协议说明、用户可见错误摘要和表单说明文案应逐步迁移为：

- 可本地化 key
- 或更靠近视图层的展示语义

网络层保留：

- DTO
- 解码
- 原始错误信息

避免继续把“用户展示文案”和“传输层逻辑”混在一起。

### 6. 设置页设计

在 `Settings` 页增加语言设置区块：

- `Language`
- 选项：
  - `Follow System`
  - `English`
  - `简体中文`

行为：

- 选择后立即更新 `AppStorage`
- 根视图立即刷新 `Locale`
- 可展示一条轻量说明：当前显示语言与系统语言关系

### 7. 测试策略

测试重心从“英文结果”迁移到“语义正确”：

- `AppLanguage` 的偏好解析与 `Locale` 映射
- 导航 key 映射完整性
- 语言设置持久化行为
- 模型层返回的数量、状态、标识正确
- 需要时对少量本地化 helper 做中英文快照断言

避免继续大面积依赖：

- `XCTAssertEqual(..., "2 models")`
- `XCTAssertEqual(..., "Last refresh 19:14:53")`

因为这些断言在多语言场景下会天然变脆。

## 建议迁移顺序

### 第一阶段：搭基础设施

- 新增 `AppLanguage`
- 新增 `Localizable.xcstrings`
- 根级注入 `Locale`
- 设置页加入语言覆盖能力

### 第二阶段：收敛导航与通用框架文案

- `AppNavigation.swift`
- `AppShellView.swift`
- `TopModeBar.swift`
- 常用状态 pill / toolbar 文案

### 第三阶段：清理模型层拼文案

- `SettingsModels.swift`
- `OverviewModels.swift`
- `ResourceWorkspaceModels.swift`
- 其余资源统计模型

### 第四阶段：覆盖复杂页面

- `TrafficAnalyticsView.swift`
- `LogsWorkbenchView.swift`
- `TopologyCanvasView.swift`
- `ProviderListView.swift`
- `GatewayListView.swift`

## 风险与约束

### 1. `ContentView` 过大

`ContentView.swift` 已承担较多页面状态与数据编排；若直接把全部本地化切换逻辑继续塞入其中，会放大维护压力。

因此建议：

- 语言偏好定义与 locale 解析放到独立文件
- `ContentView` 仅消费结果

### 2. 现有测试绑定英文

原生端测试中已有多处直接断言英文字符串，首轮接入 i18n 时会出现成片失败。

应优先：

- 把脆弱断言改成语义断言
- 必要时新增 helper 单测承接文案验证

### 3. 文案混层

当前一部分用户可见文案位于网络层与模型层，如果不先设边界，后续翻译 key 会继续散落。

### 4. 展示文案与稳定 key 混用

对于 `Topology`、`Traffic` 这类带聚合与排序的页面，不能把本地化后的展示值直接作为：

- 聚合 bucket key
- 比较 / 排序身份值
- hover payload 的稳定字段

应始终区分：

- 稳定语义 key：例如 `other`、`unknown`
- 展示标题：例如 `Other`、`其他`

否则会出现 locale 切换后行为不稳定、真实模型名与聚合桶冲突、以及页面局部继续回退系统语言的问题。

## 验收标准

满足以下条件即可认为第一阶段方案完成：

1. 应用支持系统语言与手动覆盖。
2. 至少具备 `en` 与 `zh-Hans` 两套资源。
3. 导航、设置页、通用框架文案能随语言实时切换。
4. 模型层不再继续新增英文句子拼接。
5. 现有测试已从英文绑定迁移到语义断言优先。
6. 文档与进度记录同步更新。

## 结论

本次原生端多语言支持应采用 **Apple 原生本地化资源 + 根级 Locale 注入 + AppStorage 语言偏好** 的组合方案。这样既能满足当前“系统语言 + 手动覆盖”的产品要求，也能为后续扩展更多语言保留最自然、最稳健的工程路径。
