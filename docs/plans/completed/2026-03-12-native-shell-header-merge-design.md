# Native Shell Header Merge Design

## 背景

当前原生桌面端在工作区顶部存在两层信息栏：

- `TopModeBar`：展示 `Workspace / 当前页面`、模式切换、全局状态胶囊
- `ContentView.headerBar`：展示 `Admin URL`、最近刷新时间、连接状态、全局刷新按钮

两层都位于首屏核心区域，且都在表达“当前工作区上下文 + 同步状态 + 刷新能力”。对于 `Traffic` 这类高密度监控页，这种重复结构会挤占图表与 KPI 的可视高度。

## 目标

- 将壳层顶栏与 admin 信息栏合并成一层
- 保留全局刷新入口和关键同步信息
- 删除常态下重复的第二层信息栏，让内容区更早进入业务卡片
- 保持现有原生深色监控台风格，不引入新的视觉体系

## 方案选择

### 方案 A：合并到壳层顶栏

做法：

- 扩展 `TopModeBar`，让其同时承载：
  - 工作区标题
  - admin endpoint
  - 最近刷新时间
  - 模式切换
  - 全局状态胶囊
  - 全局刷新按钮
- `ContentView` 删除常态 `headerBar`
- `loadError` 仅在发生错误时保留独立错误条，不再常驻占位

优点：

- 真正减少一整层垂直占用
- 信息归位更清晰，所有“壳级上下文”集中在一处
- `Traffic`、`Providers`、`Gateways` 等页面都能统一受益

缺点：

- `TopModeBar` 需要新增元数据与动作入口
- 顶栏布局更紧凑，需要注意 920px 最小宽度下的可读性

### 方案 B：仅压缩内容区 header

做法：

- 保留 `TopModeBar`
- 将 `ContentView.headerBar` 压缩成一条更薄的单行条带

优点：

- 改动面较小

缺点：

- 仍然是两层顶部结构
- 只解决高度，不解决信息重复

## 决策

采用 **方案 A**。

原因：

- 用户诉求是“合并成一栏”，不是单纯压缩间距
- 当前顶栏信息层级足够清晰，适合作为全局上下文承载层
- 这次改动可以直接提升原生监控页首屏信息密度

## 交互与布局细节

左侧：

- 第一行保留 `Workspace`
- 第二行主标题保留当前 section，例如 `Traffic`
- 在标题下方新增一条紧凑元信息，展示 `Admin` 与 endpoint

右侧：

- 继续保留模式切换胶囊组
- 保留三枚状态 pill
- 将全局 `Refresh` 按钮并入顶栏最右侧
- 最近刷新时间作为弱化文本，放在按钮前或状态组附近

异常态：

- 当 `loadError` 存在时，在内容区顶部保留一条错误条，并附 `Retry`
- 正常态不再渲染额外的 header 容器

## 实现影响

- `AppShellView` 需要接收更多壳层元数据
- `TopModeBar` 需要支持 admin endpoint、刷新时间和刷新动作
- `ContentView` 需要移除原 `headerBar` 的常态渲染，改为错误横幅
- 数据加载逻辑不变，不改动 `AdminApiClient`、`TrafficAnalyticsModel` 和 stats 流程

## 测试策略

本次以最小可回归模型测试 + 原生端集成为主：

- 为壳层顶栏新增纯派生模型，验证 endpoint、刷新文案、刷新中状态等输出
- 运行 `FluxDeckNativeTests`
- 运行完整原生测试命令，确认 UI 结构调整没有破坏现有数据模型测试

## 验收标准

- 页面顶部只保留一层常驻信息栏
- 顶栏同时可见当前页面、admin endpoint、模式切换、状态 pill、刷新入口
- 内容区首屏更早出现 `Traffic Monitor`
- 错误态仍可见且支持重试
