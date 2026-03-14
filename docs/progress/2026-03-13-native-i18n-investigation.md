# 2026-03-13 原生端多语言支持调研记录

## 本次目标

- 调研 `apps/desktop-macos-native` 当前多语言基础状况
- 给出适合原生端主线的多语言方案
- 形成可落地的设计文档与实施计划

## 调研范围

- 应用入口：`FluxDeckNativeApp.swift`
- 根视图状态编排：`ContentView.swift`
- 导航与壳层：`AppNavigation.swift`、`AppShellView.swift`、`SidebarView.swift`、`TopModeBar.swift`
- 关键页面：`SettingsPanelView.swift`、`TrafficAnalyticsView.swift`、`LogsWorkbenchView.swift`
- 派生模型：`SettingsModels.swift`、`OverviewModels.swift`、`ResourceWorkspaceModels.swift`
- 网络层：`AdminApiClient.swift`
- 原生测试：`FluxDeckNativeTests.swift`

## 主要发现

- 当前原生端没有现成本地化设施，未使用 `NSLocalizedString`、`String(localized:)` 或字符串目录资源。
- 用户可见文案不只在 SwiftUI 视图层，还分散在导航枚举、模型层与网络层。
- `ContentView.swift` 负责大量状态与页面编排，若把语言逻辑继续堆进去，会进一步放大复杂度。
- `AppNavigation.swift` 当前把展示文案放在枚举 `rawValue`，会阻碍多语言扩展。
- `FluxDeckNativeTests.swift` 已存在多处直接断言英文展示字符串，后续必须迁移为语义断言优先。

## 已确认方案

- 采用 Apple 原生本地化主路：`Localizable.xcstrings`
- 采用根级 `Locale` 注入
- 使用 `@AppStorage` 持久化语言偏好
- 第一阶段支持：
  - 跟随系统
  - English
  - 简体中文
- 设置页提供手动语言覆盖并即时生效
- API 原始错误详情、ID、模型名等标识性内容保持原样，不做翻译

## 输出物

- 设计文档：`docs/plans/active/2026-03-13-native-i18n-design.md`
- 实施计划：`docs/plans/active/2026-03-13-native-i18n.md`

## 推荐后续顺序

1. 先建 `AppLanguage` 与 `Localizable.xcstrings`
2. 再接设置页语言覆盖
3. 再迁移导航与壳层文案
4. 再清理模型层英文拼接
5. 最后覆盖复杂页面与测试

## 本次未动

- 未修改原生端实现代码
- 未执行原生测试，因为当前阶段仅完成方案调研与文档落地

## 备注

- 当前工作区还存在与本次任务无关的未跟踪文档文件，后续执行实现计划前应注意与本次改动分开管理。

## 首批实现进展（worktree: `feat/native-i18n`）

### 已落地

- 新增 `AppLanguage`，支持 `system` / `en` / `zh-Hans` 与 `Locale` 映射
- 在 `FluxDeckNativeApp` 根部接入 `@AppStorage("fluxdeck.native.language_preference")` 与 `.environment(\.locale, resolvedLocale)`
- 新增 `Localization/L10n.swift` 作为轻量本地化 helper
- 新增 `Resources/Localizable.xcstrings`，先收录语言设置与 model count 相关 key
- 设置页新增语言选项模型与 UI 绑定，支持手动切换语言偏好
- 原生测试新增首批 3 条 TDD 用例

### 本批验证

- 命令：`xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -only-testing:FluxDeckNativeTests/testAppLanguageMapsStorageAndLocaleIdentifiers -only-testing:FluxDeckNativeTests/testLocalizationHelperResolvesEnglishAndChineseStrings -only-testing:FluxDeckNativeTests/testSettingsPanelModelExposesLanguageOptions -quiet`
- 结果：通过
- 告警：存在 `Using the first of multiple matching destinations`，但不影响结果

## 第二批实现进展（Task 4：导航与壳层文案本地化）

### 已落地

