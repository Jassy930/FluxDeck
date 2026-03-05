# FluxDeck macOS 原生管理台增强设计（阶段二）

## 1. 背景

现有 `apps/desktop-macos-native` 已具备 `Providers / Gateways / Logs / Settings` 基础结构，但仍缺少更强的运维工作流闭环：
- `Overview` 缺少“最近日志 -> Logs”的下钻入口。
- `Settings` 仅只读展示 Admin 地址，无法在原生壳内切换连接目标。
- 地址输入缺少统一校验与归一化策略。

## 2. 设计输入（ui-ux-pro-max）

- 查询：`macos native admin operations dashboard swiftui`
- 输出风格：`Data-Dense Dashboard`
- 核心建议：
  - 关键操作在首屏可见（Above fold CTA）
  - 使用明确 loading/error recovery
  - SwiftUI 使用 `List`、`ProgressView`、`@FocusState` 做可用性保障

## 3. 本轮范围

### 3.1 Overview 增强
- 新增“Recent Logs”模块（最多 10 条，按时间倒序）。
- 每行支持点击下钻到 `Logs`，并自动带入 `gateway/provider` 过滤条件。
- 提供 `Open Logs` 快捷入口，直接跳转日志页并清空过滤。

### 3.2 Settings 可操作化
- 增加 Admin 地址输入框与焦点管理（`@FocusState`）。
- 增加 `Apply & Refresh` 按钮：提交地址后立即触发全量刷新。
- 增加 `Reset Default` 按钮：回退默认地址 `http://127.0.0.1:7777`。
- 错误提示就近展示并带可访问性标签。

### 3.3 网络层规则
- 新增 `normalizedAdminBaseURL`：
  - 自动补全无协议输入（如 `127.0.0.1:7777` -> `http://127.0.0.1:7777`）
  - 仅允许 `http/https`
  - 非法地址返回 `nil`
- 新增 `recentLogs`，统一日志排序与截断逻辑，避免视图层重复实现。

## 4. 测试策略

- 新增单元测试：
  - `testRecentLogsReturnsLatestTenEntriesInDescendingOrder`
  - `testNormalizedAdminBaseURL`
- 验证路径：
  - 先红：新增测试时构建失败（函数未定义）
  - 再绿：补实现后 `xcodebuild test` 通过

## 5. 交付文件

- `apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift`
- `apps/desktop-macos-native/FluxDeckNative/Networking/AdminApiClient.swift`
- `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`
- `design-system/fluxdeck-native/MASTER.md`
- `design-system/fluxdeck-native/pages/operations-console.md`

## 6. Provider Panel 配置操作扩展（增量）

### 6.1 用户目标
- 在 Provider 面板内完成配置修改，而非只能新建与查看。
- 支持快速启用/停用 Provider，减少跳转成本。

### 6.2 交互方案
- 每个 Provider 行提供两个操作：
  - `Configure`：打开配置弹窗，编辑 `name/kind/base_url/api_key/models/enabled`
  - `Enable/Disable`：一键切换启用状态
- `id` 作为主键在编辑中只读展示，不允许修改。

### 6.3 契约补齐
- 新增 `PUT /admin/providers/{id}`：
  - 请求体：`name/kind/base_url/api_key/models/enabled`
  - 返回：更新后的 Provider
  - 不存在时返回 `404`

### 6.4 验证
- Rust：
  - `provider_service_test` 覆盖更新行为
  - `admin_api_test` 覆盖更新成功与不存在 `404`
- Swift：
  - `UpdateProviderInput` 编码测试
  - Provider 解码增加 `api_key/models` 字段校验

## 7. Provider 表单视觉优化（增量）

### 7.1 目标
- 在不改变创建/编辑行为的前提下，提高 Provider 表单的视觉层级、输入可读性与操作清晰度。

### 7.2 设计决策
- 单一复用表单保持不变，优化其结构为：
  - 顶部说明区（当前模式 + 用途）
  - `Identity`：ID/Name/Kind
  - `Connection`：Base URL + API Key（显隐）
  - `Models`：多行输入 + 分隔规则提示
  - `Runtime`：启停开关 + 预览摘要
- 保留强约束：
  - 创建模式必须填写 `id`
  - `base_url` 必须是合法 URL
  - `models` 至少 1 项
