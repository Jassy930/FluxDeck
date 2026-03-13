# FluxDeck Native 拓扑 Token 流画布改造设计

## 文档状态

- 状态：已实现
- 类型：设计文档
- 适用范围：`apps/desktop-macos-native`

## 背景

当前原生端 `Topology` 页面已经具备基础三列结构：

- `Entrypoints`
- `Gateways`
- `Providers`

但画布仍然停留在“节点卡片 + 单色粗线”的阶段，存在三个关键问题：

1. 连线只按 `requestCount` 编码，无法表达真实的 token 负载。
2. 不同模型共享同一条链路时，用户看不到 model 对 token 的贡献结构。
3. 底部摘要仍然以 request 为主语义，无法快速回答“哪条链路最吃 token、由哪些 model 构成”。

用户已经明确要求：

- 保持三列结构，不增加显式 `Models` 第四列
- 参考 VPN / Sankey 风格的流向画布
- 在链路中直接体现 token 流量大小
- model 作为链路内部的分类维度出现，而不是独立列

## 已确认产品决策

- 页面仍保持三列：`Entrypoints -> Gateways -> Providers`
- 每条边从“单一粗线”升级为“按 model 分层的 token 流带”
- 流带厚度优先编码 `total_tokens`
- model 使用稳定颜色映射
- `requestCount` 降级为辅助指标，不再作为主视觉编码
- 顶部控制区增加：
  - `Tokens / Requests`
  - `By Model / Total Only`
  - `Top 3 / Top 5 / All`
- 底部摘要区升级为：
  - `Hot Paths`
  - `Model Mix`

## 目标

1. 让用户一眼看出最主要的 token 流向。
2. 让用户看清同一路径内不同 model 的 token 占比。
3. 保持三列拓扑结构稳定，不因模型维度破坏整体可读性。
4. 不引入新的后端专用拓扑接口，先基于稳定日志字段完成客户端聚合。
5. 延续现有原生深色工作台视觉，不把拓扑页做成通用报表页。

## 非目标

- 本次不新增 `Models` 第四列。
- 不引入新的 `/admin/topology` 后端接口。
- 不做拖拽布局、自由缩放、平移、框选。
- 不做节点详情抽屉或侧滑诊断面板。
- 不修改暂停中的 `apps/desktop/` Web 桌面端实现。

## 画布设计

### 1. 页面主结构

页面继续保持两段：

- 主画布：负责链路结构与 token 流向表达
- 底部摘要：负责快速落到数字结论

主卡标题改为更明确的 token 语义，例如：

- `Topology Flow`
- 副标题：`Entrypoints · Gateways · Providers · Model token composition`

### 2. 三列结构

三列固定顺序，不做动态重排：

- `Entrypoints`
- `Gateways`
- `Providers`

原因：

- 当前用户已经熟悉这套结构
- 三列足以承载入口、转发、上游责任边界
- model 更适合作为流带内部维度，而不是额外加列让画布变拥挤

### 3. 流带语义

每条边由一组 `model segment` 组成。

对于任意一条链路：

- 总厚度 = 该链路聚合后的总 token
- 子层厚度 = 该 model 在该链路上的 `total_tokens`
- 子层颜色 = model 固定映射颜色

这样同一条 `Gateway -> Provider` 链路可以同时表达：

- 总 token 体积
- model 贡献结构
- 高峰由哪个 model 造成

### 4. 视觉编码规则

- 主编码：`total_tokens`
- 次编码：`request_count`
- 颜色：`model`
- 透明度：活跃度
- 警告描边：错误或异常比例偏高的链路

默认模式下：

- 流带按 `Tokens` 计算厚度
- 流带内部按 `By Model` 分层
- 仅显示 `Top 5` model，剩余合并为 `Other`

### 5. 视觉风格

参考用户提供的 VPN 项目，但保持 FluxDeck 原生工作台风格：

- 深灰蓝黑背景，不使用纯黑
- 节点更窄、更克制，让流带成为主角
- 流带使用平滑曲线和半透明填充，而不是只有描边
- 主要 token 主干允许轻微发光，但不做夸张霓虹
- 低活跃链路降低亮度，高活跃链路适度提亮

## 节点卡片设计

### 1. 通用原则

节点卡片不再是页面主角，而是流图锚点：

- 宽度收窄
- 强化标题可读性
- 用紧凑 badge 暴露关键汇总指标

### 2. Entrypoint

- 标题：监听地址
- 副标题：端口
- 辅助指标：总 token

### 3. Gateway

- 标题：网关名
- 副标题：`host:port`
- 辅助指标：
  - `tokens`
  - `req`
  - `Top model share`

### 4. Provider

- 标题：provider 名
- 副标题：协议类型
- 右上角：状态点
- 辅助指标：
  - `tokens`
  - `cached`
  - `error rate`

