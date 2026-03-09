# FluxDeck 本地运行手册

## 启动 fluxd

```bash
FLUXDECK_DB_PATH="$HOME/.fluxdeck/fluxdeck.db" \
FLUXDECK_ADMIN_ADDR="127.0.0.1:7777" \
cargo run -p fluxd
```

## 使用 fluxctl 创建 Provider

```bash
cargo run -p fluxctl -- --admin-url http://127.0.0.1:7777 provider create \
  --id provider_main \
  --name "Main" \
  --kind openai \
  --base-url https://api.openai.com/v1 \
  --api-key sk-xxx \
  --models gpt-4o-mini,gpt-4.1
```

## 创建并启动网关

```bash
cargo run -p fluxctl -- --admin-url http://127.0.0.1:7777 gateway create \
  --id gateway_main \
  --name "Gateway Main" \
  --listen-host 127.0.0.1 \
  --listen-port 18080 \
  --inbound-protocol openai \
  --upstream-protocol provider_default \
  --protocol-config-json '{"compatibility_mode":"compatible"}' \
  --default-provider-id provider_main \
  --default-model gpt-4o-mini \
  --auto-start true

cargo run -p fluxctl -- --admin-url http://127.0.0.1:7777 gateway start gateway_main
```

更新网关配置：

```bash
cargo run -p fluxctl -- --admin-url http://127.0.0.1:7777 gateway update gateway_main \
  --name "Gateway Main Updated" \
  --listen-host 127.0.0.1 \
  --listen-port 19090 \
  --inbound-protocol openai \
  --upstream-protocol provider_default \
  --protocol-config-json '{"compatibility_mode":"strict"}' \
  --default-provider-id provider_main \
  --default-model gpt-4.1-mini \
  --enabled true \
  --auto-start false
```

注意：更新只保存配置，不会热更新当前运行中的 Gateway；如需生效，请手动 stop/start。

## 调用网关

```bash
curl -X POST http://127.0.0.1:18080/v1/chat/completions \
  -H 'content-type: application/json' \
  -d '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"hello"}]}'
```
