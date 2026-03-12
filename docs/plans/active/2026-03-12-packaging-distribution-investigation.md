# FluxDeck 打包与分发调研

## 目标

基于当前仓库事实，判断 FluxDeck 现阶段适合如何打包与分发，并明确进入“可对外安装”前还缺哪些能力。

## 当前仓库事实

### 1. 当前实际产物

- `crates/fluxd`：Rust 本地服务，负责 Admin API、SQLite 迁移与 Gateway 运行时
- `crates/fluxctl`：Rust CLI，负责 Provider / Gateway / Logs 管理
- `apps/desktop`：React + Vite 的 Web 桌面壳，当前只提供 `vite build` 的静态产物
- `apps/desktop-macos-native`：SwiftUI 原生 macOS 壳，当前可通过 `xcodebuild` 构建与测试

### 2. 当前主线产品形态

仓库说明已经明确：当前阶段暂停 `apps/desktop/` 的新增功能开发，优先投入 `apps/desktop-macos-native` 原生桌面端。因此“桌面端分发”应以 macOS 原生壳为主线，而不是继续围绕 Web 壳做 Electron / Tauri 类封装。

### 3. 当前运行模型

- `fluxd` 默认监听 `127.0.0.1:7777`
- `fluxd` 默认数据库路径为 `~/.fluxdeck/fluxdeck.db`
- `fluxctl` 默认连接 `http://127.0.0.1:7777`
- 原生 macOS 壳默认连接 `http://127.0.0.1:7777`

这说明当前产品并不是“单一桌面应用”，而是“本地后台服务 + 原生前端壳 + 可选 CLI”的组合。

### 4. 当前已存在的构建能力

- Rust 侧已有标准 `cargo` 构建与测试能力
- 原生 macOS 壳已有 Xcode 工程、Bundle Identifier、版本号与 Release 配置
- Web 壳已有 `bun run build`

原生壳当前已确认的 Xcode 配置：

- `PRODUCT_BUNDLE_IDENTIFIER = com.fluxdeck.native`
- `MARKETING_VERSION = 1.0`
- `CURRENT_PROJECT_VERSION = 1`
- `MACOSX_DEPLOYMENT_TARGET = 13.0`
- `CODE_SIGN_STYLE = Automatic`

### 5. 当前缺失的发布能力

仓库中未发现以下能力：

- CI 发布流水线
- GitHub Actions 或其他 release workflow
- `cargo-dist`、`cargo-bundle`、DMG/PKG 生成脚本
- macOS 签名、公证、发布证书说明
- 原生壳内嵌 `fluxd` 或自动拉起 `fluxd` 的机制
- `launchd` plist、登录项、helper app、后台守护进程管理
- 自动更新方案（如 Sparkle）
- 安装器文档与卸载文档
- 自定义 entitlements、显式 Info.plist、App 图标资源或额外打包资源文件

## 关键结论

### 结论 1：现在不能只发布一个原生 `.app`

虽然 `apps/desktop-macos-native` 已经能通过 Xcode 构建，但它只是一个消费 Admin API 的前端壳，当前并不会自行启动或管理 `fluxd`。如果直接分发 `.app`：

- 用户首次打开后大概率只能看到连不上 `127.0.0.1:7777` 的壳
- 仍需要额外安装并手动启动 `fluxd`
- 用户还需要知道数据库位置、服务地址和 CLI 初始化流程

这对内部开发验证还可以接受，对正式分发不可接受。

### 结论 2：当前最小可分发单元其实是“三件套”

按仓库现状，真正能运行的最小交付物是：

1. `fluxd`
2. `FluxDeckNative.app`
3. 可选的 `fluxctl`

如果不把这三者的关系打包成统一安装体验，那么“分发”只能算开发者交付，不算终端用户交付。

### 结论 3：Web 壳不适合作为当前主分发方向

`apps/desktop` 当前更接近开发辅助界面：

- 有 `vite build`，但没有桌面容器
- 仓库优先级已降级
- 若继续做 Electron / Tauri，会与“原生桌面端优先”直接冲突

因此短期不建议再投入 Web 桌面封装分发。

## 可选方案

### 方案 A：开发者分发

形态：

- 单独发布 `fluxd`
- 单独发布 `fluxctl`
- 单独发布 `FluxDeckNative.app`
- 使用文档指导用户手动启动服务与应用

优点：

- 实现最简单
- 不需要马上处理 app 内嵌服务、进程托管、签名复杂度
- 适合当前仓库还在快速迭代阶段的内部试用

缺点：

- 用户体验差
- 安装与升级步骤分裂
- 很难面向普通用户

