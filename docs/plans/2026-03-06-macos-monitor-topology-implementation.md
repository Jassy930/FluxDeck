# FluxDeck macOS 监控台与路由拓扑改造 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将 `apps/desktop` 改造成以 `Monitor` 为首页、`Topology` 为独立可视化页面、`Resources / Settings` 为资源配置层的 macOS 风格桌面控制台。

**Architecture:** 继续基于现有 React + Vite 单页应用实现，先完成导航与页面骨架，再用小步 TDD 逐个替换首页内容区、监控卡片、图表容器与拓扑页骨架。样式层通过扩展 `tokens.css` 和 `app.css` 建立深色桌面化设计系统，后续可再抽离为更细粒度组件。

**Tech Stack:** React 19、TypeScript、Vite、Bun test、CSS variables、自定义 SVG / CSS 可视化。

---

### Task 1: 建立多页面导航骨架

**Files:**
- Modify: `apps/desktop/src/App.tsx`
- Modify: `apps/desktop/src/ui/layout/AppShell.tsx`
- Modify: `apps/desktop/src/App.test.tsx`

**Step 1: Write the failing test**

在 `apps/desktop/src/App.test.tsx` 新增断言：
- 默认显示 `Monitor`
- 侧边栏存在 `Monitor`、`Topology`、`Providers`、`Gateways`、`Logs`
- `Topology` 内容区初始不显示

**Step 2: Run test to verify it fails**

Run: `cd apps/desktop && bun test src/App.test.tsx`
Expected: FAIL，因当前界面仍为单页区块布局。

**Step 3: Write minimal implementation**

- 在 `App.tsx` 增加本地页面状态，如 `monitor | topology | providers | gateways | logs`
- 将 `sidebar` 链接改成页面切换控件
- 在主区域按当前页面切换对应内容

**Step 4: Run test to verify it passes**

Run: `cd apps/desktop && bun test src/App.test.tsx`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/desktop/src/App.tsx apps/desktop/src/ui/layout/AppShell.tsx apps/desktop/src/App.test.tsx
git commit -m "feat(desktop): add monitor and topology navigation shell"
```

### Task 2: 用失败测试驱动 Monitor 首页骨架

**Files:**
- Modify: `apps/desktop/src/App.test.tsx`
- Modify: `apps/desktop/src/App.tsx`
- Create: `apps/desktop/src/ui/monitor/MonitorPage.tsx`

**Step 1: Write the failing test**

新增断言首页包含：
- `Running Gateways`
- `Active Providers`
- `Requests / min`
- `P95 Latency`
- `Recent Alerts`
- `Gateway Runtime Board`

**Step 2: Run test to verify it fails**

Run: `cd apps/desktop && bun test src/App.test.tsx`
Expected: FAIL，因 `MonitorPage` 尚未存在。

**Step 3: Write minimal implementation**

- 新建 `MonitorPage.tsx`
- 返回静态结构化卡片骨架
- 在 `App.tsx` 中接入 `MonitorPage`

**Step 4: Run test to verify it passes**

Run: `cd apps/desktop && bun test src/App.test.tsx`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/desktop/src/App.tsx apps/desktop/src/App.test.tsx apps/desktop/src/ui/monitor/MonitorPage.tsx
git commit -m "feat(desktop): scaffold monitor dashboard page"
```

### Task 3: 提取监控指标卡组件

**Files:**
- Create: `apps/desktop/src/ui/monitor/MetricCard.tsx`
- Create: `apps/desktop/src/ui/monitor/MetricCard.test.tsx`
- Modify: `apps/desktop/src/ui/monitor/MonitorPage.tsx`

**Step 1: Write the failing test**

在 `MetricCard.test.tsx` 断言：
- 标题、数值、说明、趋势文本均可渲染
- 状态类型 class 会根据 `healthy | warning | error` 输出不同语义类名

**Step 2: Run test to verify it fails**

Run: `cd apps/desktop && bun test src/ui/monitor/MetricCard.test.tsx`
Expected: FAIL

**Step 3: Write minimal implementation**

