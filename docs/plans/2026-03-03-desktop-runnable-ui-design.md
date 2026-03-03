# FluxDeck 可运行桌面前端设计（Tauri 主线）

## 目标

将当前 `apps/desktop` 从“逻辑与测试占位工程”升级为可运行可见的桌面管理界面，支持本地启动后完成以下操作：

- 查看 Provider / Gateway / Logs
- 创建 Provider / Gateway
- 查看 Gateway 运行状态与错误

## 设计约束

- 前端只通过 `fluxd` Admin API 读写数据。
- 不复制后端业务逻辑到前端。
- JS/TS 工具链统一使用 `bun`。
- 保留现有 TDD 流程：先写失败测试，再写最小实现。

## 信息架构

页面采用单页管理台布局：

1. 顶部栏（Header）
- 显示应用名、Admin API 地址、全局刷新按钮。

2. 左侧导航（Sidebar）
- 三个锚点：`Providers`、`Gateways`、`Logs`。
- 仅用于定位区块，不引入路由复杂度。

3. 主内容区（Content）
- `Provider` 区块：列表 + 创建表单
- `Gateway` 区块：列表 + 创建表单 + 运行状态
- `Logs` 区块：最近请求日志列表

## 视觉与样式策略

- 使用轻量 design tokens（CSS 变量）统一颜色/间距/圆角/阴影。
- 保持桌面优先的两栏布局，窄宽度下自动堆叠。
- 状态颜色固定语义：
  - running: 绿色
  - stopped: 灰色
  - error: 红色

## 组件拆分

- `src/ui/layout/AppShell.tsx`
  - 负责 Header + Sidebar + 主内容栅格。
- `src/ui/providers/ProviderSection.tsx`
  - Provider 表单与列表。
- `src/ui/gateways/GatewaySection.tsx`
  - Gateway 表单、列表、运行状态标签。
- `src/ui/logs/LogSection.tsx`
  - Logs 列表与空态。
- `src/ui/common/*`
  - Button/Input/Tag/Notice 等复用基础组件。

## 数据流

- `App` 初始化时并发调用：
  - `listProviders`
  - `listGateways`
  - `listLogs`
- 提交 Provider/Gateway 表单后：
  - 调用对应 create API
  - 成功后触发一次最小刷新（重新加载三组数据）
- Gateway 列表读取 `runtime_status` 与 `last_error`，直接展示。

## 异常与状态处理

每个区块必须具备 4 态：

- `loading`: 首次加载或刷新中
- `empty`: 数据为空
- `error`: API 失败
- `success`: 正常展示

错误优先显示在区块顶部，不阻断其他区块渲染。

## 测试策略

- `App.test.tsx` 保留并扩展行为测试：
  - 首屏区块存在
  - 创建操作触发 API 调用与刷新
  - Gateway 状态/错误渲染逻辑
- 新增轻量组件测试，避免过度快照。
- 运行命令统一：`cd apps/desktop && bun run test`

## 验收标准

1. `apps/desktop` 可直接启动看到 UI（不再是 placeholder）。
2. 能通过页面创建 Provider/Gateway 并刷新。
3. Gateway 状态与错误可见。
4. `cargo test -q`、`cd apps/desktop && bun run test`、`./scripts/e2e/smoke.sh` 全通过。

