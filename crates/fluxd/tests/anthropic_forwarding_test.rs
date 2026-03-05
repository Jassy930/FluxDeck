use std::net::SocketAddr;

use axum::{extract::Json, response::IntoResponse, routing::post, Router};
use fluxd::http::anthropic_routes::{build_anthropic_router, AnthropicRouteState};
use fluxd::storage::migrate::run_migrations;
use serde_json::{json, Value};
use tokio::net::TcpListener;

#[tokio::test]
async fn forwards_anthropic_messages_to_openai_upstream() {
    let upstream = spawn_upstream_mock().await;
    let gateway = setup_gateway_with_provider_base_url(format!("http://{}/v1", upstream.addr)).await;

    let resp = reqwest::Client::new()
        .post(format!("http://{}/v1/messages", gateway.addr))
        .json(&json!({
            "model": "claude-3-7-sonnet",
            "max_tokens": 128,
            "messages": [{"role": "user", "content": "hello"}]
        }))
        .send()
        .await
        .expect("call gateway");

    assert_eq!(resp.status(), reqwest::StatusCode::OK);

    let body: Value = resp.json().await.expect("decode gateway response");
    assert_eq!(body["type"], "message");
    assert_eq!(body["role"], "assistant");
    assert_eq!(body["content"][0]["type"], "text");
    assert_eq!(body["content"][0]["text"], "pong");
    assert!(body.get("id").is_some());
}

#[tokio::test]
async fn maps_openai_tool_calls_to_anthropic_tool_use_blocks() {
    let upstream = spawn_upstream_tool_call_mock().await;
    let gateway = setup_gateway_with_provider_base_url(format!("http://{}/v1", upstream.addr)).await;

    let resp = reqwest::Client::new()
        .post(format!("http://{}/v1/messages", gateway.addr))
        .json(&json!({
            "model": "claude-3-7-sonnet",
            "max_tokens": 128,
            "messages": [{"role": "user", "content": "天气如何"}],
            "tools": [{
                "name": "lookup_weather",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "city": {"type": "string"}
                    },
                    "required": ["city"]
                }
            }]
        }))
        .send()
        .await
        .expect("call gateway");

    assert_eq!(resp.status(), reqwest::StatusCode::OK);

    let body: Value = resp.json().await.expect("decode gateway response");
    assert_eq!(body["stop_reason"], "tool_use");
    assert_eq!(body["content"][0]["type"], "tool_use");
    assert_eq!(body["content"][0]["id"], "call_weather_001");
    assert_eq!(body["content"][0]["name"], "lookup_weather");
    assert_eq!(body["content"][0]["input"]["city"], "Hangzhou");
}

#[tokio::test]
async fn wraps_non_object_tool_call_arguments_into_object_input() {
    let upstream = spawn_upstream_tool_call_array_args_mock().await;
    let gateway = setup_gateway_with_provider_base_url(format!("http://{}/v1", upstream.addr)).await;

    let resp = reqwest::Client::new()
        .post(format!("http://{}/v1/messages", gateway.addr))
        .json(&json!({
            "model": "claude-3-7-sonnet",
            "max_tokens": 128,
            "messages": [{"role": "user", "content": "请查询城市列表"}],
            "tools": [{
                "name": "lookup_weather",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "cities": {
                            "type": "array",
                            "items": {"type": "string"}
                        }
                    }
                }
            }]
        }))
        .send()
        .await
        .expect("call gateway");

    assert_eq!(resp.status(), reqwest::StatusCode::OK);

    let body: Value = resp.json().await.expect("decode gateway response");
    assert_eq!(body["content"][0]["type"], "tool_use");
    assert!(body["content"][0]["input"].is_object());
    assert_eq!(body["content"][0]["input"]["_value"][0], "Hangzhou");
    assert_eq!(body["content"][0]["input"]["_value"][1], "Shanghai");
}

#[tokio::test]
async fn returns_bad_request_for_local_openai_encoding_failure() {
    let gateway = setup_gateway_with_provider_base_url("http://127.0.0.1:9/v1".to_string()).await;

    let resp = reqwest::Client::new()
        .post(format!("http://{}/v1/messages", gateway.addr))
        .json(&json!({
            "model": "claude-3-7-sonnet",
            "max_tokens": 128,
            "messages": [{"role": "user", "content": "hello"}],
            "tools": [{
                "name": "broken_missing_input_schema"
            }]
        }))
        .send()
        .await
        .expect("call gateway");

    assert_eq!(resp.status(), reqwest::StatusCode::BAD_REQUEST);

    let body: Value = resp.json().await.expect("decode gateway response");
    assert_eq!(body["type"], "error");
    assert_eq!(body["error"]["type"], "invalid_request_error");
    assert!(
        body["error"]["message"]
            .as_str()
            .expect("error message as string")
            .contains("tools[0].input_schema")
    );
}

#[tokio::test]
async fn surfaces_upstream_error_message_for_nonstandard_error_shape() {
    let upstream = spawn_upstream_nonstandard_error_mock().await;
    let gateway = setup_gateway_with_provider_base_url(format!("http://{}/v1", upstream.addr)).await;

    let resp = reqwest::Client::new()
        .post(format!("http://{}/v1/messages", gateway.addr))
        .json(&json!({
            "model": "qwen3-coder-plus",
            "max_tokens": 128,
            "messages": [{"role": "user", "content": "hello"}]
        }))
        .send()
        .await
        .expect("call gateway");

    assert_eq!(resp.status(), reqwest::StatusCode::BAD_REQUEST);

    let body: Value = resp.json().await.expect("decode gateway response");
    assert_eq!(body["error"]["type"], "api_error");
    assert_eq!(
        body["error"]["message"],
        "invalid payload: unsupported content block"
    );
}

