# FluxDeck macOS 原生界面设计（SplitView）

## 1. 目标与边界

### 目标
- 在 macOS 原生壳中提供可用的运维管理台：`Providers / Gateways / Logs`。
- 与 Web 端保持同一 Admin API 契约，避免双端语义漂移。
- 优先“可操作 + 可观测 + 可恢复”，而不是装饰性视觉。

### 边界
- 原生端不复制后端业务逻辑；只做 API 调用、状态展示与用户操作编排。
- 当前迭代聚焦单窗口管理台，不引入多窗口复杂度。

## 2. 设计输入（ui-ux-pro-max）

- 风格基线：`Data-Dense Dashboard`（高信息密度、清晰状态层级）。
- 视觉方向：专业运维风格（深蓝/灰为主，绿色作为正向状态色）。
- SwiftUI 关键约束：
  - 异步加载使用 `.task`
  - 长列表使用 `List`
  - 超过 300ms 的操作必须反馈 `ProgressView`

## 3. 信息架构（NavigationSplitView）

左侧 Sidebar（一级导航）：
1. `Overview`
2. `Providers`
3. `Gateways`
4. `Logs`
5. `Settings`（仅放 Admin 地址与连接配置）

右侧 Detail（内容区）：
- 顶部工具栏：`Admin 地址`、`Refresh`、`连接状态`、`最近错误摘要`
- 主内容：按导航切换对应模块视图（列表 + 操作区）

## 4. 关键页面与交互

### Overview
- 显示 4 张 KPI 卡片：Provider 数、Gateway 数、Running Gateway 数、近 1 小时错误数。
- 显示“最近 10 条日志”预览，点击跳转 Logs 详情。

### Providers
- 左侧列表（名称、类型、启用状态），右侧详情（base_url、models、enabled）。
- 顶部 `New Provider` 打开 sheet 表单。
- 提交后流程：按钮 loading -> 成功 toast -> 局部刷新列表 -> 失败错误提示与重试。

### Gateways
- 列表字段：`name / host:port / default_provider / runtime_status / last_error`。
- 行级操作：`Start` / `Stop`，状态色规则：
  - `running` 绿色
  - `stopped` 灰色
  - `error` 红色（并显示 `last_error`）

### Logs
- 按时间倒序列表，字段：`request_id / gateway / provider / model / status / latency / created_at`。
- 支持基础筛选：按 gateway/provider/status。

## 5. 状态与可用性规范

- 每个模块统一四态：`loading / empty / error / success`。
- 错误必须可恢复：提供 `Retry`；网络失败不应阻断其他模块渲染。
- 键盘与可访问性：
  - Sidebar 支持上下切换与回车进入
  - 关键错误使用可被辅助技术感知的语义（SwiftUI `accessibilityLabel` + 明确文案）

## 6. 视觉令牌（Native 映射）

- 主色：`#0F172A`，辅助：`#1E293B`，成功：`#22C55E`，错误：系统 `red`
- 文本优先使用系统语义色（`primary/secondary`），避免固定低对比灰
- 间距：8/12/16/24；圆角：8；动效 150-220ms，支持 reduce motion

## 7. 交付分期（建议）

1. Phase A：先落 `NavigationSplitView + Overview + Providers/Gateways 只读`
2. Phase B：补齐 `Create Provider/Gateway + Start/Stop + 全局刷新`
3. Phase C：补齐 `Logs 筛选 + 错误恢复 + 快捷键（⌘R 刷新）`