- 新建 `MetricCard` 组件
- 接受 `label/value/helper/trend/tone`
- Monitor 首页改用该组件渲染总览卡

**Step 4: Run test to verify it passes**

Run: `cd apps/desktop && bun test src/ui/monitor/MetricCard.test.tsx`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/desktop/src/ui/monitor/MetricCard.tsx apps/desktop/src/ui/monitor/MetricCard.test.tsx apps/desktop/src/ui/monitor/MonitorPage.tsx
git commit -m "feat(desktop): add monitor metric cards"
```

### Task 4: 用静态 SVG / CSS 实现趋势图容器

**Files:**
- Create: `apps/desktop/src/ui/monitor/TrendPanel.tsx`
- Create: `apps/desktop/src/ui/monitor/TrendPanel.test.tsx`
- Modify: `apps/desktop/src/ui/monitor/MonitorPage.tsx`
- Modify: `apps/desktop/src/styles/app.css`

**Step 1: Write the failing test**

断言 `TrendPanel` 渲染：
- `Request Throughput`
- `Latency Trend`
- `1m / 5m / 15m / 1h` 切换标签
- 至少一个 `svg` 元素

**Step 2: Run test to verify it fails**

Run: `cd apps/desktop && bun test src/ui/monitor/TrendPanel.test.tsx`
Expected: FAIL

**Step 3: Write minimal implementation**

- 新建 `TrendPanel.tsx`
- 使用静态 `svg polyline/path` 先完成视觉骨架
- 在 `app.css` 中加入深色图表面板样式

**Step 4: Run test to verify it passes**

Run: `cd apps/desktop && bun test src/ui/monitor/TrendPanel.test.tsx`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/desktop/src/ui/monitor/TrendPanel.tsx apps/desktop/src/ui/monitor/TrendPanel.test.tsx apps/desktop/src/ui/monitor/MonitorPage.tsx apps/desktop/src/styles/app.css
git commit -m "feat(desktop): add monitor trend panel"
```

### Task 5: 增加 Recent Alerts 与事件流组件

**Files:**
- Create: `apps/desktop/src/ui/monitor/AlertFeed.tsx`
- Create: `apps/desktop/src/ui/monitor/AlertFeed.test.tsx`
- Modify: `apps/desktop/src/ui/monitor/MonitorPage.tsx`

**Step 1: Write the failing test**

断言 `AlertFeed`：
- 能渲染 `info/warning/error` 三种级别
- 错误项包含明显状态标签
- 空态时显示说明文案

**Step 2: Run test to verify it fails**

Run: `cd apps/desktop && bun test src/ui/monitor/AlertFeed.test.tsx`
Expected: FAIL

**Step 3: Write minimal implementation**

- 新建 `AlertFeed.tsx`
- 先用静态假数据渲染事件流
- 在首页底部接入组件

**Step 4: Run test to verify it passes**

Run: `cd apps/desktop && bun test src/ui/monitor/AlertFeed.test.tsx`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/desktop/src/ui/monitor/AlertFeed.tsx apps/desktop/src/ui/monitor/AlertFeed.test.tsx apps/desktop/src/ui/monitor/MonitorPage.tsx
git commit -m "feat(desktop): add monitor alert feed"
```

### Task 6: 用失败测试驱动 Topology 页面骨架

**Files:**
- Modify: `apps/desktop/src/App.test.tsx`
- Create: `apps/desktop/src/ui/topology/TopologyPage.tsx`
- Modify: `apps/desktop/src/App.tsx`

**Step 1: Write the failing test**

新增断言：
- 切换到 `Topology` 后显示 `Live Flow`
- 显示 `Gateways`、`Providers`、`Models`
- 显示 `Failure Path`

**Step 2: Run test to verify it fails**

Run: `cd apps/desktop && bun test src/App.test.tsx`
Expected: FAIL

**Step 3: Write minimal implementation**

- 新建 `TopologyPage.tsx`
- 提供顶部视图切换与主画布占位
- 在 `App.tsx` 中接入该页面

**Step 4: Run test to verify it passes**

Run: `cd apps/desktop && bun test src/App.test.tsx`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/desktop/src/App.tsx apps/desktop/src/App.test.tsx apps/desktop/src/ui/topology/TopologyPage.tsx
git commit -m "feat(desktop): scaffold topology page"
```

