# 2026-03-12 打包与分发调研记录

## 本次调研范围

围绕当前仓库现状，确认 FluxDeck 现阶段适合如何打包与分发，重点核对：

- 实际可交付产物有哪些
- 原生 macOS 壳是否已具备独立分发条件
- 是否已有签名、公证、安装器或发布自动化基础

## 结论摘要

### 1. 当前不是单一桌面应用，而是组合式产品

仓库现状由三部分组成：

- `fluxd`：本地后台服务
- `FluxDeckNative.app`：原生前端壳
- `fluxctl`：可选 CLI

原生壳当前默认连接 `http://127.0.0.1:7777`，并不会自行拉起 `fluxd`。因此直接分发 `.app` 不能形成完整安装体验。

### 2. 当前可做的只有开发者分发

目前已经有：

- `cargo` 构建 Rust 二进制
- `xcodebuild` 构建原生 macOS 壳
- `bun run build` 构建 Web 静态壳

但还没有：

- CI 发布链路
- DMG / PKG / ZIP 标准制品脚本
- Apple 签名与公证流程
- 原生壳内嵌 `fluxd`
- `launchd` 或 helper 进程管理

因此当前最多只适合做内部 alpha 或开发者预览分发。

### 3. 推荐主线是“原生壳 + 内嵌 fluxd”

由于仓库已明确暂停 Web 桌面壳主线开发，后续分发不应继续围绕 Electron / Tauri 或纯 Web 封装展开。

更合理的路线是：

- 先用分离制品完成最小开发者分发
- 再把 `fluxd` 内嵌进 `FluxDeckNative.app`
- 最后补签名、公证、DMG 与自动更新

## 建议动作

1. 新建一份“原生一体化分发设计”文档，明确 `fluxd` 生命周期、内嵌路径、日志、数据目录与端口策略
2. 增加最小发布脚本，至少能稳定产出 `fluxd`、`fluxctl`、`FluxDeckNative.app`
3. 后续再推进签名、公证和正式安装包

## 相关文档

- `docs/plans/2026-03-12-packaging-distribution-investigation.md`
