# FluxDeck Native Traffic KPI 附属指标增强设计

## 文档状态

- 状态：已确认
- 类型：设计文档，待进入实现
- 适用范围：`apps/desktop-macos-native`

## 背景

当前原生端 `Traffic` 页面已经采用连续 KPI 指标栏，但每个 KPI 只显示主值和一行摘要，仍然缺少监控场景最需要的二级判断信息：

- `Requests / min` 无法快速看出流量主要集中在哪些 gateway
- `Success Rate` 无法直接判断错误主要落在哪些 gateway
- `Avg Latency` 无法快速判断高延迟来自哪几个 gateway
- `Total Tokens` 只有总量，没有 `input / output / cached` 的结构信息

用户要求在四个最大 KPI 指标下增加附属指标，同时保持当前原生深色工作台和连续指标栏的整体气质不变。

## 已确认产品决策

- 保持现有连续 KPI 指标栏，不改成新的大卡片布局
- 每个 KPI 在主值下新增紧凑的附属指标区
- 分 gateway 的附属指标统一按 `request_count` 降序取最多两个 gateway
- `Requests / min`、`Success Rate`、`Avg Latency` 都按最多两个 gateway 展示
- `Total Tokens` 展示整体 `Input / Output / Cached`

## 目标

1. 让用户在首屏直接判断最活跃 gateway 的请求量、成功情况和延迟情况
2. 让 token 总量具备结构信息，而不是只有总数
3. 保持当前页面的信息密度与视觉秩序，不引入新的视觉噪音
4. 为 tokens 结构信息提供可信口径，避免前端猜测统计语义

## 非目标

- 不改动趋势图、Routing Summary 和 breakdown 卡片结构
- 不新增 gateway drill-down、hover 展开、tooltip 或点击跳转
- 不在本次实现中增加自动轮询

## 设计方案

### 1. KPI 结构保持不变

沿用现有四段式 `metric strip`：

- `Requests / min`
- `Success Rate`
- `Avg Latency`
- `Total Tokens`

每段仍由：

- 小标题
- 大数字
- 附属指标区

组成，只是将原本单行摘要升级为 2 到 3 行紧凑附属指标。

### 2. 各 KPI 的附属指标

#### `Requests / min`

- 主值保持现有 `requests_per_minute`
- 下方增加最多两行 gateway 行：
  - `gw_alpha 2.4 rpm`
  - `gw_beta 1.8 rpm`

口径：

- 使用 `overview.byGateway`
- 按 `request_count` 降序取前两个
- 以 `gateway.request_count / periodMinutes` 计算 gateway 级 `rpm`

#### `Success Rate`

- 主值保持现有整体 `success_rate`
- 下方增加最多两行 gateway 行：
  - `gw_alpha 35 ok / 5 err`
  - `gw_beta 25 ok / 7 err`

口径：

- 使用 `overview.byGateway`
- 直接读取每个 gateway 的 `success_count` 与 `error_count`

#### `Avg Latency`

- 主值保持现有整体平均延迟
- 下方增加最多两行 gateway 行：
  - `gw_alpha 420 ms`
  - `gw_beta 1250 ms`

口径：

- 使用 `overview.byGateway`
- 直接读取每个 gateway 的 `avg_latency`

#### `Total Tokens`

- 主值保持现有整体 `total_tokens`
- 下方增加三项结构化指标：
  - `Input 1,800`
  - `Output 3,000`
  - `Cached 118,656`

口径：

- `Input`：使用 `trend.data[].input_tokens`
- `Output`：使用 `trend.data[].output_tokens`
- `Cached`：使用 `trend.data[].cached_tokens` 的 period 聚合值

说明：

- `cached_tokens` 必须由 `fluxd` 统计接口直接提供
- 原生端不允许再通过 `total_tokens - input - output` 推导 `cached`
- 这是因为当前仓库已将 `cached_tokens` 定义为独立稳定语义字段，而不是 `total_tokens` 的剩余量

## 后端契约调整

为保证 `cached_tokens` 口径可信，本次需要同步扩展 `fluxd` 的 Stats API：

- `GET /admin/stats/overview`
  - 新增 `cached_tokens: number`
  - `by_gateway / by_provider / by_model` 各维度新增 `cached_tokens: number`
- `GET /admin/stats/trend`
  - `data[]` 每个 bucket 新增 `cached_tokens: number`

聚合规则：

- 全部直接来自 `request_logs.cached_tokens`
- 缺失值按 `0` 聚合
- 不做前端推导，不从 `usage_json` 临时解析

## 视觉规则

- 附属指标字体小于主值，使用 `caption2` 或同等级
- gateway 名称使用主文本色的较低权重，数值使用主文本色
- 不增加状态胶囊、彩色徽记或图标，避免抢占主值注意力
- 附属指标区保持左对齐，行高紧凑
- 在窄宽度回退为 `2 x 2` 栅格时，附属指标仍需完整可见

## 数据模型建议

在 `TrafficAnalyticsModel` 中增加专门的 KPI 附属指标结构，而不是在视图层拼字符串，以保证：

- 测试可直接断言结构与顺序
- 视图保持简单
- 后续若需要增加第三种附属指标样式，不必回改主模型接口

建议结构：

- `TrafficKpiSupplementRow`
  - `label`
  - `value`
- `TrafficKpiStripItem`
  - `title`
  - `value`
  - `detailRows: [TrafficKpiSupplementRow]`

## 测试要求

1. 先补失败测试，确认：
   - KPI 顺序不变
   - `Requests / min`、`Success Rate`、`Avg Latency` 均只取前两个 gateway
   - `Total Tokens` 正确消费后端返回的 `Input / Output / Cached`
   - `fluxd` 的 `overview / trend` 都返回 `cached_tokens`
2. 再实现模型派生逻辑
3. 再实现 `fluxd` 统计聚合与原生端消费
4. 最后验证 Rust 与原生端测试通过

## 验收标准

1. 四个 KPI 主值保持不变，附属指标出现在主值下方
2. gateway 类附属指标最多显示两行，且按 `request_count` 排序
3. tokens 卡显示 `Input / Output / Cached`
4. 宽屏和窄屏回退布局下均无明显拥挤或截断
5. `cached_tokens` 完全来自后端稳定契约，Rust 与原生端测试通过
