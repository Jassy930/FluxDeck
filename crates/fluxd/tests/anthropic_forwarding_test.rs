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
async fn anthropic_forwarding_records_effective_model_and_usage_fields() {
    let upstream = spawn_upstream_mock().await;
    let (gateway, pool) =
        setup_gateway_with_provider_base_url_and_pool(format!("http://{}/v1", upstream.addr))
            .await;

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

    let log = latest_request_log(&pool).await;
    assert_eq!(log.inbound_protocol.as_deref(), Some("anthropic"));
    assert_eq!(log.upstream_protocol.as_deref(), Some("openai"));
    assert!(log.model_effective.is_some());
    assert_eq!(log.input_tokens, Some(10));
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

#[tokio::test]
async fn rewrites_model_with_mapping_rule_before_forwarding() {
    let upstream = spawn_upstream_model_rewrite_mock().await;
    let gateway = setup_gateway_with_provider_base_url_and_protocol_config(
        format!("http://{}/v1", upstream.addr),
        json!({
            "model_mapping": {
                "rules": [
                    {"from": "claude-*", "to": "qwen3-coder-plus"}
                ]
            }
        }),
    )
    .await;

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
    assert_eq!(body["model"], "qwen3-coder-plus");
}

#[tokio::test]
async fn falls_back_to_fallback_model_when_rule_not_matched() {
    let upstream = spawn_upstream_model_rewrite_mock().await;
    // 不设置 default_model，这样 fallback_model 才会被使用
    let gateway = setup_gateway_with_provider_base_url_and_protocol_config_no_default_model(
        format!("http://{}/v1", upstream.addr),
        json!({
            "model_mapping": {
                "rules": [
                    {"from": "claude-*", "to": "qwen3-coder-plus"}
                ],
                "fallback_model": "qwen3-coder-plus"
            }
        }),
    )
    .await;

    let resp = reqwest::Client::new()
        .post(format!("http://{}/v1/messages", gateway.addr))
        .json(&json!({
            "model": "unknown-model",
            "max_tokens": 128,
            "messages": [{"role": "user", "content": "hello"}]
        }))
        .send()
        .await
        .expect("call gateway");

    assert_eq!(resp.status(), reqwest::StatusCode::OK);
    let body: Value = resp.json().await.expect("decode gateway response");
    assert_eq!(body["model"], "qwen3-coder-plus");
}

#[tokio::test]
async fn keeps_original_model_when_rule_not_matched_and_no_fallback() {
    let upstream = spawn_upstream_echo_model_mock().await;
    // 不设置 default_model，这样原始模型才会保持
    let gateway = setup_gateway_with_provider_base_url_and_protocol_config_no_default_model(
        format!("http://{}/v1", upstream.addr),
        json!({
            "model_mapping": {
                "rules": [
                    {"from": "claude-*", "to": "qwen3-coder-plus"}
                ]
            }
        }),
    )
    .await;

    let resp = reqwest::Client::new()
        .post(format!("http://{}/v1/messages", gateway.addr))
        .json(&json!({
            "model": "unknown-model",
            "max_tokens": 128,
            "messages": [{"role": "user", "content": "hello"}]
        }))
        .send()
        .await
        .expect("call gateway");

    assert_eq!(resp.status(), reqwest::StatusCode::OK);
    let body: Value = resp.json().await.expect("decode gateway response");
    assert_eq!(body["model"], "unknown-model");
}

struct SpawnedServer {
    addr: SocketAddr,
}

struct RequestLogRow {
    inbound_protocol: Option<String>,
    upstream_protocol: Option<String>,
    model_effective: Option<String>,
    input_tokens: Option<i64>,
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

async fn spawn_upstream_model_rewrite_mock() -> SpawnedServer {
    let app = Router::new().route(
        "/v1/chat/completions",
        post(upstream_chat_completions_expect_rewritten_model),
    );
    spawn_gateway(app).await
}

async fn spawn_upstream_echo_model_mock() -> SpawnedServer {
    let app = Router::new().route("/v1/chat/completions", post(upstream_chat_completions_echo_model));
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
    setup_gateway_with_provider_base_url_and_protocol_config(base_url, json!({})).await
}

async fn setup_gateway_with_provider_base_url_and_pool(
    base_url: String,
) -> (SpawnedServer, sqlx::SqlitePool) {
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
        "INSERT INTO gateways (id, name, listen_host, listen_port, inbound_protocol, upstream_protocol, protocol_config_json, default_provider_id, default_model, enabled) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, 1)",
    )
    .bind("gw_anthropic")
    .bind("Gateway Anthropic")
    .bind("127.0.0.1")
    .bind(18889_i64)
    .bind("anthropic")
    .bind("openai")
    .bind(json!({}).to_string())
    .bind("provider_openai")
    .bind("gpt-4o-mini")
    .execute(&pool)
    .await
    .expect("insert gateway");

    let app = build_anthropic_router(AnthropicRouteState::new(pool.clone(), "gw_anthropic"));
    let gateway = spawn_gateway(app).await;
    (gateway, pool)
}

async fn setup_gateway_with_provider_base_url_and_protocol_config(
    base_url: String,
    protocol_config_json: Value,
) -> SpawnedServer {
    setup_gateway_with_provider_base_url_and_protocol_config_internal(base_url, protocol_config_json, Some("gpt-4o-mini")).await
}

async fn setup_gateway_with_provider_base_url_and_protocol_config_no_default_model(
    base_url: String,
    protocol_config_json: Value,
) -> SpawnedServer {
    setup_gateway_with_provider_base_url_and_protocol_config_internal(base_url, protocol_config_json, None::<&str>).await
}

async fn setup_gateway_with_provider_base_url_and_protocol_config_internal(
    base_url: String,
    protocol_config_json: Value,
    default_model: Option<&str>,
) -> SpawnedServer {
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
        "INSERT INTO gateways (id, name, listen_host, listen_port, inbound_protocol, upstream_protocol, protocol_config_json, default_provider_id, default_model, enabled) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, 1)",
    )
    .bind("gw_anthropic")
    .bind("Gateway Anthropic")
    .bind("127.0.0.1")
    .bind(18889_i64)
    .bind("anthropic")
    .bind("openai")
    .bind(protocol_config_json.to_string())
    .bind("provider_openai")
    .bind(default_model)
    .execute(&pool)
    .await
    .expect("insert gateway");

    let app = build_anthropic_router(AnthropicRouteState::new(pool, "gw_anthropic"));
    spawn_gateway(app).await
}

