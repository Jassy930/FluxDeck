# FluxDeck Native Logs Workbench Redesign

## 文档状态

- 状态：已确认
- 类型：设计文档，待进入实现
- 适用范围：`apps/desktop-macos-native`、`crates/fluxd`、日志相关文档

## 背景

当前原生端 `Logs` 页面仍采用“双栏”结构：

- 左侧 `Requests` 列表
- 右侧 `Details` 详情卡

这种结构存在两个问题：

1. 关键诊断信息被拆散，用户需要在左右区域之间来回对照。
2. 后端 Admin API 已经暴露了更丰富的转发与 usage 字段，但原生端 `AdminLog` 仍只消费基础字段，信息密度明显不足。

本次改版目标是把日志页升级为单列、可扫描、可展开的排障工作台，并同步补齐日志契约消费能力。

## 已确认产品决策

以下决策已经与用户确认：

- 页面主形态改为“可展开日志卡片”，不再保留 `Requests + Details` 分栏。
- 默认折叠态直接显示：
  - 状态
  - 路由 `gateway -> provider`
  - 模型信息
  - 若存在模型映射，显示 `请求模型 -> 实际模型`
  - 错误摘要
  - 延迟
  - 时间
- 失败日志比成功日志更醒目；成功日志保持更紧凑。
- 同一时刻仅允许展开一条日志，采用手风琴交互。
- 日志模型需要补齐到当前 Admin API 稳定契约。
- token 展示增加：
  - `input_tokens`
  - `output_tokens`
  - `cached_tokens`
  - `total_tokens`
- `fluxctl` 需要检查是否受日志契约变更影响。

## 目标

1. 让用户在不点开详情面板的情况下完成大部分日志扫描。
2. 把模型映射、错误摘要、延迟和时间提升为一眼可见的信息。
3. 让展开态承担“精查”职责，而不是基础信息承载职责。
4. 将原生端日志模型升级到可消费 Admin API 全量稳定字段。
5. 在不破坏现有 `fluxctl logs` 基本行为的前提下，同步更新相关文档与示例。

## 非目标

- 不新增全文搜索、时间范围筛选、分组视图或导出能力。
- 不改变 `fluxctl logs` 的命令结构或输出格式。
- 不在本次设计中重做 Overview / Traffic / Connections 页面。
- 不把 `usage_json` 升级为结构化对象契约；仍保留字符串返回。

## 信息架构

### 1. 顶部筛选区

保留现有筛选能力，但视觉上从“大卡片”收敛为更紧凑的查询条：

- `Gateway`
- `Provider`
- `Status`
- `Only Errors`
- `Clear Filters`
- 已加载数量与是否仍可翻页

筛选区继续置顶，但不再抢占主视图注意力。

### 2. 主体区

主体改为单个 `Request Stream` 风格卡片，内部为纵向日志流：

- 每条日志是一张独立卡片
- 卡片默认折叠
- 点击卡片后在同一卡片内展开
- 失败日志使用更强的描边、语义色和状态徽记
- 成功日志保持更克制的视觉权重

### 3. 折叠态

折叠态优先服务“扫描”：

- 左侧：
  - 状态徽记
  - 路由 `gateway -> provider`
  - 模型文案
  - 错误摘要（有错误时优先展示）
- 右侧：
  - 延迟
  - 时间
  - 展开指示

### 4. 展开态

展开态承担“诊断明细”职责，展示：

- `request_id`
- `inbound_protocol / upstream_protocol`
- `stream / first_byte_ms`
- `input_tokens / output_tokens / cached_tokens / total_tokens`
- `error_stage / error_type`
- 完整错误文本
- `usage_json` 若非空，可作为原始明细文案显示

## 模型与映射展示规则

日志主视图不再只依赖旧字段 `model`，而是优先使用模型语义字段：

1. 若 `model_requested` 与 `model_effective` 都有值且不同，显示：
   - `请求模型 -> 实际模型`
2. 若两者都有值且相同，仅显示一个模型名，避免重复。
3. 若只有其中一个有值，则显示该值。
4. 若两者都没有值，则回退显示旧字段 `model`。
5. 若三者都为空，显示占位 `-`。

这样可以将模型 mapping 直接前置到日志折叠态，而不是隐藏到展开区。

## Token 设计

### 为什么不能只靠 `usage_json`

当前仓库约束明确要求不要猜测边界数据结构。不同 provider 的 usage 形状并不稳定，因此不能把 `cached token` 仅作为前端临时解析逻辑处理。

