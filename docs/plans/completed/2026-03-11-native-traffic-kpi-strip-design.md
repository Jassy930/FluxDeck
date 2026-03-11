# FluxDeck macOS 原生 Traffic KPI 连续指标栏设计

## 目标

将 `Traffic` 页面中的 4 个主要 KPI 从独立短卡改为一条连续的高密度指标栏，以进一步压缩首屏高度，并让趋势区更早进入可视范围。

## 当前问题

- 即便已经压缩为短卡，4 个 KPI 仍然占据两行空间
- 每个 KPI 仍有独立卡片边界，首屏信息块过于分散
- 趋势区仍被向下推，影响监控页首屏扫读效率

## 设计方案

### 1. KPI 改为单条 `metric strip`

采用一张 `SurfaceCard` 承载 4 段连续指标：

- `Requests / min`
- `Success Rate`
- `Avg Latency`
- `Total Tokens`

每段由细竖线分隔，不再拥有独立外边框。

### 2. 每段结构

每段只保留三层：

- 小标题
- 大数字
- 极短补充信息

示例：

- `Requests / min` → `0.1` → `95 total`
- `Success Rate` → `75.8%` → `72 ok / 23 err`
- `Avg Latency` → `4219 ms` → `selected period`
- `Total Tokens` → `146,184` → `combined usage`

### 3. 布局策略

- 优先横向单排展示
- 若可用宽度不足，可降级为 `2 x 2`
- 在当前桌面最小宽度下，目标仍应以单排为主

### 4. 视觉规则

- 保持现有 `SurfaceCard`、`DesignTokens`
- 不给每段再套 `StatusPill`
- 状态语义通过补充文案和数字表达
- 分隔线要轻，不破坏整体一体感

## 验收标准

1. 4 个 KPI 在宽屏下位于同一行。
2. 趋势区相对当前版本明显上移。
3. 页面依旧保持原生深色工作台气质。
4. 不牺牲主要指标可读性。