- `AppNavigation.swift` 将 `SidebarSection`、`AppMode` 的 `rawValue` 切换为稳定标识，并补充 `titleKey`
- `SidebarGroup` 改为稳定 `id + titleKey`，默认分组不再依赖展示文案作为身份
- `SidebarView.swift` 改为通过 `L10n` + `Locale` 渲染分组标题、导航标题与壳层副标题
- `TopModeBar.swift` / `AppShellView.swift` 接入工作区、刷新、连接状态、运行网关数、告警数等本地化文案
- `ContentView.swift` 透传当前 `locale`，使顶部标题与壳层状态随语言切换即时生效
- `Localizable.xcstrings` 扩充 `sidebar.*`、`shell.*` 相关 key，并新增 Task 4 的导航/壳层测试

### 本批验证

- 命令：`xcodebuild test -project .worktrees/native-i18n/apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`
- 结果：通过
- 新增通过用例：
  - `testSidebarSectionUsesStableIdentifiersAndLocalizedTitleKeys`
  - `testSidebarGroupsAndAppModeExposeLocalizedTitleKeys`
  - `testShellCopyUsesLocalizedKeys`

### 下一步

- 进入 Task 5：清理 `OverviewModels.swift`、`SettingsModels.swift` 等模型层英文拼接
- 继续把“文案语义”与“稳定身份”解耦，避免模型层再把英文字符串当作状态值或 identity

## 第三批实现进展（Task 5：模型层英文拼接清理）

### 已落地

- `OverviewDashboardModel` 将连接数、网关数、延迟与网关健康状态改为稳定数值 / 枚举语义，不再在模型层拼英文文案
- `SettingsPanelModel` 将设置分区改为 `titleKey` / `descriptionKey`，并以 `SettingsPanelStatus` 表达状态语义
- `ProviderWorkspaceCard` / `GatewayWorkspaceCard` 改为暴露 `modelCount`、`isEnabled`、`runtimeState`、`autoStartEnabled` 等稳定字段
- `ShellStatusSummary` 改为暴露 `connectionState`、`runningGatewayCount`、`alertCount`，壳层状态文案统一通过 `L10n` 在视图层生成
- `L10n.swift` 与 `Localizable.xcstrings` 扩充设置状态、资源状态、毫秒格式、概览网关健康等 key
- 消费方视图已切到新语义字段，避免继续依赖英文字符串判断状态

### 本批验证

- 命令：`xcodebuild test -project .worktrees/native-i18n/apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -derivedDataPath /tmp/FluxDeckNativeDD-task5 -quiet`
- 结果：通过
- 说明：沙箱内测试运行器会被 `testmanagerd` 限制；最终验证在提权环境下完成

### 下一步

- 进入 Task 6：清理复杂页面与网络层用户可见文案边界
- 重点处理 `TrafficAnalyticsView`、`LogsWorkbenchView`、`ProviderListView`、`GatewayListView` 等页面中的按钮、空态、错误摘要和提示文案

## 第四批实现进展（2026-03-14：现有改动收口与验证补齐）

### 已修复

- 修复 `TopologyCanvasView.swift` 中本地化接线错误：
  - `emptyStateKey` 被误当成不存在的 `emptyStateText`
  - `metric` / `flow` picker 的本地化 helper 调用被写反
- 对齐 `FluxDeckNativeTests.swift` 中已迁移接口的断言，改为验证 `summaryTitleKey` / `mixTitleKey` / `emptyStateKey`
- 补齐 `Localizable.xcstrings` 中缺失的 23 个 key，覆盖：
  - `resource.provider.toggle.*`
  - `resource.gateway.action.*`
  - `topology.*`
  - `admin.error.*`
  - `admin.gateway.notice.*`
- 使 `AdminApiClient.swift` 中网关 notice / Admin API 错误摘要真正走字符串目录资源，而不是在缺 key 时回退成原始 key

### 根因结论

- 本轮主要阻塞不是业务逻辑，而是字符串目录资源未补全。
- `L10n.swift` 已声明多个 key，但 `Localizable.xcstrings` 缺少对应条目，导致全量测试时返回原始 key 字面量，例如：
  - `admin.error.request_failed_http`
  - `topology.metric.tokens`
  - `resource.gateway.action.start`

### 本批验证

