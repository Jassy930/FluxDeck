# 2026-03-11 anthropic base_url 归一化排查

## 现象

- 用户反馈：Gateway `GLMGLM` 配置为 `anthropic -> anthropic`，在 Claude Code 中发消息无反馈，也没有报错
- `request_logs` 中最近请求显示：
  - `gateway_id=GLMGLM`
  - `inbound_protocol=anthropic`
  - `upstream_protocol=anthropic`
  - `model_requested=claude-sonnet-4-6`
  - `model_effective=GLM-5`
  - `status_code=200`

## 根因

- 运行中的 Provider `glm-coding-id` 配置为：
  - `kind=anthropic`
  - `base_url=https://open.bigmodel.cn/api/anthropic`
- `AnthropicClient` 旧逻辑直接拼接：
  - `base_url + "/messages"`
  - `base_url + "/messages/count_tokens"`
- 因此实际请求被发往：
  - `https://open.bigmodel.cn/api/anthropic/messages`
  - `https://open.bigmodel.cn/api/anthropic/messages/count_tokens`
- 该错误路径会返回 HTTP `200`，但 body 是业务错误：

```json
{"code":500,"msg":"404_NOT_FOUND","success":false}
```

- Claude Code 侧因此拿到“看起来成功、实际上不是 Anthropic message/SSE”的响应，表现为无反馈、无显式报错

## 证据

- 直接请求错误路径：
  - `https://open.bigmodel.cn/api/anthropic/messages`
  - 返回 `{"code":500,"msg":"404_NOT_FOUND","success":false}`
- 直接请求正确路径：
  - `https://open.bigmodel.cn/api/anthropic/v1/messages`
  - 返回合法 Anthropic `message`
- `count_tokens` 也受相同路径问题影响，旧行为会在网关侧表现为：
  - `502`
  - `upstream count_tokens response missing \`input_tokens\``

## 修复

- 在 `crates/fluxd/src/upstream/anthropic_client.rs` 增加 URL 归一化：
  - 如果 `base_url` 未以 `/v1` 结尾，自动补 `/v1`
  - 同时兼容：
    - `https://host/api/anthropic`
    - `https://host/api/anthropic/v1`

## 验证

已执行：

```bash
cargo test -p fluxd --test anthropic_native_base_url_test -q
cargo test -p fluxd upstream::anthropic_client --lib -q
```

结果：

- 新增回归测试 3 项通过
- `AnthropicClient` URL helper 单测通过

## 现场处置建议

- 若本地运行中的 `fluxd` 仍是旧二进制，需要重启后修复才会生效
- 在未升级二进制前，临时 workaround 是把 Provider `base_url` 改成显式带 `/v1`：
  - `https://open.bigmodel.cn/api/anthropic/v1`
- 修改后需要对应 Gateway 执行 `stop -> start`