## 顶部控制区设计

只保留会影响读图判断的最小控制集合：

### 1. Metric

- `Tokens`
- `Requests`

默认 `Tokens`。

切换后：

- `Tokens`：流带厚度按 token
- `Requests`：流带厚度按请求量

### 2. Flow Mode

- `By Model`
- `Total Only`

默认 `By Model`。

`Total Only` 用于快速看主干，不显示 model 分层颜色。

### 3. Highlight

- `Top 3`
- `Top 5`
- `All`

默认 `Top 5`。

目的：

- 避免高模型数场景把画布打散
- 保证默认视图仍然清晰

### 4. Refresh

继续保留现有刷新入口，不新增独立轮询策略。

## 底部摘要区设计

### 1. Hot Paths

展示当前周期 token 最高的路径。

每项内容：

- 路径：`entrypoint -> gateway -> provider`
- `tokens`
- `req`
- `top model`

用于快速回答“最忙链路是哪条”。

### 2. Model Mix

展示当前画布聚合周期内的 model token 占比。

表现形式：

- 横向堆叠条
- 或紧凑色块 + 百分比列表

用于快速回答“整体 token 被哪些 model 吃掉”。

## 数据模型设计

## 数据来源

第一版仅基于原生端当前已拿到的数据：

- `AdminGateway`
- `AdminProvider`
- `AdminLog`

不新增后端专用拓扑接口。

### 聚合口径

节点层：

- `Entrypoints / Gateways` 来自 `AdminGateway`
- `Providers` 来自 `AdminProvider`

流量层：

- 由 `AdminLog` 聚合

聚合维度：

- `entrypoint -> gateway`
- `gateway -> provider`
- 每条边内部再按 `model_effective -> model -> unknown` 分组

主指标：

- `total_tokens`

辅助指标：

- `request_count`
- `cached_tokens`
- `error_count`

### 稳定归一规则

- 优先使用日志字段 `total_tokens`
- 若缺失，则用 `input_tokens + output_tokens` 回填
- model 取值优先级：
  - `model_effective`
  - `model`
  - `unknown`
- provider 缺失于当前 provider 列表时，仍保留匿名 provider 节点
- token 全缺失但请求存在时，允许回退到按请求量显示最细基础流带

## 原生端展示模型

建议把现有 `TopologyGraph` 扩展为更明确的聚合视图模型，而不是把所有逻辑塞进 View：

- `TopologyNode`
  - `id`
  - `title`
  - `subtitle`
  - `totalTokens`
  - `requestCount`
  - `cachedTokens`
  - `errorCount`
- `TopologyEdge`
  - `id`
  - `fromNodeID`
  - `toNodeID`
  - `totalTokens`
  - `requestCount`
  - `cachedTokens`
  - `errorCount`
  - `segments`
- `TopologyEdgeSegment`
  - `modelName`
  - `totalTokens`
  - `requestCount`
  - `cachedTokens`
  - `errorCount`
  - `share`

同时引入轻量控制模型：

- `TopologyMetricMode`
- `TopologyFlowMode`
- `TopologyHighlightMode`

## 实现边界

首版只做：

1. 三列稳定布局
2. token / requests 双指标切换
3. `By Model / Total Only` 切换
4. `Top N models` 过滤
5. 底部 `Hot Paths + Model Mix`

本次明确不做：

1. 拖拽布局
2. 节点详情抽屉
3. 全图 hover 联动高亮
4. 新后端接口
5. 历史回放与时间轴回溯

## 测试策略

### 1. 视图模型测试

在 `FluxDeckNativeTests.swift` 增加：

- 多条日志聚合到同一边时 token 求和正确
- 同一路径内 model 分层正确
- `unknown` model 归并正确
- token 缺失时回填逻辑正确
- `Top N` 过滤后 `Other` 合并正确

### 2. 视图行为测试

至少验证：

- `By Model` 与 `Total Only` 两种展示模式都有稳定无数据/有数据输出
- `Tokens / Requests` 切换不会导致空白画布
- `Hot Paths` 与 `Model Mix` 使用的是 token 语义

### 3. 手工验收

- 最粗流带应与日志中最高 token 热点一致
- `Tokens / Requests` 切换后主干流排序应发生可解释变化
- 同一路径中的不同 model 颜色分层应清晰可读
- 低活跃链路不应抢主视觉

## 验收标准

1. 用户能在 3 秒内判断最主要的 token 流向。
2. 用户能在不增加 `Models` 列的前提下看清 model token 构成。
3. 画布风格明显优于当前“节点卡片 + 单色粗线”方案。
4. 页面仍保持三列拓扑结构，未退化为复杂报表。
5. 第一版只依赖当前原生端已有稳定数据，不要求后端新增契约。