- 命令：`xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`
- 结果：通过，72/72 用例通过
- 说明：
  - 初次全量测试暴露了编译错误与字符串目录缺项
  - 修复后重新执行全量测试，所有原生端测试通过

### 当前剩余范围

- 复杂页面仍存在较多未迁移的用户可见硬编码文案，主要集中在：
  - `ContentView.swift`
  - `ProviderListView.swift`
  - `GatewayListView.swift`
  - `LogsWorkbenchView.swift`
  - `TrafficAnalyticsView.swift`
- 这些属于 Task 6 的后续迁移范围，不影响当前分支已落地的语言偏好、导航壳层、模型层语义和现有测试闭环

## 第五批实现进展（2026-03-14：Task 6 第一轮页面文案迁移）

### 已落地

- `ProviderListView.swift`
  - 页面标题、空态、按钮、字段标签、提交态切换到 `L10n` key
- `GatewayListView.swift`
  - 页面标题、空态、按钮、字段标签、提交态切换到 `L10n` key
  - 运行状态胶囊改为通过本地化资源渲染，而不是直接显示枚举 `rawValue`
- `LogsWorkbenchView.swift`
  - 过滤条、计数标签、加载更多、空态、分区标题切换到 `L10n`
  - `LogStreamCardModel` 的执行/诊断明细标签改为按 `locale` 生成
  - `Streaming / Non-stream` 改为可本地化文案，并同步修正 badge tint 判定
- `TopologyCanvasView.swift` / `TopologyModels.swift`
  - 页面标题、副标题、控制条标签切换到 `L10n`
  - 拓扑列标题从直接文案改为 `titleKey`，在视图层按当前 `locale` 渲染
- `Localizable.xcstrings`
  - 新增 Provider / Gateway / Logs / Topology 第一批页面级 key
- `FluxDeckNativeTests.swift`
  - 新增 `testWorkbenchPageCopyResolvesForEnglishAndChinese`
  - `TopologyColumn` 测试构造更新为 `titleKey`

### 本批验证

- 命令：`xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`
- 结果：通过，73/73 用例通过

### 当前剩余范围

- 本轮已清理四个相对独立的页面文件，剩余最大迁移面仍在：
  - `ContentView.swift`
  - `TrafficAnalyticsView.swift`
- 这两个文件仍包含大量表单说明、空态、操作按钮和诊断说明文案，适合作为下一轮 Task 6 的主战场


## 第五批实现进展（2026-03-14：Task 6 页面框架文案继续本地化）

### 已落地

- 修复 `Localizable.xcstrings` 的写回方式：将字符串目录统一规范化为稳定 JSON 后再增量追加，避免新增 key 被 Xcode 编译阶段静默丢弃。
- `ProviderListView.swift` / `GatewayListView.swift` 接入当前 `locale`，将页面标题、新建按钮、加载态、空态、资源标签和提交中提示切到字符串目录资源。
- `GatewayListView.swift` 的运行态动作按钮改为复用 `L10n.gatewayRuntimeAction(...)`，与 Task 6 针对性测试保持一致。
- `TrafficAnalyticsView.swift` 接入当前 `locale`，将监控页标题、副标题、刷新按钮、趋势区标题、路由概览、告警区、空态与 breakdown 空态切到字符串目录资源。
- `LogsWorkbenchView.swift` 接入当前 `locale`，将日志筛选、请求流标题、加载更多、清空筛选、详情 section 标题与用量 JSON 标题切到字符串目录资源。
- `TopologyCanvasView.swift` 将页面标题、副标题与 `Metric / Flow / Highlight` 控制组标签切到字符串目录资源。
- `Localizable.xcstrings` 新增 Provider / Gateway / Traffic / Logs / Topology 页面框架层 key，并确认已进入构建产物。

### 本批验证

