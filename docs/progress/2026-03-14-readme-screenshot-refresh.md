# 2026-03-14 README 截图与内容刷新

## 目标

把用户提供的最新原生端界面截图纳入仓库，并将根目录 `README.md` 刷新为与当前项目阶段一致的项目首页。

## 调整内容

- 新增 README 静态资源：
  - `docs/assets/readme/fluxdeck-native-traffic-2026-03-14.jpeg`
- 在 `README.md` 顶部加入原生桌面端 `Traffic` 工作台截图
- 重新表述当前项目状态：
  - 原生桌面端 `apps/desktop-macos-native` 是当前主线
  - `fluxd` / `fluxctl` 是稳定基础设施
  - `apps/desktop` Web 桌面端暂停新增功能开发
- 补充当前已落地能力：
  - 多 Provider 有序链路
  - Gateway 级健康状态
  - 请求级故障切流
  - `Traffic` 按模型 token 趋势
  - `Topology` Sankey 主舞台
- 快速开始示例同步纳入 `--route-target` 能力说明
- 文档入口补齐 `docs/product/current-state.md` 与 `ARCHITECTURE.md`

## 结果

- README 不再停留在“基础代理可用”的旧描述，而是能准确反映 2026-03-14 的当前产品状态
- 新使用者进入仓库后，可以直接看到当前原生端界面与主线能力，而不需要先翻多篇进展文档
- 截图资源已进入仓库稳定路径，后续可以继续在 README 或其他文档中复用
