# FluxDeck macOS 原生 Traffic 统计监控设计

## 目标

将 `apps/desktop-macos-native` 中的 `Traffic` 页面从“基于最近日志的轻量分析卡片”升级为“基于真实 Admin Stats API 的原生监控工作台”，并保持与现有原生壳层、卡片、色彩和交互密度一致。

本次设计只覆盖 `Traffic` 页面，不新增独立监控页面，不改动侧边栏信息架构。

## 当前现状

- 原生端已存在 `TrafficAnalyticsView`，但数据来自 `dashboardLogs` 的本地聚合。
- 后端 `fluxd` 已提供：
  - `GET /admin/stats/overview`
  - `GET /admin/stats/trend`
- Web 端已有一套基于真实统计数据的监控页，可作为信息结构参考，但原生端需要保留 SwiftUI 原生风格，而不是照搬 Web 布局。

## 设计原则

1. `Traffic` 必须一眼看出是监控页，而不是普通详情页。
2. 页面风格必须延续原生界面的深色工作台语言：
   - 使用 `SurfaceCard`
   - 使用 `StatusPill`
   - 使用 `DesignTokens`
3. 信息优先级应为：
   - 关键指标
   - 趋势
   - 维度分布
   - 异常摘要
4. 不引入新的复杂图表依赖，趋势图用 SwiftUI 原生绘制或轻量自绘。
5. 本次支持手动刷新与时间范围切换，不强制接入自动轮询。

## 页面结构

### 1. 顶部控制条

放在 `Traffic` 页面顶部，包含：

- 页面标题：`Traffic Monitor`
- 辅助说明：说明当前展示的是网关请求流量、延迟和错误趋势
- 时间范围切换：`1h` / `6h` / `24h`
- 刷新按钮或最近刷新时间

设计要求：

- 控件风格保持轻量，不抢占内容区视觉焦点
- 时间范围切换采用与现有原生页面一致的胶囊式/分段式选择风格

### 2. KPI 指标区

第一屏展示四个核心指标：

- `Requests/min`
- `Success Rate`
- `Avg Latency`
- `Total Tokens`

每个指标都放在独立卡片中，采用与 `Overview` 同级的卡片层级。

语义规则：

- 成功率过低显示 warning / error 语义
- 延迟过高显示 warning / error 语义
- 无流量时不伪造健康结论，显示 empty / neutral 文案

### 3. 趋势区

趋势区为页面主舞台，至少包含：

- 请求量趋势
- 平均延迟趋势
- 错误数摘要

实现形式：

- 使用单卡片或双列卡片呈现
- 图形保持低噪音、可读优先
- 重点让用户快速判断趋势方向，而不是追求高保真图表系统

### 4. Breakdown 区

展示三类维度统计中的 top 项：

- 按 Gateway
- 按 Provider
- 按 Model

每一类以列表卡片显示请求量、错误量、平均延迟和 token 使用量，强调“最常用 / 最异常”的维度。

### 5. Alerts 区

如果统计数据表明存在明显异常，则在页面下方展示 `Alerts` 卡片，聚合：

- 高延迟
- 有错误请求
- 流量异常低或无流量

这里不直接替代 `Logs` 页面，而是作为监控摘要入口。

## 数据流

### 输入

`Traffic` 页面需要直接消费：

- `StatsOverview`
- `StatsTrend`

页面不再依赖 `dashboardLogs` 计算主要监控指标。

### 获取时机

- 切换到 `Traffic` 页面时加载
- 修改时间范围时重新加载
- 点击刷新时重新加载

### 错误处理

- 若 overview 或 trend 任一请求失败，页面保留外壳和已知成功数据
- 顶部或卡片内展示明确错误提示
- 不允许整页空白

## 原生端模型设计

新增两层模型：

1. `AdminApiClient` 解码模型
- `AdminStatsOverview`
- `AdminStatsTrend`
- `AdminStatsTrendPoint`
- 各类维度统计模型

2. `Traffic` 视图派生模型
- 负责把原始接口数据转换为：
  - KPI 文案
  - 告警状态
  - top gateway/provider/model
  - 图表点位

这样可以把“接口解码”和“界面展示规则”分离，避免 `View` 中塞满业务判断。

## 视觉一致性约束

- 不新增独立主题文件
- 不改变现有 `AppShellView`、`SidebarView`、`TopModeBar` 的结构
- 新增卡片样式若可复用，应优先扩展现有 UI 组件而不是在页面内内联实现
- 数字和状态色必须使用现有 token 体系，不在页面中硬编码新的主色

## 测试策略

### 单元测试

增加原生测试覆盖：

- 统计 overview JSON 解码
- 统计 trend JSON 解码
- `Traffic` 派生模型的成功率、延迟、异常判断

### 回归重点

- 现有 `Overview`、`Connections`、`Topology` 的派生模型不能被破坏
- 原生客户端在无统计数据、请求失败、维度数据为空时仍可稳定渲染

## 非目标

- 本次不做实时 websocket / streaming monitor
- 不做独立告警中心
- 不做复杂缩放图表或第三方图表库接入
- 不改造 `Overview` 成监控首页，监控主界面明确放在 `Traffic`

## 验收标准

1. `Traffic` 页面基于真实 `/admin/stats/*` 数据渲染。
2. 页面能切换 `1h / 6h / 24h` 时间范围。
3. 页面能展示 KPI、趋势、维度分布和异常摘要。
4. 页面视觉风格与其他原生界面保持一致。
5. 原生测试覆盖新增统计解码与派生逻辑。
