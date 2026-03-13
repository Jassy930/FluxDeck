# FluxDeck Native Traffic 模型 Token 趋势图改造设计

## 文档状态

- 状态：已确认
- 类型：设计文档，待进入实现
- 适用范围：`crates/fluxd`、`apps/desktop-macos-native`

## 背景

当前原生端 `Traffic` 页面主图仍以 `request_count` 与 `avg_latency` 两条归一化折线叠加的方式表达趋势。这个实现能反映方向变化，但存在两个问题：

1. 主图语义与用户最关心的 token 负载不一致，无法直接回答“总 token 由哪些模型构成”。
2. 双线各自归一化后共用一个视觉空间，容易让用户误读为同一数值坐标系。

用户已明确要求把主图升级为“总 token + 不同模型 token 分布”的趋势图，并增加更高时间密度、图例和 tooltip。

## 已确认产品决策

- 主图区从“请求量 / 平均延迟趋势”切换为“按模型堆叠的 token 趋势”。
- 主图以每个时间桶的 `total_tokens` 为总高度，不再展示平均延迟折线。
- 不同模型的 token 使用量在同一个时间桶内按颜色堆叠，整体高度等于该时间桶总 token。
- 视觉形式采用“堆叠面积 + 每层上边界折线”的混合样式，保持监控折线图气质。
- 时间密度提高：
  - `1h -> 1m`
  - `6h -> 5m`
  - `24h -> 15m`
- 图例必须可见，并支持按模型查看颜色映射。
- tooltip 必须展示 bucket 时间、总 token、各模型 token 明细。
- 主图默认显示 Top N 模型，剩余模型合并为 `Other`，避免颜色过多导致可读性崩坏。

## 目标

1. 让用户在一眼内读出每个时间桶的总 token 波动。
2. 让用户判断 token 峰值由哪些模型贡献，而不是只看到整体总量。
3. 保持原生深色监控工作台风格，不引入第三方图表库。
4. 让时间维度更密，支持更接近实时监控的读取节奏。
5. 保证数据来源完全基于稳定后端契约，不从前端日志样本推导。

## 非目标

- 本次不恢复 `request_count` / `avg_latency` 双折线到主图中。
- 不引入缩放、拖拽平移、框选等复杂图表交互。
- 不新增自动轮询、告警规则编辑、下钻分析。
- 不修改 `apps/desktop/` Web 桌面端实现。

## 主图设计

### 1. 信息语义

主图标题调整为 `Token Trend by Model`。

图形表达：

- X 轴：时间 bucket
- Y 轴：该 bucket 的 `total_tokens`
- 图层：每个模型在该 bucket 的 token 值
- 总高度：该 bucket 所有模型 token 之和

这种表达方式比双折线更接近监控问题本身：高峰来自什么模型，而不是“这段时间延迟高不高”。

### 2. 图形形式

采用堆叠面积图，但保留每层的上边界折线：

- 填充层使用低透明度颜色，避免深色背景上过于厚重。
- 每层顶部边界线使用同色高亮线条，强化趋势可读性。
- 最顶部总量轮廓允许略微提亮，帮助快速识别峰值。

这能同时满足“占满总 token 范围”的要求和“仍像监控折线图”的视觉预期。

### 3. 模型分层策略

默认仅展示 Top 4 模型，依据为当前 period 内总 `total_tokens` 降序。

其余模型合并为：

- `Other`

原因：

- 模型数过多时，颜色会迅速失控
- 图例和 tooltip 仍可读
- 大部分监控场景只需要聚焦主要负载贡献者

排序规则：

1. 先按 period 总 token 降序
2. 同值按模型名排序
3. Top 4 保留原名
4. 其他全部折叠进 `Other`

### 4. 颜色与视觉规则

保持原生监控风格，采用稳定顺序色板：

- Top 1：绿色
- Top 2：青色
- Top 3：橙色
- Top 4：蓝色
- `Other`：低饱和灰蓝

要求：

- 同一模型在整个 period 内颜色稳定不变
- tooltip、图例、面积层颜色保持一致
- 不在页面中散落硬编码颜色，应尽量集中在 `DesignTokens` 或局部图表常量中

### 5. 图例

图例放在图卡标题区右侧或图内部上边缘，展示：

- 颜色点
- 模型名称

交互要求：

- 首版至少支持静态图例
- 若实现成本可控，支持点击图例临时隐藏/显示模型层

即使首版不做显隐，也必须保留图例区结构，便于后续扩展。

### 6. Tooltip

tooltip 需要在鼠标 hover 时展示当前 bucket 的完整摘要：

- bucket 时间
- `Total Tokens`
- 各模型 token（按值降序）
- 若该 bucket 有 `error_count`，作为次级信息展示

tooltip 规则：

- 数据按当前 bucket 读取，不做插值推导
- 数值使用千分位格式化
- 当前 bucket 对应的竖向高亮辅助线应同步出现

