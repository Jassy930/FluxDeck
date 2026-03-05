use std::net::SocketAddr;
use std::time::Duration;

use axum::{
    body::Body, extract::Json, http::header, response::IntoResponse, routing::post, Router,
};
use bytes::Bytes;
use fluxd::http::anthropic_routes::{build_anthropic_router, AnthropicRouteState};
use fluxd::storage::migrate::run_migrations;
use futures_util::StreamExt;
use serde_json::{json, Value};
use tokio::net::TcpListener;
use tokio::time::{sleep, timeout};

#[tokio::test]
async fn maps_openai_sse_to_anthropic_sse_events() {
    let upstream = spawn_upstream_stream_mock().await;
    let gateway =
        setup_gateway_with_provider_base_url(format!("http://{}/v1", upstream.addr)).await;

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
    assert!(
        body.contains("event: message_start"),
        "missing message_start: {body}"
    );
    assert!(
        body.contains("event: content_block_delta"),
        "missing content_block_delta: {body}"
    );
    assert!(
        body.contains("event: message_stop"),
        "missing message_stop: {body}"
    );
    assert!(
        body.contains("\"text\":\"pon\""),
        "missing first delta text: {body}"
    );
    assert!(
        body.contains("\"text\":\"g\""),
        "missing second delta text: {body}"
    );
}

#[tokio::test]
async fn streams_first_anthropic_event_before_upstream_completes() {
    let upstream = spawn_upstream_incremental_stream_mock().await;
    let gateway =
        setup_gateway_with_provider_base_url(format!("http://{}/v1", upstream.addr)).await;

    let request = reqwest::Client::new()
        .post(format!("http://{}/v1/messages", gateway.addr))
        .json(&json!({
            "model": "claude-3-7-sonnet",
            "max_tokens": 128,
            "stream": true,
            "messages": [{"role": "user", "content": "hello"}]
        }));

    let resp = timeout(Duration::from_millis(150), request.send())
        .await
        .expect("gateway should return stream response before upstream final chunk")
        .expect("call gateway");

    assert_eq!(resp.status(), reqwest::StatusCode::OK);
    let mut stream = resp.bytes_stream();

    let first_chunk = timeout(Duration::from_millis(150), async {
        stream
            .next()
            .await
            .expect("first event chunk should exist")
            .expect("read first event chunk")
    })
    .await
    .expect("expected first anthropic event chunk before delayed upstream chunk");

    let first_text = String::from_utf8_lossy(&first_chunk);
    assert!(
        first_text.contains("event: message_start")
            || first_text.contains("event: content_block_start")
            || first_text.contains("event: content_block_delta"),
        "unexpected first chunk: {first_text}"
    );
}

#[tokio::test]
async fn extracts_sse_wrapped_upstream_error_message() {
    let upstream = spawn_upstream_error_stream_mock().await;
    let gateway =
        setup_gateway_with_provider_base_url(format!("http://{}/v1", upstream.addr)).await;

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

    assert_eq!(resp.status(), reqwest::StatusCode::TOO_MANY_REQUESTS);
    let body: Value = resp.json().await.expect("read error body");
    assert_eq!(body["error"]["type"], "api_error");
    assert_eq!(body["error"]["message"], "upstream rate limit reached");
}

struct SpawnedServer {
    addr: SocketAddr,
}

async fn spawn_upstream_stream_mock() -> SpawnedServer {
    let app = Router::new().route(
        "/v1/chat/completions",
        post(upstream_stream_chat_completions),
    );
    spawn_server(app).await
}

async fn spawn_upstream_incremental_stream_mock() -> SpawnedServer {
    let app = Router::new().route(
        "/v1/chat/completions",
        post(upstream_incremental_stream_chat_completions),
    );
    spawn_server(app).await
}

async fn spawn_upstream_error_stream_mock() -> SpawnedServer {
    let app = Router::new().route(
        "/v1/chat/completions",
        post(upstream_error_stream_chat_completions),
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

    let body = format!("data: {chunk1}\n\ndata: {chunk2}\n\ndata: [DONE]\n\n");

    (
        [(header::CONTENT_TYPE, "text/event-stream; charset=utf-8")],
        body,
    )
}

async fn upstream_incremental_stream_chat_completions(
    Json(payload): Json<Value>,
) -> impl IntoResponse {
    assert_eq!(payload["stream"], true);
    assert_eq!(payload["messages"][0]["role"], "user");
    assert_eq!(payload["messages"][0]["content"], "hello");

    let chunk1 = json!({
        "id": "chatcmpl_stream_002",
        "object": "chat.completion.chunk",
        "model": payload["model"],
        "choices": [
            {
                "index": 0,
                "delta": {"role": "assistant", "content": "hel"},
                "finish_reason": Value::Null
            }
        ]
    });

    let chunk2 = json!({
        "id": "chatcmpl_stream_002",
        "object": "chat.completion.chunk",
        "model": payload["model"],
        "choices": [
            {
                "index": 0,
                "delta": {"content": "lo"},
                "finish_reason": "stop"
            }
        ]
    });

    let stream = async_stream::stream! {
        yield Ok::<Bytes, std::convert::Infallible>(Bytes::from(format!("data: {chunk1}\n\n")));
        sleep(Duration::from_millis(350)).await;
        yield Ok::<Bytes, std::convert::Infallible>(Bytes::from(format!("data: {chunk2}\n\n")));
        yield Ok::<Bytes, std::convert::Infallible>(Bytes::from("data: [DONE]\n\n"));
    };

    (
        [(header::CONTENT_TYPE, "text/event-stream; charset=utf-8")],
        Body::from_stream(stream),
    )
}

async fn upstream_error_stream_chat_completions(Json(_payload): Json<Value>) -> impl IntoResponse {
    (
        reqwest::StatusCode::TOO_MANY_REQUESTS,
        [(header::CONTENT_TYPE, "text/event-stream; charset=utf-8")],
        "data: {\"error\":{\"message\":\"upstream rate limit reached\"}}\n\n",
    )
}
