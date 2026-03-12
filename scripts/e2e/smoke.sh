#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUN_DIR="$(mktemp -d /tmp/fluxdeck-smoke.XXXXXX)"

cleanup() {
  if [[ -n "${FLUXD_PID:-}" ]]; then
    kill "$FLUXD_PID" >/dev/null 2>&1 || true
    wait "$FLUXD_PID" >/dev/null 2>&1 || true
  fi
  if [[ -n "${MOCK_PID:-}" ]]; then
    kill "$MOCK_PID" >/dev/null 2>&1 || true
    wait "$MOCK_PID" >/dev/null 2>&1 || true
  fi
  rm -rf "$RUN_DIR"
}
trap cleanup EXIT

pick_port() {
  uv run python -c "import socket; s=socket.socket(); s.bind(('127.0.0.1',0)); print(s.getsockname()[1]); s.close()"
}

ADMIN_PORT="$(pick_port)"
UPSTREAM_PORT="$(pick_port)"
GATEWAY_PORT="$(pick_port)"

uv run python "$ROOT_DIR/scripts/e2e/mock_openai.py" --host 127.0.0.1 --port "$UPSTREAM_PORT" >"$RUN_DIR/mock.log" 2>&1 &
MOCK_PID=$!

FLUXDECK_DB_PATH="$RUN_DIR/fluxdeck.db" \
FLUXDECK_ADMIN_ADDR="127.0.0.1:${ADMIN_PORT}" \
cargo run -q -p fluxd >"$RUN_DIR/fluxd.log" 2>&1 &
FLUXD_PID=$!

# 提前构建，避免首次编译导致就绪等待不足
cargo build -q -p fluxd -p fluxctl

ready=0
for _ in $(seq 1 120); do
  if curl -fsS "http://127.0.0.1:${ADMIN_PORT}/admin/providers" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 0.5
done

if [[ "$ready" -ne 1 ]]; then
  echo "admin api not ready, fluxd log:" >&2
  cat "$RUN_DIR/fluxd.log" >&2 || true
  exit 1
fi

cargo run -q -p fluxctl -- --admin-url "http://127.0.0.1:${ADMIN_PORT}" provider create \
  --id provider_smoke \
  --name "Smoke Provider" \
  --kind openai \
  --base-url "http://127.0.0.1:${UPSTREAM_PORT}/v1" \
  --api-key sk-smoke \
  --models gpt-4o-mini >/dev/null

cargo run -q -p fluxctl -- --admin-url "http://127.0.0.1:${ADMIN_PORT}" gateway create \
  --id gateway_smoke \
  --name "Smoke Gateway" \
  --listen-host 127.0.0.1 \
  --listen-port "$GATEWAY_PORT" \
  --inbound-protocol openai \
  --default-provider-id provider_smoke \
  --default-model gpt-4o-mini >/dev/null

cargo run -q -p fluxctl -- --admin-url "http://127.0.0.1:${ADMIN_PORT}" gateway start gateway_smoke >/dev/null

RESPONSE="$(curl -fsS -X POST "http://127.0.0.1:${GATEWAY_PORT}/v1/chat/completions" \
  -H 'content-type: application/json' \
  -d '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"hello"}]}' )"

echo "$RESPONSE" | grep -q 'chatcmpl_mock_001'

uv run python "$ROOT_DIR/scripts/e2e/anthropic_compat.py" \
  --admin-url "http://127.0.0.1:${ADMIN_PORT}" \
  --upstream-base-url "http://127.0.0.1:${UPSTREAM_PORT}/v1"

echo "smoke ok"
