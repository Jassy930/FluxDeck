#!/usr/bin/env python3
import argparse
import json
import socket
import time
import urllib.error
import urllib.request
from typing import Any, Tuple


def pick_port() -> int:
    sock = socket.socket()
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    sock.close()
    return int(port)


def http_json(method: str, url: str, payload: Any | None = None) -> Tuple[int, Any]:
    data = None
    headers = {"content-type": "application/json"}
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")

    req = urllib.request.Request(url=url, data=data, method=method.upper(), headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            status = resp.getcode()
            raw = resp.read()
    except urllib.error.HTTPError as err:
        status = err.code
        raw = err.read()

    text = raw.decode("utf-8") if raw else ""
    body = json.loads(text) if text else {}
    return status, body


def post_with_retry(url: str, payload: Any, attempts: int = 30) -> Tuple[int, Any]:
    last_err = None
    for _ in range(attempts):
        try:
            return http_json("POST", url, payload)
        except urllib.error.URLError as err:
            last_err = err
            time.sleep(0.1)
    raise RuntimeError(f"request failed after retries: {url}, err={last_err}")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--admin-url", required=True)
    parser.add_argument("--upstream-base-url", required=True)
    args = parser.parse_args()

    admin_url = args.admin_url.rstrip("/")
    upstream_base_url = args.upstream_base_url.rstrip("/")
    suffix = str(int(time.time() * 1000))

    provider_id = f"provider_compat_{suffix}"
    provider_payload = {
        "id": provider_id,
        "name": "Compat Provider",
        "kind": "openai",
        "base_url": upstream_base_url,
        "api_key": "sk-compat",
        "models": ["gpt-4o-mini"],
        "enabled": True,
    }
    status, _ = http_json("POST", f"{admin_url}/admin/providers", provider_payload)
    require(status == 201, f"create provider failed, status={status}")

    gateways: dict[str, dict[str, Any]] = {}
    for mode in ("strict", "compatible", "permissive"):
        gateway_id = f"gateway_{mode}_{suffix}"
        gateway_port = pick_port()
        payload = {
            "id": gateway_id,
            "name": f"Gateway {mode}",
            "listen_host": "127.0.0.1",
            "listen_port": gateway_port,
            "inbound_protocol": "anthropic",
            "upstream_protocol": "openai",
            "protocol_config_json": {"compatibility_mode": mode},
            "default_provider_id": provider_id,
            "default_model": "claude-3-7-sonnet",
            "enabled": True,
        }
        status, _ = http_json("POST", f"{admin_url}/admin/gateways", payload)
        require(status == 201, f"create gateway({mode}) failed, status={status}")

        status, _ = http_json("POST", f"{admin_url}/admin/gateways/{gateway_id}/start", {})
        require(status == 200, f"start gateway({mode}) failed, status={status}")
        gateways[mode] = {"id": gateway_id, "port": gateway_port}

    strict_payload = {
        "model": "claude-3-7-sonnet",
        "messages": [{"role": "user", "content": "hello"}],
        "x_passthrough": {"trace_id": "strict-e2e"},
    }
    status, body = post_with_retry(
        f"http://127.0.0.1:{gateways['strict']['port']}/v1/messages",
        strict_payload,
    )
    require(status == 422, f"strict mode should reject extension, got status={status}")
    require(
        body.get("error", {}).get("type") == "capability_error",
        f"strict mode error type mismatch, body={body}",
    )

    compatible_payload = {
        "model": "claude-3-7-sonnet",
        "messages": [{"role": "user", "content": "hello"}],
    }
    status, body = post_with_retry(
        f"http://127.0.0.1:{gateways['compatible']['port']}/v1/messages/count_tokens",
        compatible_payload,
    )
    require(status == 200, f"compatible count_tokens expected 200, got status={status}")
    require(body.get("estimated") is True, f"compatible estimated mismatch, body={body}")
    require(
        body.get("notice") == "degraded_to_estimate",
        f"compatible notice mismatch, body={body}",
    )

    permissive_payload = {
        "model": "claude-3-7-sonnet",
        "messages": [{"role": "user", "content": "hello"}],
        "x_passthrough": {"trace_id": "perm-e2e"},
    }
    status, body = post_with_retry(
        f"http://127.0.0.1:{gateways['permissive']['port']}/v1/messages",
        permissive_payload,
    )
    require(status == 200, f"permissive mode expected 200, got status={status}")
    blocks = body.get("content") or []
    first_text = blocks[0].get("text") if blocks else None
    require(
        first_text == "passthrough-ok",
        f"permissive passthrough result mismatch, body={body}",
    )

    print("anthropic compat ok")


if __name__ == "__main__":
    main()