async fn latest_request_log(pool: &sqlx::SqlitePool) -> RequestLogRow {
    let row = sqlx::query_as::<_, (Option<String>, Option<String>, Option<String>, Option<i64>)>(
        "SELECT inbound_protocol, upstream_protocol, model_effective, input_tokens FROM request_logs ORDER BY created_at DESC LIMIT 1",
    )
    .fetch_one(pool)
    .await
    .expect("fetch request log");

    RequestLogRow {
        inbound_protocol: row.0,
        upstream_protocol: row.1,
        model_effective: row.2,
        input_tokens: row.3,
    }
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

async fn upstream_chat_completions_expect_rewritten_model(Json(payload): Json<Value>) -> impl IntoResponse {
    assert_eq!(payload["model"], "qwen3-coder-plus");
    assert_eq!(payload["messages"][0]["role"], "user");

    Json(json!({
        "id": "chatcmpl_model_rewrite_001",
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

async fn upstream_chat_completions_echo_model(Json(payload): Json<Value>) -> impl IntoResponse {
    Json(json!({
        "id": "chatcmpl_echo_001",
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

#[tokio::test]
async fn forwards_anthropic_tool_result_to_openai_tool_message() {
    let upstream = spawn_upstream_tool_result_mock().await;
    let gateway = setup_gateway_with_provider_base_url(format!("http://{}/v1", upstream.addr)).await;

    // Send a request with tool_result content block
    let resp = reqwest::Client::new()
        .post(format!("http://{}/v1/messages", gateway.addr))
        .json(&json!({
            "model": "claude-3-7-sonnet",
            "max_tokens": 128,
            "messages": [
                {
                    "role": "user",
                    "content": "What's the weather?"
                },
                {
                    "role": "assistant",
                    "content": [
                        {
                            "type": "tool_use",
                            "id": "toolu_001",
                            "name": "get_weather",
                            "input": {"city": "Beijing"}
                        }
                    ]
                },
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "tool_result",
                            "tool_use_id": "toolu_001",
                            "content": "Sunny, 25°C"
                        }
                    ]
                }
            ]
        }))
        .send()
        .await
        .expect("call gateway");

    assert_eq!(resp.status(), reqwest::StatusCode::OK);

    let body: Value = resp.json().await.expect("decode gateway response");
    assert_eq!(body["type"], "message");
    assert_eq!(body["role"], "assistant");
}

async fn spawn_upstream_tool_result_mock() -> SpawnedServer {
    let app = Router::new().route(
        "/v1/chat/completions",
        post(upstream_chat_completions_expect_tool_result_format),
    );
    spawn_gateway(app).await
}

async fn upstream_chat_completions_expect_tool_result_format(Json(payload): Json<Value>) -> impl IntoResponse {
    let messages = payload["messages"].as_array().expect("messages array");

    // Verify message structure
    // Message 0: user with text content
    assert_eq!(messages[0]["role"], "user");
    assert_eq!(messages[0]["content"], "What's the weather?");

    // Message 1: assistant with tool_calls
    assert_eq!(messages[1]["role"], "assistant");
    let tool_calls = messages[1]["tool_calls"].as_array().expect("tool_calls array");
    assert_eq!(tool_calls.len(), 1);
    assert_eq!(tool_calls[0]["id"], "toolu_001");
    assert_eq!(tool_calls[0]["function"]["name"], "get_weather");
    assert_eq!(tool_calls[0]["function"]["arguments"], r#"{"city":"Beijing"}"#);

    // Message 2: user message (empty content, parent of tool_result)
    assert_eq!(messages[2]["role"], "user");
    assert_eq!(messages[2]["content"], Value::Null);

    // Message 3: tool message with result
    assert_eq!(messages[3]["role"], "tool");
    assert_eq!(messages[3]["tool_call_id"], "toolu_001");
    assert_eq!(messages[3]["content"], "Sunny, 25°C");

    Json(json!({
        "id": "chatcmpl_tool_result_001",
        "object": "chat.completion",
        "model": payload["model"],
        "choices": [
            {
                "index": 0,
                "message": {"role": "assistant", "content": "Based on the weather data, it's sunny in Beijing with 25°C."},
                "finish_reason": "stop"
            }
        ],
        "usage": {
            "prompt_tokens": 50,
            "completion_tokens": 15,
            "total_tokens": 65
        }
    }))
}