- 命令：`xcodebuild test -project .worktrees/native-i18n/apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -derivedDataPath /tmp/FluxDeckNativeDD-task6-ui -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTopologyControlsUseStableIdentifiersAndLocalizedTitleKeys -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTopologyCanvasScreenModelExposesEmptyState -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testProviderAndGatewayActionCopyUsesStableState -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testGatewayUpdateNoticeTextPrefersServerNoticeAndFallsBackLocally -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testGatewayDeleteNoticeTextPrefersServerNoticeAndFallsBackLocally -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testBuildsReadableAdminApiErrorMessageForReferencedProviderConflict -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testAdminApiErrorMessagePreservesPlainTextAndLocalizesHttpFallback -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testLogStreamCardModelPrefersErrorSummaryForFailedLog -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testLogStreamCardModelKeepsRouteModelLatencyAndTimeForSuccessfulLog -quiet`
- 结果：通过，Task 6 当前关键回归全部通过。
- 全量验证：`xcodebuild test -project .worktrees/native-i18n/apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -derivedDataPath /tmp/FluxDeckNativeDD-task6-full2 -quiet` 通过。
- 产物检查：在 `/tmp/FluxDeckNativeDD-task6-ui/Build/Products/Debug/FluxDeckNative.app` 中确认 `provider.page.title`、`gateway.page.title`、`traffic.page.title`、`logs.filters.title`、`topology.page.title` 已编译到 `en.lproj/Localizable.strings` 与 `zh-Hans.lproj/Localizable.strings`。

## 第六批实现进展（2026-03-14：review 收口与稳定 key 拆分）

### 已落地

- `SettingsPanelView.swift`
  - 将设置页主操作按钮 `Apply / Reset` 与诊断标签 `Current Endpoint / Busy / Error / Yes / No` 全部切到字符串目录资源。
- `OverviewModels.swift`
  - 将空网关兜底文案 `"No gateway"` 改为本地化资源，并在 `ContentView.swift` 调用处显式透传当前 `locale`。
- `LogsWorkbenchView.swift`
  - 将紧凑 token 摘要从硬编码 `Tok / in / out / total / c` 改为本地化格式化输出，中文环境下改为 `令牌 / 入 / 出 / 总 / 缓`。
- `AdminApiClient.swift` + `ContentView.swift`
  - 将 Provider/Gateway 协议说明 subtitle 从硬编码英文迁移到字符串目录资源，并在协议 picker 选项构造时显式按当前 `locale` 渲染。
- `TrafficConnectionsModels.swift`
  - 为 token trend 的 `Other` 聚合桶引入稳定内部 key `__other__`，避免直接使用本地化文案做聚合身份值。
  - 当真实模型名与本地化后的 `Other` 标签冲突时，使用独立展示名 `其他（模型）` / `Other (model)` 规避碰撞。
- `TopologyModels.swift` / `TopologyCanvasView.swift`
  - `TopologyGraph.make(...)` 与 `TopologyCanvasScreenModel.make(...)` 均接入显式 `locale`。
  - Topology 的热点路径、model mix、node summary、hover tooltip、`Total` 汇总标签、`UNKNOWN PROVIDER` 兜底说明全部改为本地化输出。
  - `TopologyCanvasSegmentModel` 增加稳定布尔字段 `isTotal`，避免再用展示标题 `"Total"` 参与行为判断。
- `Localizable.xcstrings`
  - 新增 settings diagnostics、common yes/no、overview no-gateway、logs compact summary、provider kind subtitles、topology short metrics / tooltip / total / unknown-provider、traffic other-model 等 key。
- `FluxDeckNativeTests.swift`
  - 新增回归测试覆盖：
    - 设置页/概览页新增 key 可解析
    - 协议 subtitle 中英文本地化
    - 日志紧凑摘要中文格式
    - Traffic `Other` 聚合桶稳定 key 与冲突展示名
    - Topology 显式 locale 渲染

## 第七批实现进展（2026-03-14：rebase 本地 main 后补齐 failover / health i18n）

### 背景

- 本地 `main` 相对 `feat/native-i18n` 额外前进了 6 个提交，新增了多 Provider failover、Provider health 探测与 Gateway route target 相关 UI / 数据结构。
- `git rebase main` 时，冲突集中出现在：
  - `ContentView.swift`
  - `ProviderListView.swift`
  - `GatewayListView.swift`
  - `ResourceWorkspaceModels.swift`
  - `FluxDeckNativeTests.swift`

### 本轮处理

