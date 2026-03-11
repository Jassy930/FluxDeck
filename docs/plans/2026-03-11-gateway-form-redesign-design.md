# FluxDeck macOS 原生 Gateway 配置表单重构设计

## 目标

将 `apps/desktop-macos-native` 中的 `GatewayFormSheet` 从系统 `Form` 风格重构为与 `ProviderFormSheet` 一致的工作台式配置界面，同时统一 `New Gateway` 与 `Edit Gateway` 的视觉和交互体验。

本次设计仅覆盖 Gateway 创建/编辑弹窗，不调整 Gateway 列表页的信息架构，不修改后端 Admin API 契约。

## 当前现状

- `ProviderFormSheet` 已采用深色工作台样式：
  - 顶部标题栏
  - 摘要卡
  - 多张 `SurfaceCard`
  - 底部固定操作栏
- `GatewayFormSheet` 仍使用 `NavigationStack + Form + Section`：
  - 字段按后端顺序平铺
  - 视觉层级弱
  - `Routing JSON` 可编辑区过小
  - `Default Provider ID`、协议字段仍依赖自由输入，易出错

## 设计原则

1. Gateway 配置页必须与 Provider 配置页共用一套视觉语言和布局节奏。
2. 字段顺序按用户决策顺序组织，而不是按数据模型顺序平铺。
3. 高风险字段优先使用受控输入，降低拼写和配置错误概率。
4. `Routing JSON` 作为高级配置区单独突出，但不抢占主表单语义。
5. 创建态与编辑态只在可编辑字段和标题文案上区分，整体结构保持一致。

## 界面结构

### 1. 顶部标题栏

- 创建态：`Create Gateway`
- 编辑态：`Configure Gateway`
- 副标题：说明该界面用于管理本地监听、协议桥接与默认路由
- 右侧状态胶囊：展示 `Enabled` / `Disabled`

### 2. 摘要卡

使用 `Gateway Snapshot`，展示：

- 当前名称
- 监听地址 `host:port`
- 三个紧凑指标：
  - `Inbound`
  - `Upstream`
  - `Provider`

目的：打开弹窗即可确认当前 Gateway 入口协议、出口协议和默认上游目标。

### 3. 主配置双栏

#### 左栏：Identity

- `Gateway ID`
  - 创建态可编辑
  - 编辑态只读
- `Display Name`
- `Default Provider`
  - 优先使用 picker，从当前 provider 列表中选择
  - 若当前值不存在，显示保底选项以避免历史配置丢失
- `Default Model (optional)`

#### 右栏：Runtime

- `Enabled`
- `Auto Start`
- 状态摘要：
  - `Status`
  - `Startup`
  - `Endpoint`

目的：让用户在修改前直接看到该 Gateway 的运行参与状态和启动策略。

### 4. 独立配置卡片

#### Network & Protocols

- `Listen Host`
- `Listen Port`
- `Inbound Protocol`
- `Upstream Protocol`

协议字段改为 picker，避免自由输入导致拼写不一致。

#### Routing JSON

- 保留大尺寸等宽编辑器
- 顶部加说明文案，强调该配置仅影响协议映射与兼容细节
- 卡片内直接显示 JSON 解析失败提示
- 保留“运行中实例需手动 stop/start 才能生效”的说明

#### Routing Targets

展示当前可用 provider 列表，用作辅助参考：

- provider id
- display name
- enabled 状态

这张卡片帮助用户确认默认 provider 去向，但不作为主编辑交互。

### 5. 底部固定操作栏

- 左侧显示当前配置摘要，例如：
  - `Anthropic -> Anthropic via glm-coding-id`
  - `127.0.0.1:18072 · Auto Start On`
- 右侧保留 `Cancel` 与主操作按钮
- 创建态主按钮：`Create Gateway`
- 编辑态主按钮：`Save Changes`

## 字段交互规则

### Default Provider

- 若 `providers` 非空，默认显示 picker
- 若编辑态中的 `defaultProviderId` 已不在列表中，插入一条只读语义的“当前值”选项，防止旧配置被静默清空
- 若当前没有任何 provider，则保留只读提示或空状态说明，不伪造可选值

### 协议字段

- `Inbound Protocol` 与 `Upstream Protocol` 使用菜单式 picker
- 保留对未知旧值的兼容显示，避免已有配置在编辑时丢失

### Routing JSON

- 保存前必须是合法 JSON object
- 非法时在卡片内与全局错误区同时反馈
- 不引入代码高亮或外部编辑器依赖

## 验证与错误反馈

- 保留整页底部错误卡片，用于提交级错误
- 针对 `Routing JSON` 补充局部错误提示
- `Listen Port` 校验继续要求 `1...65535`
- `Default Provider` 为空时给出明确错误，而不是泛化为“字段缺失”

## 视觉一致性约束

- 继续复用：
  - `DesignTokens`
  - `SurfaceCard`
  - `StatusPill`
- 不新增平行主题系统
- 不引入分步向导、Tab 或复杂动画
- 不新增右侧悬浮预览面板

## 窗口尺寸策略

- 窗口提升到与 Provider 表单接近的尺寸
- 目标尺寸约 `760 x 680`
- 采用“顶部固定 + 中间滚动 + 底部固定”的结构

## 测试策略

### 原生测试

补充 `FluxDeckNativeTests` 覆盖：

- Gateway 默认卡片元数据派生
- Provider/Protocol picker 的兼容文本逻辑
- Gateway 表单摘要文案和辅助状态文本的派生逻辑

### 手动回归重点

- Create Gateway 与 Edit Gateway 都能正常打开
- 无 provider、单 provider、多 provider 三种场景表现稳定
- 已存在未知协议值、未知 provider id 的编辑态不崩溃
- JSON 非法时错误提示清晰且不会提交

## 非目标

- 不修改后端 Gateway 数据模型
- 不调整 Gateway 列表页卡片结构
- 不接入代码高亮 JSON 编辑器
- 不扩展为多步骤配置向导
