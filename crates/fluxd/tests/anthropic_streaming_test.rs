use std::net::SocketAddr;

use axum::{
    extract::Json,
    http::header,
    response::IntoResponse,
    routing::post,
    Router,
};
use fluxd::http::anthropic_routes::{build_anthropic_router, AnthropicRouteState};
use fluxd::storage::migrate::run_migrations;
use serde_json::{json, Value};
use tokio::net::TcpListener;

#[tokio::test]
async fn maps_openai_sse_to_anthropic_sse_events() {
    let upstream = spawn_upstream_stream_mock().await;
    let gateway = setup_gateway_with_provider_base_url(format!("http://{}/v1", upstream.addr)).await;

    let resp = reqwest::Client::new()
        .post(format!("http://{}/v1/messages", gateway.addr))
        .json(&json!({
            "model": "claude-3-7-sonnet",
            "max_tokens": 128,
            "stream": true,
            "messages": [{"role": "user", "content": "hello"}]
        }))
        .send()
        .await
        .expect("call gateway");

    assert_eq!(resp.status(), reqwest::StatusCode::OK);
    let content_type = resp
        .headers()
        .get(reqwest::header::CONTENT_TYPE)
        .and_then(|value| value.to_str().ok())
        .unwrap_or_default();
    assert!(
        content_type.starts_with("text/event-stream"),
        "unexpected content-type: {content_type}"
    );

    let body = resp.text().await.expect("read sse body");
    assert!(body.contains("event: message_start"), "missing message_start: {body}");
    assert!(
        body.contains("event: content_block_delta"),
        "missing content_block_delta: {body}"
    );
    assert!(body.contains("event: message_stop"), "missing message_stop: {body}");
    assert!(body.contains("\"text\":\"pon\""), "missing first delta text: {body}");
    assert!(body.contains("\"text\":\"g\""), "missing second delta text: {body}");
}

struct SpawnedServer {
    addr: SocketAddr,
}

async fn spawn_upstream_stream_mock() -> SpawnedServer {
    let app = Router::new().route("/v1/chat/completions", post(upstream_stream_chat_completions));
    spawn_server(app).await
}

async fn spawn_server(app: Router) -> SpawnedServer {
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
    spawn_server(app).await
}

async fn upstream_stream_chat_completions(Json(payload): Json<Value>) -> impl IntoResponse {
    assert_eq!(payload["stream"], true);
    assert_eq!(payload["messages"][0]["role"], "user");
    assert_eq!(payload["messages"][0]["content"], "hello");

    let chunk1 = json!({
        "id": "chatcmpl_stream_001",
        "object": "chat.completion.chunk",
        "model": payload["model"],
        "choices": [
            {
                "index": 0,
                "delta": {"role": "assistant", "content": "pon"},
                "finish_reason": Value::Null
            }
        ]
    });

    let chunk2 = json!({
        "id": "chatcmpl_stream_001",
        "object": "chat.completion.chunk",
        "model": payload["model"],
        "choices": [
            {
                "index": 0,
                "delta": {"content": "g"},
                "finish_reason": "stop"
            }
        ]
    });

    let body = format!(
        "data: {chunk1}\n\ndata: {chunk2}\n\ndata: [DONE]\n\n"
    );

    (
        [(header::CONTENT_TYPE, "text/event-stream; charset=utf-8")],
        body,
    )
}