- 保留本地 `main` 引入的 failover / health 能力，同时继续沿用原生字符串目录与 `L10n` helper 体系。
- 将新增用户可见文案迁移到字符串目录：
  - Provider 页新增 `Health`、`Last Failure`、`Probe`
  - Gateway 页新增 `Active`、`Routes`、`Health`、`Idle`
  - Gateway form 新增 route target 预览 / 编辑文案
  - Provider probe notice 改为本地化模板
  - Provider / Gateway health 状态统一走本地化 key，而不是直接显示原始状态值
- `ResourceWorkspaceModels.swift` 保留稳定数据形状：
  - `ProviderWorkspaceCard` 暴露 `modelCount`、`isEnabled`、`healthStatus`、`healthDetailText`
  - `GatewayWorkspaceCard` 暴露 `runtimeState`、`activeProviderText`、`routeTargets`、`healthSummary`、`autoStartEnabled`
  - 视图层再通过 `L10n` 生成最终展示文案，避免把新的英文短语继续固化到模型层

### 本轮验证

- `jq empty apps/desktop-macos-native/FluxDeckNative/Resources/Localizable.xcstrings`
  - 结果：通过
- `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -derivedDataPath /tmp/FluxDeckNativeDD-rebase-i18n-20260314 -quiet`
  - 结果：通过，原生端全量测试通过

### 当前状态

- rebase 冲突内容已经合并并通过测试验证。
- `feat/native-i18n` 已成功 rebase 到本地 `main`。
- 当前 worktree 仅保留本轮新增的计划 / 进展文档更新，等待提交收口。

### 本批验证

- 命令：`jq empty apps/desktop-macos-native/FluxDeckNative/Resources/Localizable.xcstrings`
- 结果：通过
- 命令：`xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -derivedDataPath /tmp/FluxDeckNativeDD-review-fixes-full3 -quiet`
- 结果：通过，全量 `FluxDeckNativeTests` 通过
- 备注：构建阶段仍有 `XCTest` 针对 macOS 13/14 的链接告警，但不影响测试结果

### 当前剩余范围

- `LogsWorkbenchView.swift` 仍有少量诊断 badge / token 缩写位于 `LogStreamCardModel` 里，例如 `Tok`、`in/out/c/total`、`Streaming`、`Non-stream`。
- `TrafficAnalyticsView.swift` 图表内部仍有少量缩写型辅助文案未迁移，例如 `err`、`Total Tokens` 与 bucket 级 token 汇总缩写。
- `TopologyCanvasView.swift` 仍有少量 tooltip / summary 缩写未迁移，例如 `tok`、`req`、`cached`、`err`、`Total`、`unknown`。
- 上述残留不影响当前语言切换、关键页面框架层文案与网络层错误摘要回归；可作为 Task 6 收尾批次继续清理。

## 第六批实现进展（2026-03-14：Task 6 收口与验证补齐）

### 已落地

- `ContentView.swift`
  - Provider / Gateway 删除确认弹窗切到字符串目录资源。
  - Route Map 占位页、壳层重试按钮、刷新失败可访问性描述和 Admin URL 校验错误切到本地化 key。
  - Provider 删除 notice 统一走本地化资源。
  - 将日志筛选“全部”选项改为稳定 sentinel，并在日志页面按当前 `locale` 渲染展示文案，避免把展示文本当筛选身份。
  - 清理未再使用的旧版 `OverviewView` / `LogsPanelView` / `SettingsView` 死代码，缩小 `ContentView.swift` 的遗留面。
- `OverviewDashboardView.swift`
  - 运行状态、网络状态、流量概览、最近请求和加载 / 空态文案全部切到字符串目录资源。
- `TrafficAnalyticsView.swift` / `TrafficConnectionsModels.swift`
  - 监控页图表 tooltip、Total Tokens 图例、Top Model Share / Peak Bucket Errors 等趋势摘要切到本地化资源。
  - KPI 标题、补充明细、告警标题与详情、`No gateway / No provider / No model / Other` 回退语义全部按 `locale` 生成。
  - `TrafficAnalyticsModel` 新增 `locale` 语义，避免模型层继续固化英文输出。