## 数据契约变更

### 现状问题

当前 `GET /admin/stats/trend` 仅返回 bucket 总体统计：

- `request_count`
- `avg_latency`
- `error_count`
- `input_tokens`
- `output_tokens`
- `cached_tokens`

它缺少“按模型拆分的 bucket token 分布”，因此无法支持模型堆叠图。

### 新契约方向

扩展 `GET /admin/stats/trend` 的 `data[]`，为每个 bucket 增加 `by_model`：

- `by_model: Array<{ model: string, total_tokens: number, input_tokens: number, output_tokens: number, cached_tokens: number, request_count: number, error_count: number }>`

说明：

- `total_tokens` 为每模型在该 bucket 的总 token
- 其余 token 字段用于 tooltip 明细和后续扩展
- `request_count` / `error_count` 允许 tooltip 后续显示“该模型在该 bucket 的请求与错误”
- 空模型名统一在服务端归一为稳定占位值，如 `Unknown model`

聚合规则：

- 时间 bucket 仍由 `period + interval` 决定
- 分组维度为 `bucket timestamp + model_effective 优先，其次 model`
- `NULL` 模型在服务端归一，避免前端猜空值

### 兼容性策略

- 保留现有 bucket 顶层字段，避免现有消费方立即失效
- 新增 `by_model` 为向后兼容扩展
- 原生端主图改为消费 `by_model`
- `request_count / avg_latency / error_count` 顶层字段保留给次级摘要或后续兼容用途

## 原生端模型设计

### 新增展示模型

在 `TrafficAnalyticsModel` 周边新增专用图表结构，而不是直接把 API DTO 喂给视图：

- `TrafficTokenTrendSeries`
  - `modelName`
  - `colorRole`
  - `buckets: [TrafficTokenTrendBucketValue]`
  - `totalTokens`
- `TrafficTokenTrendBucketValue`
  - `timestamp`
  - `value`
- `TrafficTokenTrendTooltipModelRow`
  - `modelName`
  - `totalTokens`
  - `inputTokens`
  - `outputTokens`
  - `cachedTokens`
- `TrafficTokenTrendTooltip`
  - `timestampLabel`
  - `totalTokens`
  - `errorCount`
  - `rows`

`TrafficAnalyticsModel` 负责：

- 从 `AdminStatsTrend` 提取所有 bucket
- 汇总模型 period 总 token
- 计算 Top 4 + `Other`
- 对缺失 bucket 的模型补 0
- 生成图表序列、图例与 tooltip 基础数据

### 视图结构

`TrafficTrendChart` 调整为支持：

- 堆叠面积绘制
- 图例
- hover 追踪
- tooltip 定位
- bucket 高亮

避免把模型筛选、聚合、排序逻辑写在 View 中。

## 时间密度调整

`Traffic` 页面当前 interval 映射为：

- `1h -> 5m`
- `6h -> 15m`
- `24h -> 1h`

本次调整为：

- `1h -> 1m`
- `6h -> 5m`
- `24h -> 15m`

影响：

- 后端 bucket 数量明显增加
- 原生端 hover 命中与 tooltip 显示必须按 bucket 中心对齐
- 图表宽度不足时，依然优先保持连续趋势，不强制显示密集 X 轴刻度文本

## 摘要指标调整

主图下方摘要不再使用：

- `Peak Req`
- `Peak Latency`

替换为更符合 token 主图语义的摘要：

- `Peak Total Tokens`
- `Top Model Share`
- `Peak Bucket Errors`

其中：

- `Peak Total Tokens`：单 bucket 总 token 峰值
- `Top Model Share`：period 内 Top 1 模型占总 token 百分比
- `Peak Bucket Errors`：单 bucket 最大错误数

## 测试策略

### Rust

必须补失败测试验证：

- `/admin/stats/trend` 返回 `by_model`
- bucket 级模型 token 聚合正确
- `NULL` 模型被归一为稳定名称
- 更高时间密度下 bucket 结果仍稳定

### 原生端 XCTest

必须补失败测试验证：

- `AdminStatsTrend` 新字段解码
- `TrafficAnalyticsModel` 正确生成 Top 4 + `Other`
- 缺失 bucket 会按 0 补齐
- tooltip 数据按 bucket 正确排序
- 图下摘要切换到 token 语义

### 回归重点

- 现有 KPI strip 不被破坏
- `Routing Summary`、breakdown 与 alerts 仍可渲染
- 无趋势数据时页面保持可读空态

## 验收标准

1. 原生端 `Traffic` 主图显示按模型堆叠的 token 趋势，而不是请求/延迟双折线。
2. 图例可见，模型颜色稳定且可区分。
3. hover 时出现 tooltip，内容包含总 token 与模型拆分。
4. 时间密度切换为 `1m / 5m / 15m` 映射后仍可稳定渲染。
5. `/admin/stats/trend` 契约与原生端测试同步更新，数据完全来自后端稳定聚合。
