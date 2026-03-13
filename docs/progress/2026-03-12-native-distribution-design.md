# 2026-03-12 原生正式分发设计记录

## 本次工作

围绕 FluxDeck 面向普通 macOS 用户的一键安装分发，整理了一份待定设计方案，重点固化了以下边界：

- 目标用户为普通用户
- 首版正式分发追求一键安装
- 后台服务为常驻模式
- 不支持远端 Admin API
- 原生 App 仅作为本机控制台

## 当前结论

当前推荐但尚未立项执行的主方向为：

- `FluxDeck.pkg`
- 每用户 `LaunchAgent`
- 本机常驻 `fluxd`
- `FluxDeck.app` 控制台

该方案当前只作为待定设计保存在 `docs/plans/` 中，后续随项目进展继续讨论和修订。

## 当前明确保留的待定项

- `LaunchAgent` 的安装、升级与回滚策略
- App 内“服务不可用恢复页”和“诊断页”的信息边界

## 相关文档

- `docs/plans/active/2026-03-12-native-distribution-design.md`