- `ProviderFormSheet` / `GatewayFormSheet`
  - 表单标题、分区标题、字段标题、说明文案、按钮、运行态摘要、校验错误、fallback 选项提示全部切到字符串目录资源。
  - `GatewayFormSupport` 的 snapshot / fallback 选项改为可按 `locale` 生成。
- `Localizable.xcstrings`
  - 新增 Content / Overview / Provider Form / Gateway Form / Traffic 收尾批次所需 key，覆盖中英文资源。
- `FluxDeckNativeTests.swift`
  - 新增 `testContentAndTrafficCopyResolvesForEnglishAndChinese`
  - 新增 `testGatewayFormSupportLocalizesFallbackOptionsAndSnapshotCopy`
  - 新增 `testTrafficTrendRenderableLinesLocalizePrimaryTotalTitle`
  - 调整相关测试为显式传入 `Locale(identifier: "en")`，避免依赖测试环境默认语言。

### 本批验证

- 先执行 `jq empty apps/desktop-macos-native/FluxDeckNative/Resources/Localizable.xcstrings`
  - 结果：通过，字符串目录 JSON 结构有效。
- 再执行 `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`
  - 结果：通过，原生端全量测试通过。

### 当前状态

- Task 6 针对原生端主要页面与表单的可见文案迁移已基本收口。
- 当前 worktree 仍然是脏的，但内容集中在这条 `feat/native-i18n` 实现线与对应文档，不存在本轮新增的未验证改动。

## 第七批实现进展（2026-03-14：rebase 本地 main 后继续补齐 i18n）

### 背景

- 本地 `main` 在 `feat/native-i18n` 之外新增了 6 个提交，主要带入 failover、provider health、gateway route targets 和 provider probe 能力。
- 对 `feat/native-i18n` 执行 `git rebase --autostash main` 后，冲突集中在原生端资源页、表单页和测试。

### 已落地

- `ContentView.swift`
  - 保留 `main` 新增的 provider health 拉取与 provider probe 操作。
  - probe 成功 notice 改为 `L10n` 格式化输出，并按当前 `locale` 本地化健康状态。
  - Routing Targets 预览区与编辑区新增的标题、按钮、说明文案全部迁移到字符串目录。
- `ProviderListView.swift`
  - 为 `Health`、`Last Failure`、`Probe` 补齐本地化 key。
  - provider health 状态改为基于稳定状态值再按 locale 渲染。
- `GatewayListView.swift`
  - 为 `Active`、`Routes`、`Health` 补齐本地化 key。
  - route chain 与 gateway health summary 改为按 locale 生成展示文案。
- `ResourceWorkspaceModels.swift`
  - provider/gateway 新增的 health、route target、health summary 数据以稳定字段保留在模型层。
  - 不再在模型层拼英文展示字符串。
  - provider 若缺失 health 数据，回退为 `unknown`，避免误报 `healthy`。
- `L10n.swift` / `Localizable.xcstrings`
  - 新增 provider/gateway failover 相关 key。
  - 新增 health 状态、route target 编辑区文案、gateway health summary、probe notice 的中英文资源。
- `FluxDeckNativeTests.swift`
  - 资源模型测试更新为断言稳定数据形状，覆盖 route targets / health summary / provider health。
  - 保留本地 `main` 带入的 provider health、route targets 编解码与 failover 操作测试。

### 本批验证

- 命令：`jq empty /Users/jassy/Documents/glm/FluxDeck/.worktrees/native-i18n/apps/desktop-macos-native/FluxDeckNative/Resources/Localizable.xcstrings`
- 结果：通过
- 命令：`xcodebuild test -project /Users/jassy/Documents/glm/FluxDeck/.worktrees/native-i18n/apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -derivedDataPath /tmp/FluxDeckNativeDD-rebase-i18n-20260314 -quiet`
- 结果：通过，全量 `FluxDeckNativeTests` 通过

### 当前状态

- rebase 冲突已经在代码层全部解决。
- 待执行 `git add ...` 标记冲突已解决并 `git rebase --continue`。
- 当前 worktree 中的 i18n 补漏、测试和文档已同步到位。