### Task 7: 拆出拓扑节点与路径基础组件

**Files:**
- Create: `apps/desktop/src/ui/topology/TopologyNode.tsx`
- Create: `apps/desktop/src/ui/topology/TopologyCanvas.tsx`
- Create: `apps/desktop/src/ui/topology/TopologyCanvas.test.tsx`
- Modify: `apps/desktop/src/ui/topology/TopologyPage.tsx`
- Modify: `apps/desktop/src/styles/app.css`

**Step 1: Write the failing test**

断言 `TopologyCanvas`：
- 渲染四层列标题：`Entrypoints / Gateways / Providers / Models`
- 渲染至少一条路径
- 渲染详情面板占位区域

**Step 2: Run test to verify it fails**

Run: `cd apps/desktop && bun test src/ui/topology/TopologyCanvas.test.tsx`
Expected: FAIL

**Step 3: Write minimal implementation**

- 新建 `TopologyNode.tsx` 与 `TopologyCanvas.tsx`
- 用静态样例布局完成四层节点和简单 SVG 连线
- 更新样式以形成深色画布感

**Step 4: Run test to verify it passes**

Run: `cd apps/desktop && bun test src/ui/topology/TopologyCanvas.test.tsx`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/desktop/src/ui/topology/TopologyNode.tsx apps/desktop/src/ui/topology/TopologyCanvas.tsx apps/desktop/src/ui/topology/TopologyCanvas.test.tsx apps/desktop/src/ui/topology/TopologyPage.tsx apps/desktop/src/styles/app.css
git commit -m "feat(desktop): add topology canvas skeleton"
```

### Task 8: 深色 macOS 视觉系统改造

**Files:**
- Modify: `apps/desktop/src/styles/tokens.css`
- Modify: `apps/desktop/src/styles/app.css`
- Modify: `apps/desktop/src/ui/layout/AppShell.tsx`
- Modify: `docs/USAGE.md`

**Step 1: Write the failing test**

在现有页面测试中新增断言：
- 顶部存在更明确的 `Monitor` 页面标题
- 顶栏和侧边栏存在 macOS 风格类名，如 `window-toolbar` 或类似命名
- 页面包含 `Topology` 导航入口

**Step 2: Run test to verify it fails**

Run: `cd apps/desktop && bun test src/App.test.tsx`
Expected: FAIL

**Step 3: Write minimal implementation**

- 重命名并扩展壳层 class
- 调整 token 为深色桌面体系
- 补齐 `docs/USAGE.md` 的页面说明

**Step 4: Run test to verify it passes**

Run: `cd apps/desktop && bun test src/App.test.tsx`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/desktop/src/styles/tokens.css apps/desktop/src/styles/app.css apps/desktop/src/ui/layout/AppShell.tsx docs/USAGE.md
git commit -m "feat(desktop): apply macos monitor visual system"
```

### Task 9: 全量验收与文档同步

**Files:**
- Modify: `docs/USAGE.md`
- Modify: `docs/plans/2026-03-06-macos-monitor-topology-design.md`
- Modify: `docs/plans/2026-03-06-macos-monitor-topology-implementation.md`

**Step 1: Run focused desktop tests**

Run: `cd apps/desktop && bun test`
Expected: PASS

**Step 2: Run production build**

Run: `cd apps/desktop && bun run build`
Expected: PASS

**Step 3: Run repo validation**

Run: `cargo test -q && ./scripts/e2e/smoke.sh`
Expected: PASS with `smoke ok`

**Step 4: Review docs and git status**

Run: `git status --short`
Expected: 仅包含本任务相关文件

**Step 5: Commit**

```bash
git add docs/USAGE.md docs/plans/2026-03-06-macos-monitor-topology-design.md docs/plans/2026-03-06-macos-monitor-topology-implementation.md apps/desktop/src
git commit -m "feat(desktop): add macos monitor and topology workspace"
```