### 本次推荐做法

将 `cached_tokens` 提升为稳定契约字段，并保持以下口径：

- `input_tokens`：输入 token
- `output_tokens`：输出 token
- `cached_tokens`：缓存命中的 token
- `total_tokens`：总 token

同时继续保留：

- `usage_json`：原始 usage 明细字符串，用于兼容、排障和后续迭代

### 与更细粒度缓存字段的关系

如果未来上游 usage 包含：

- `cache_read_tokens`
- `cache_write_tokens`

第一版只要求后端整理出稳定的 `cached_tokens` 聚合口径，更细颗粒继续保留在 `usage_json`。等真实使用场景证明有必要，再升级契约版本。

## 后端与契约变更

### `request_logs` / Admin API

本次需要把日志稳定字段从“基础 usage”扩展为“完整日志诊断字段”：

- 已有但原生端未消费的字段：
  - `inbound_protocol`
  - `upstream_protocol`
  - `model_requested`
  - `model_effective`
  - `stream`
  - `first_byte_ms`
  - `input_tokens`
  - `output_tokens`
  - `total_tokens`
  - `usage_json`
  - `error_stage`
  - `error_type`
- 新增稳定字段：
  - `cached_tokens`

### 数据来源建议

- 对支持直接返回缓存 token 的上游：
  - 后端在 `UsageSnapshot` 中明确承载 `cached_tokens`
- 对只有 `usage_json` 带有缓存维度的上游：
  - 由后端在协议适配层完成提取与归一
- 对不返回缓存 token 的上游：
  - `cached_tokens = null`

## 原生端视图实现建议

### 组件层

建议将日志项拆成更明确的视图单元：

- `LogsWorkbenchView`
  - 负责筛选条、空态、加载态、错误态、分页按钮
- `LogStreamCard`
  - 单条日志的折叠/展开容器
- `LogSummaryRow`
  - 折叠态信息排布
- `LogExpandedDetail`
  - 展开态明细区

如果当前仓库倾向先最小变更，也可先在 `LogsWorkbenchView.swift` 内完成拆分，第二阶段再抽组件。

### 交互细节

- 点击整张日志卡片切换展开状态
- 仅一条展开：切换到新卡片时自动收起旧卡片
- 分页 `Load More` 保持在列表底部
- 筛选变化后默认回到全折叠状态，避免旧展开项引用失效

## `fluxctl` 影响评估

本次结论：

- `fluxctl` 当前只是把 `limit` 拼到 `/admin/logs` 并原样打印 JSON。
- 它没有本地 `LogItem` 强类型结构，也没有依赖固定字段集合做反序列化。

因此：

- **`fluxctl` 预计不需要代码修改**
- 但需要同步检查与更新：
  - `docs/USAGE.md`
  - `docs/ops/local-runbook.md`
  - 日志返回示例中的字段说明

如果后续希望 `fluxctl logs` 增加“人类可读模式”或 token 摘要格式化，那是独立需求，不纳入本次范围。

## 测试与验收

### 后端

- SQLite migration 测试覆盖 `cached_tokens` 列存在
- Admin API 测试覆盖 `/admin/logs` 返回 `cached_tokens`
- 请求日志服务测试覆盖插入与回写 `cached_tokens`

### 原生端

- `AdminApiClient.decodeLogPage` 解码测试覆盖新增字段
- 日志页模型/格式化测试覆盖：
  - 模型 mapping 展示
  - 错误优先摘要
  - token 文案
- 日志页视图测试或模型测试覆盖：
  - 手风琴展开行为
  - 筛选切换后展开态重置

### 文档

- `docs/contracts/admin-api-v1.md` 更新日志字段契约
- `docs/USAGE.md` 与 `docs/ops/local-runbook.md` 更新示例与说明

## 风险

1. `cached_tokens` 的上游来源并不统一，后端需要先收敛归一口径。
2. 原生端日志页如果一次塞入过多文本，容易破坏当前深色工作台的节奏，需要控制折叠态密度。
3. 工作区当前已有未提交改动，本次实现必须避免覆盖其他进行中的变更。

## 推荐实现顺序

1. 后端先扩展稳定字段 `cached_tokens`
2. 更新契约、migration 与后端测试
3. 原生端补齐 `AdminLog` 解码模型
4. 重构 `LogsWorkbenchView` 为单列可展开卡片
5. 更新文档并做回归验证
