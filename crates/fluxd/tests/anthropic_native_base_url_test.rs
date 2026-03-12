use std::net::SocketAddr;

use axum::{
    body::Body, extract::Json, http::header, response::IntoResponse, routing::post, Router,
};
use bytes::Bytes;
use fluxd::http::anthropic_routes::{build_anthropic_router, AnthropicRouteState};
use fluxd::storage::migrate::run_migrations;
use futures_util::stream;
use serde_json::{json, Value};
use tokio::net::TcpListener;

#[tokio::test]
async fn forwards_anthropic_messages_when_provider_base_url_omits_v1() {
    let gateway = setup_anthropic_native_gateway_without_v1().await;

    let response = reqwest::Client::new()
        .post(format!("http://{}/v1/messages", gateway.addr))
        .json(&json!({
            "model": "claude-3-7-sonnet",
            "max_tokens": 64,
            "messages": [{"role": "user", "content": "hello"}]
        }))
        .send()
        .await
        .expect("call gateway");

    assert_eq!(response.status(), reqwest::StatusCode::OK);

    let body: Value = response.json().await.expect("decode response");
    assert_eq!(body["type"], "message");
    assert_eq!(body["role"], "assistant");
    assert_eq!(body["content"][0]["type"], "text");
    assert_eq!(body["content"][0]["text"], "pong");
}

#[tokio::test]
async fn streams_anthropic_events_when_provider_base_url_omits_v1() {
    let gateway = setup_anthropic_native_gateway_without_v1().await;

    let body = reqwest::Client::new()
        .post(format!("http://{}/v1/messages", gateway.addr))
        .json(&json!({
            "model": "claude-3-7-sonnet",
            "max_tokens": 64,
            "stream": true,
            "messages": [{"role": "user", "content": "hello"}]
        }))
        .send()
        .await
        .expect("call gateway")
        .text()
        .await
        .expect("read body");

    assert!(body.contains("event: message_start"));
    assert!(body.contains("event: content_block_delta"));
    assert!(body.contains("event: message_stop"));
}

#[tokio::test]
async fn counts_tokens_when_provider_base_url_omits_v1() {
    let gateway = setup_anthropic_native_gateway_without_v1().await;

    let response = reqwest::Client::new()
        .post(format!("http://{}/v1/messages/count_tokens", gateway.addr))
        .json(&json!({
            "model": "claude-3-7-sonnet",
            "messages": [{"role": "user", "content": "hello"}]
        }))
        .send()
        .await
        .expect("call gateway");

    assert_eq!(response.status(), reqwest::StatusCode::OK);

    let body: Value = response.json().await.expect("decode response");
    assert_eq!(body["input_tokens"], 123);
}

struct SpawnedServer {
    addr: SocketAddr,
}

async fn setup_anthropic_native_gateway_without_v1() -> SpawnedServer {
    let upstream = spawn_native_upstream_mock().await;
    let pool = sqlx::SqlitePool::connect("sqlite::memory:")
        .await
        .expect("connect sqlite memory db");
    run_migrations(&pool).await.expect("run migrations");

    sqlx::query(
        "INSERT INTO providers (id, name, kind, base_url, api_key, enabled) VALUES (?1, ?2, ?3, ?4, ?5, 1)",
    )
    .bind("provider_anthropic")
    .bind("Anthropic Upstream")
    .bind("anthropic")
    .bind(format!("http://{}", upstream.addr))
    .bind("sk-anthropic")
    .execute(&pool)
    .await
    .expect("insert provider");

    sqlx::query(
        "INSERT INTO gateways (id, name, listen_host, listen_port, inbound_protocol, upstream_protocol, protocol_config_json, default_provider_id, default_model, enabled) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, 1)",
    )
    .bind("gw_anthropic_native")
    .bind("Gateway Anthropic Native")
    .bind("127.0.0.1")
    .bind(18893_i64)
    .bind("anthropic")
    .bind("anthropic")
    .bind(json!({}).to_string())
    .bind("provider_anthropic")
    .bind("claude-sonnet-4-5")
    .execute(&pool)
    .await
    .expect("insert gateway");

    let app = build_anthropic_router(AnthropicRouteState::new(pool, "gw_anthropic_native"));
    spawn_server(app).await
}

async fn spawn_native_upstream_mock() -> SpawnedServer {
    let app = Router::new()
        .route("/v1/messages", post(native_upstream_messages))
        .route(
            "/v1/messages/count_tokens",
            post(native_upstream_count_tokens),
        );
    spawn_server(app).await
}

async fn spawn_server(app: Router) -> SpawnedServer {
    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind random port");
    let addr = listener.local_addr().expect("read listener addr");

    tokio::spawn(async move {
        axum::serve(listener, app).await.expect("serve app");
    });

    SpawnedServer { addr }
}

async fn native_upstream_messages(Json(payload): Json<Value>) -> impl IntoResponse {
    if payload["stream"].as_bool().unwrap_or(false) {
        let chunks = vec![
            Ok::<Bytes, std::convert::Infallible>(Bytes::from(
                "event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_native_stream_001\",\"type\":\"message\",\"role\":\"assistant\",\"model\":\"claude-sonnet-4-5\",\"content\":[],\"usage\":{\"input_tokens\":12,\"output_tokens\":0}}}\n\n",
            )),
            Ok(Bytes::from(
                "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"pong\"}}\n\n",
            )),
            Ok(Bytes::from(
                "event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n",
            )),
        ];

        return (
            [(header::CONTENT_TYPE, "text/event-stream; charset=utf-8")],
            Body::from_stream(stream::iter(chunks)),
        )
            .into_response();
    }

    Json(json!({
        "id": "msg_native_001",
        "type": "message",
        "role": "assistant",
        "model": payload["model"],
        "content": [{"type": "text", "text": "pong"}],
        "stop_reason": "end_turn",
        "stop_sequence": Value::Null,
        "usage": {
            "input_tokens": 12,
            "output_tokens": 3
        }
    }))
    .into_response()
}

async fn native_upstream_count_tokens(Json(payload): Json<Value>) -> impl IntoResponse {
    assert_eq!(payload["model"], "claude-sonnet-4-5");
    Json(json!({
        "input_tokens": 123
    }))
}