适用阶段：

- 当前立刻可做
- 仅建议作为内部 alpha / 开发者预览

### 方案 B：macOS 一体化桌面应用

形态：

- 以 `FluxDeckNative.app` 为主入口
- 将 `fluxd` 作为内嵌二进制放入 App Bundle
- App 首次启动时负责创建数据目录、拉起本地 `fluxd`、检测健康状态
- `fluxctl` 不进入首发安装包，保留给高级用户单独下载

优点：

- 符合当前“原生桌面端优先”的产品方向
- 能把“本地服务 + 前端壳”收敛为一次安装
- 用户只需打开一个 `.app`

缺点：

- 需要补齐进程托管与生命周期管理
- 需要处理 `fluxd` 内嵌路径、日志、崩溃恢复、端口占用
- 需要做 macOS 签名、公证与 DMG/ZIP 发布

适用阶段：

- 最适合作为下一个正式分发里程碑
- 也是本项目最推荐的主路线

### 方案 C：安装器优先

形态：

- 用 `.pkg` 安装 `fluxd`、CLI、原生壳
- 通过 `launchd` 安装系统级或用户级服务
- App 仅作为控制台 UI

优点：

- 服务管理更稳定
- 对后台守护进程、开机启动、升级控制更强

缺点：

- 设计和维护成本最高
- 对当前 MVP 阶段明显过重
- 卸载、权限、系统差异处理更复杂

适用阶段：

- 不建议现在做
- 可留到需要长期驻留服务和企业内部分发时再评估

## 推荐方案：先 A，尽快转 B

### 阶段 1：开发者预览分发

目标：先把“别人能装起来”这件事做出来，但不承诺最终安装体验。

建议交付：

- `fluxd` 的 macOS 二进制压缩包
- `fluxctl` 的 macOS 二进制压缩包
- `FluxDeckNative.app` 的 Release 构建产物
- 一份明确的安装 / 启动 / 升级 / 卸载文档

最低要求：

- 区分 `arm64` 与 `x86_64`，或直接构建 Universal 版本
- 固化版本号、产物命名和校验方式
- 文档明确说明“原生壳依赖本地 `fluxd`”

### 阶段 2：原生一体化 Beta

目标：让普通 macOS 用户通过一个安装包完成使用。

必须补齐：

1. 原生壳内嵌 `fluxd`
2. App 启动时自动检查并拉起 `fluxd`
3. App 退出时是否保活 `fluxd` 的策略
4. 数据目录从 `~/.fluxdeck` 迁移到更标准的 `Application Support`
5. 端口占用与健康检查提示
6. 签名、公证、DMG/ZIP 发布

阶段 2 完成后，才可以称为真正意义上的“桌面应用分发”。

### 阶段 3：稳定版分发

可在 Beta 稳定后追加：

- 自动更新
- 崩溃恢复与诊断导出
- 可选 CLI 独立下载
- 更标准的卸载与数据保留策略

## 进入方案 B 前的实现缺口

### 产品与架构缺口

- 需要明确 `fluxd` 是随 app 生命周期运行，还是作为独立后台服务运行
- 需要明确用户是否仍可手动配置远端 Admin API
- 需要明确 CLI 在发布体系中的位置，是“开发者工具”还是“正式附带组件”

### 工程缺口

- 为 `fluxd` 增加发布构建脚本
- 为 Xcode 工程增加 Archive / Export 流程脚本
- 处理 Rust 二进制嵌入 `.app/Contents/Resources` 或其他稳定位置
- 在 Swift 侧增加子进程启动、健康探测、错误提示和日志查看
- 处理 app sandbox / hardened runtime / 网络权限评估

### 发布缺口

- Apple Developer 签名配置
- notarization 流程
- DMG 或 ZIP 制品标准
- 版本清单与 release note 模板

## 建议的下一步执行顺序

1. 先补一份正式的分发设计文档，专门决定 `fluxd` 的嵌入方式与生命周期策略
2. 再为方案 A 建一个最小发布脚本，把 `fluxd`、`fluxctl`、`FluxDeckNative.app` 产物固定化
3. 然后进入方案 B，把原生壳做成真正的一体化桌面应用
4. 方案 B 稳定后，再引入签名、公证、DMG 与自动更新

## 最终判断

以 2026-03-12 当前仓库状态来看：

- “内部开发者分发”已经可以开始做
- “面向普通用户的一键安装分发”还不能做
- 最正确的主线不是 Web 封装，而是原生 macOS 壳整合内嵌 `fluxd`
- 如果现在就要开始推进，推荐先补“原生一体化分发设计”，再做最小发布脚本
