# FluxDeck

FluxDeck 是一个本地优先的 LLM Gateway、Provider 管理与流量观测工具，面向 macOS 使用场景。

它提供：

- `fluxd`：本地服务，负责 Admin API、Gateway 运行时与请求转发
- `fluxctl`：命令行管理工具，用于创建和维护 Provider / Gateway
- 原生桌面端：用于配置、观察和操作本地路由工作区

## 当前状态

FluxDeck 当前已经具备可用的本地代理管理能力，主线重心是原生桌面端。

- 原生桌面端优先：Provider、Gateway、运行状态、日志与流量视图已经接入
- `fluxd` 与 `fluxctl` 可作为稳定基础设施使用
- Web 技术栈桌面端仍保留，但当前不是新增功能主线

## 当前能力

你现在可以用 FluxDeck：

- 管理多个上游 Provider
  - 支持 `openai`、`anthropic` 等 provider kind
- 创建本地 Gateway
  - 支持 OpenAI 与 Anthropic 入站
  - 支持 OpenAI / Anthropic 上游转发
- 统一本地调用入口
  - 给 Claude Code、兼容 OpenAI 的工具或自定义脚本提供稳定本地端点
- 观察请求日志与基础流量指标
  - 查看请求状态、延迟、错误、token 使用与按 Gateway / Provider 聚合的概览
- 安全应用运行时配置
  - 当运行中的 Gateway 保存后确实发生配置变化，`fluxd` 会自动执行 `stop -> start`
  - 原生桌面端与 `fluxctl` 会提示是否已自动重启

## 适用场景

FluxDeck 适合这些本地工作流：

- 在一台机器上统一管理多个 LLM 上游和路由入口
- 为本地工具提供固定的 OpenAI / Anthropic 兼容地址
- 调试 Gateway 配置、模型映射与兼容模式
- 排查 Claude Code 或其他客户端在网关后的请求行为
- 观察最近流量、错误与请求日志

## 快速开始

### 1. 启动 `fluxd`

```bash
FLUXDECK_DB_PATH="$HOME/.fluxdeck/fluxdeck.db" \
FLUXDECK_ADMIN_ADDR="127.0.0.1:7777" \
cargo run -p fluxd
```

默认情况下，FluxDeck 使用本地 SQLite 数据库：

- 默认路径：`~/.fluxdeck/fluxdeck.db`
- 也可通过 `FLUXDECK_DB_PATH` 覆盖

### 2. 使用 `fluxctl` 创建 Provider

```bash
cargo run -p fluxctl -- --admin-url http://127.0.0.1:7777 provider create \
  --id provider_main \
  --name "Main Provider" \
  --kind openai \
  --base-url https://api.openai.com/v1 \
  --api-key sk-xxx \
  --models gpt-4o-mini,gpt-4.1
```

### 3. 创建 Gateway

```bash
cargo run -p fluxctl -- --admin-url http://127.0.0.1:7777 gateway create \
  --id gateway_main \
  --name "Gateway Main" \
  --listen-host 127.0.0.1 \
  --listen-port 18080 \
  --inbound-protocol openai \
  --upstream-protocol provider_default \
  --default-provider-id provider_main \
  --default-model gpt-4o-mini \
  --enabled true \
  --auto-start true
```

### 4. 打开桌面端

原生桌面端是当前主线体验。

如果你在本仓库中进行本地开发，也可以启动 Web 桌面端：

```bash
cd apps/desktop
bun install
bun run dev
```

默认地址：

- `http://127.0.0.1:5173`

## Gateway 更新行为

FluxDeck 现在会自动处理运行中实例的配置应用问题：

- 如果 Gateway 当前处于 `running`
- 并且你保存后的配置与原配置确实不同
- `fluxd` 会自动执行一次 `stop -> start`

如果 Gateway 当前未运行，则只保存配置，不会自动启动。

## 重要文档

如果你想继续深入，优先看这些文档：

- [使用说明](./docs/USAGE.md)
- [本地运行手册](./docs/ops/local-runbook.md)
- [Admin API 契约](./docs/contracts/admin-api-v1.md)
- [Anthropic 兼容 E2E 说明](./docs/testing/anthropic-compat-e2e.md)
- [文档总览](./docs/README.md)

## 提交前验证

```bash
cargo test -q
cd apps/desktop && bun run test
./scripts/e2e/smoke.sh
```

如果遇到工具链切换后 `cargo test` 出现 `E0463 can't find crate`，先执行：

```bash
cargo clean
```
