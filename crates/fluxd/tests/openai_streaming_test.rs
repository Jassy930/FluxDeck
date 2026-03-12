use std::net::SocketAddr;

use axum::{
    body::Body,
    extract::Json,
    http::{header, HeaderValue, StatusCode},
    response::IntoResponse,
    routing::post,
    Router,
};
use bytes::Bytes;
use fluxd::http::openai_routes::{build_openai_router, OpenAiRouteState};
use fluxd::storage::migrate::run_migrations;
use futures_util::stream;
use serde_json::{json, Value};
use tokio::net::TcpListener;

#[tokio::test]
async fn openai_chat_completions_streams_through_gateway() {
    let (upstream, _) = setup_openai_gateway_with_streaming_upstream().await;

    let body = call_openai_stream(upstream.addr).await;

    assert!(body.contains("chat.completion.chunk"));
    assert!(body.contains("[DONE]"));
}

#[tokio::test]
async fn openai_streaming_persists_usage_after_stream_finishes() {
    let (upstream, pool) = setup_openai_gateway_with_streaming_upstream().await;

    let body = call_openai_stream(upstream.addr).await;

    assert!(body.contains("[DONE]"));

    let row = sqlx::query_as::<_, (Option<i64>, Option<i64>, Option<i64>)>(
        "SELECT input_tokens, output_tokens, total_tokens FROM request_logs ORDER BY created_at DESC LIMIT 1",
    )
    .fetch_one(&pool)
    .await
    .expect("fetch latest request log");

    assert_eq!(row.0, Some(10));
    assert_eq!(row.1, Some(2));
    assert_eq!(row.2, Some(12));
}

async fn call_openai_stream(addr: SocketAddr) -> String {
    reqwest::Client::new()
        .post(format!("http://{addr}/v1/chat/completions"))
        .json(&json!({
            "model": "gpt-4o-mini",
            "stream": true,
            "messages": [{"role": "user", "content": "hello"}]
        }))
        .send()
        .await
        .expect("call gateway")
        .text()
        .await
        .expect("read stream body")
}

struct SpawnedServer {
    addr: SocketAddr,
}

async fn setup_openai_gateway_with_streaming_upstream() -> (SpawnedServer, sqlx::SqlitePool) {
    let upstream = spawn_upstream_stream_mock().await;

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
    .bind(format!("http://{}/v1", upstream.addr))
    .bind("sk-upstream")
    .execute(&pool)
    .await
    .expect("insert provider");

    sqlx::query(
        "INSERT INTO gateways (id, name, listen_host, listen_port, inbound_protocol, default_provider_id, default_model, enabled) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, 1)",
    )
    .bind("gw_openai")
    .bind("Gateway OpenAI")
    .bind("127.0.0.1")
    .bind(18888_i64)
    .bind("openai")
    .bind("provider_openai")
    .bind("gpt-4o-mini")
    .execute(&pool)
    .await
    .expect("insert gateway");

    let app = build_openai_router(OpenAiRouteState::new(pool.clone(), "gw_openai"));
    let gateway = spawn_server(app).await;
    (gateway, pool)
}

async fn spawn_upstream_stream_mock() -> SpawnedServer {
    let app = Router::new().route("/v1/chat/completions", post(upstream_stream_chat_completions));
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

async fn upstream_stream_chat_completions(Json(payload): Json<Value>) -> impl IntoResponse {
    assert_eq!(payload["stream"], true);
    assert_eq!(payload["stream_options"]["include_usage"], true);

    let chunks = vec![
        Ok::<Bytes, std::convert::Infallible>(Bytes::from(
            "data: {\"id\":\"chatcmpl_stream_001\",\"object\":\"chat.completion.chunk\",\"model\":\"gpt-4o-mini\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":\"pon\"},\"finish_reason\":null}]}\n\n",
        )),
        Ok(Bytes::from(
            "data: {\"id\":\"chatcmpl_stream_001\",\"object\":\"chat.completion.chunk\",\"model\":\"gpt-4o-mini\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"g\"},\"finish_reason\":\"stop\"}]}\n\n",
        )),
        Ok(Bytes::from(
            "data: {\"id\":\"chatcmpl_stream_001\",\"object\":\"chat.completion.chunk\",\"model\":\"gpt-4o-mini\",\"choices\":[],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":2,\"total_tokens\":12}}\n\n",
        )),
        Ok(Bytes::from("data: [DONE]\n\n")),
    ];

    (
        StatusCode::OK,
        [(header::CONTENT_TYPE, HeaderValue::from_static("text/event-stream; charset=utf-8"))],
        Body::from_stream(stream::iter(chunks)),
    )
}