struct SpawnedServer {
    addr: SocketAddr,
}

async fn spawn_upstream_mock() -> SpawnedServer {
    let app = Router::new().route("/v1/chat/completions", post(upstream_chat_completions));
    spawn_gateway(app).await
}

async fn spawn_upstream_tool_call_mock() -> SpawnedServer {
    let app = Router::new().route("/v1/chat/completions", post(upstream_chat_completions_with_tool_calls));
    spawn_gateway(app).await
}

async fn spawn_upstream_tool_call_array_args_mock() -> SpawnedServer {
    let app = Router::new().route(
        "/v1/chat/completions",
        post(upstream_chat_completions_with_tool_calls_array_arguments),
    );
    spawn_gateway(app).await
}

async fn spawn_upstream_nonstandard_error_mock() -> SpawnedServer {
    let app = Router::new().route(
        "/v1/chat/completions",
        post(upstream_chat_completions_nonstandard_error),
    );
    spawn_gateway(app).await
}

async fn spawn_gateway(app: Router) -> SpawnedServer {
    let listener = TcpListener::bind("127.0.0.1:0").await.expect("bind random port");
    let addr = listener.local_addr().expect("read listener addr");

    tokio::spawn(async move {
        axum::serve(listener, app).await.expect("serve app");
    });

    SpawnedServer { addr }
}

async fn setup_gateway_with_provider_base_url(base_url: String) -> SpawnedServer {
    let pool = sqlx::SqlitePool::connect("sqlite::memory:")
        .await
        .expect("connect sqlite memory db");
    run_migrations(&pool).await.expect("run migrations");

    sqlx::query(
        "INSERT INTO providers (id, name, kind, base_url, api_key, enabled) VALUES (?1, ?2, ?3, ?4, ?5, 1)",
    )
    .bind("provider_openai")
    .bind("OpenAI Upstream")
    .bind("openai")
    .bind(base_url)
    .bind("sk-upstream")
    .execute(&pool)
    .await
    .expect("insert provider");

    sqlx::query(
        "INSERT INTO gateways (id, name, listen_host, listen_port, inbound_protocol, upstream_protocol, default_provider_id, default_model, enabled) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, 1)",
    )
    .bind("gw_anthropic")
    .bind("Gateway Anthropic")
    .bind("127.0.0.1")
    .bind(18889_i64)
    .bind("anthropic")
    .bind("openai")
    .bind("provider_openai")
    .bind("gpt-4o-mini")
    .execute(&pool)
    .await
    .expect("insert gateway");

    let app = build_anthropic_router(AnthropicRouteState::new(pool, "gw_anthropic"));
    spawn_gateway(app).await
}

async fn upstream_chat_completions(Json(payload): Json<Value>) -> impl IntoResponse {
    assert_eq!(payload["messages"][0]["role"], "user");
    assert_eq!(payload["messages"][0]["content"], "hello");

    Json(json!({
        "id": "chatcmpl_mock_001",
        "object": "chat.completion",
        "model": payload["model"],
        "choices": [
            {
                "index": 0,
                "message": {"role": "assistant", "content": "pong"},
                "finish_reason": "stop"
            }
        ],
        "usage": {
            "prompt_tokens": 10,
            "completion_tokens": 1,
            "total_tokens": 11
        }
    }))
}

async fn upstream_chat_completions_with_tool_calls(Json(payload): Json<Value>) -> impl IntoResponse {
    assert_eq!(payload["messages"][0]["role"], "user");
    assert_eq!(payload["messages"][0]["content"], "天气如何");
    assert_eq!(payload["tools"][0]["function"]["name"], "lookup_weather");

    Json(json!({
        "id": "chatcmpl_mock_tool_001",
        "object": "chat.completion",
        "model": payload["model"],
        "choices": [
            {
                "index": 0,
                "message": {
                    "role": "assistant",
                    "content": Value::Null,
                    "tool_calls": [
                        {
                            "id": "call_weather_001",
                            "type": "function",
                            "function": {
                                "name": "lookup_weather",
                                "arguments": "{\"city\":\"Hangzhou\"}"
                            }
                        }
                    ]
                },
                "finish_reason": "tool_calls"
            }
        ],
        "usage": {
            "prompt_tokens": 25,
            "completion_tokens": 8,
            "total_tokens": 33
        }
    }))
}

async fn upstream_chat_completions_with_tool_calls_array_arguments(
    Json(payload): Json<Value>,
) -> impl IntoResponse {
    assert_eq!(payload["messages"][0]["role"], "user");
    assert_eq!(payload["messages"][0]["content"], "请查询城市列表");
    assert_eq!(payload["tools"][0]["function"]["name"], "lookup_weather");

    Json(json!({
        "id": "chatcmpl_mock_tool_002",
        "object": "chat.completion",
        "model": payload["model"],
        "choices": [
            {
                "index": 0,
                "message": {
                    "role": "assistant",
                    "content": Value::Null,
                    "tool_calls": [
                        {
                            "id": "call_weather_002",
                            "type": "function",
                            "function": {
                                "name": "lookup_weather",
                                "arguments": "[\"Hangzhou\",\"Shanghai\"]"
                            }
                        }
                    ]
                },
                "finish_reason": "tool_calls"
            }
        ],
        "usage": {
            "prompt_tokens": 25,
            "completion_tokens": 8,
            "total_tokens": 33
        }
    }))
}

async fn upstream_chat_completions_nonstandard_error(_: Json<Value>) -> impl IntoResponse {
    (
        reqwest::StatusCode::BAD_REQUEST,
        Json(json!({
            "msg": "invalid payload: unsupported content block",
            "code": "BadRequest"
        })),
    )
}
