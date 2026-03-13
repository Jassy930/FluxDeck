use std::net::SocketAddr;

use axum::{
    body::{to_bytes, Body},
    extract::Request,
    http::header,
    response::IntoResponse,
    routing::{get, post},
    Router,
};
use bytes::Bytes;
use fluxd::http::openai_routes::{build_openai_router, OpenAiRouteState};
use fluxd::storage::migrate::run_migrations;
use futures_util::stream;
use serde_json::{json, Value};
use tokio::net::TcpListener;

#[tokio::test]
async fn forwards_responses_without_version_prefix_via_openai_fallback() {
    let upstream = spawn_upstream_mock().await;
    let gateway = spawn_openai_gateway(format!("http://{}/v1", upstream.addr)).await;

    let resp = reqwest::Client::new()
        .post(format!("http://{}/responses", gateway.addr))
        .json(&json!({
            "model": "gpt-5-codex",
            "input": "ping"
        }))
        .send()
        .await
        .expect("call gateway /responses");

    assert_eq!(resp.status(), reqwest::StatusCode::OK);
    let body: Value = resp.json().await.expect("decode /responses body");
    assert_eq!(body["id"], "resp_mock_001");
    assert_eq!(body["path"], "/v1/responses");
}

#[tokio::test]
async fn forwards_responses_with_version_prefix_via_openai_fallback() {
    let upstream = spawn_upstream_mock().await;
    let gateway = spawn_openai_gateway(format!("http://{}/v1", upstream.addr)).await;

    let resp = reqwest::Client::new()
        .post(format!("http://{}/v1/responses", gateway.addr))
        .json(&json!({
            "model": "gpt-5-codex",
            "input": "ping"
        }))
        .send()
        .await
        .expect("call gateway /v1/responses");

    assert_eq!(resp.status(), reqwest::StatusCode::OK);
    let body: Value = resp.json().await.expect("decode /v1/responses body");
    assert_eq!(body["id"], "resp_mock_001");
    assert_eq!(body["path"], "/v1/responses");
}

#[tokio::test]
async fn persists_minimal_request_log_for_openai_fallback() {
    let upstream = spawn_upstream_mock().await;
    let gateway = spawn_openai_gateway(format!("http://{}/v1", upstream.addr)).await;

    let resp = reqwest::Client::new()
        .post(format!("http://{}/responses", gateway.addr))
        .json(&json!({
            "model": "gpt-5-codex",
            "input": "ping"
        }))
        .send()
        .await
        .expect("call gateway /responses");

    assert_eq!(resp.status(), reqwest::StatusCode::OK);

    let row = sqlx::query_as::<_, (Option<String>, Option<String>, i64)>(
        "SELECT inbound_protocol, upstream_protocol, status_code FROM request_logs ORDER BY rowid DESC LIMIT 1",
    )
    .fetch_one(&gateway.pool)
    .await
    .expect("fetch fallback request log");

    assert_eq!(row.0.as_deref(), Some("openai"));
    assert_eq!(row.1.as_deref(), Some("openai"));
    assert_eq!(row.2, 200);
}

#[tokio::test]
async fn persists_usage_for_non_stream_openai_responses_fallback() {
    let upstream = spawn_upstream_mock().await;
    let gateway = spawn_openai_gateway(format!("http://{}/v1", upstream.addr)).await;

    let resp = reqwest::Client::new()
        .post(format!("http://{}/responses", gateway.addr))
        .json(&json!({
            "model": "gpt-5-codex",
            "input": "ping"
        }))
        .send()
        .await
        .expect("call gateway /responses");

    assert_eq!(resp.status(), reqwest::StatusCode::OK);

    let row = sqlx::query_as::<_, (Option<i64>, Option<i64>, Option<i64>, Option<i64>)>(
        "SELECT input_tokens, output_tokens, cached_tokens, total_tokens FROM request_logs ORDER BY rowid DESC LIMIT 1",
    )
    .fetch_one(&gateway.pool)
    .await
    .expect("fetch fallback usage log");

    assert_eq!(row.0, Some(11));
    assert_eq!(row.1, Some(7));
    assert_eq!(row.2, Some(5));
    assert_eq!(row.3, Some(18));
}

#[tokio::test]
async fn persists_model_dimensions_for_non_stream_openai_responses_fallback() {
    let upstream = spawn_upstream_mock().await;
    let gateway = spawn_openai_gateway(format!("http://{}/v1", upstream.addr)).await;

    let resp = reqwest::Client::new()
        .post(format!("http://{}/responses", gateway.addr))
        .json(&json!({
            "model": "gpt-5-codex",
            "input": "ping"
        }))
        .send()
        .await
        .expect("call gateway /responses");

    assert_eq!(resp.status(), reqwest::StatusCode::OK);

    let row = sqlx::query_as::<_, (Option<String>, Option<String>, Option<String>)>(
        "SELECT model, model_requested, model_effective FROM request_logs ORDER BY rowid DESC LIMIT 1",
    )
    .fetch_one(&gateway.pool)
    .await
    .expect("fetch fallback model dimensions log");

    assert_eq!(row.0.as_deref(), Some("gpt-5-codex"));
    assert_eq!(row.1.as_deref(), Some("gpt-5-codex"));
    assert_eq!(row.2.as_deref(), Some("gpt-5-codex"));
}

#[tokio::test]
async fn persists_first_byte_for_non_stream_openai_responses_fallback() {
    let upstream = spawn_upstream_mock().await;
    let gateway = spawn_openai_gateway(format!("http://{}/v1", upstream.addr)).await;

    let resp = reqwest::Client::new()
        .post(format!("http://{}/responses", gateway.addr))
        .json(&json!({
            "model": "gpt-5-codex",
            "input": "ping"
        }))
        .send()
        .await
        .expect("call gateway /responses");

    assert_eq!(resp.status(), reqwest::StatusCode::OK);

    let row = sqlx::query_as::<_, (Option<i64>, Option<i64>)>(
        "SELECT first_byte_ms, latency_ms FROM request_logs ORDER BY rowid DESC LIMIT 1",
    )
    .fetch_one(&gateway.pool)
    .await
    .expect("fetch fallback first byte log");

    assert_eq!(row.0, row.1);
    assert!(row.0.is_some());
}

#[tokio::test]
async fn persists_usage_for_streaming_openai_responses_fallback_after_stream_finishes() {
    let upstream = spawn_upstream_mock().await;
    let gateway = spawn_openai_gateway(format!("http://{}/v1", upstream.addr)).await;

    let body = reqwest::Client::new()
        .post(format!("http://{}/responses", gateway.addr))
        .json(&json!({
            "model": "gpt-5-codex",
            "input": "ping",
            "stream": true
        }))
        .send()
        .await
        .expect("call gateway /responses")
        .text()
        .await
        .expect("read streaming fallback body");

    assert!(body.contains("response.completed"));

    let row = sqlx::query_as::<_, (Option<i64>, Option<i64>, Option<i64>, Option<i64>)>(
        "SELECT input_tokens, output_tokens, cached_tokens, total_tokens FROM request_logs ORDER BY rowid DESC LIMIT 1",
    )
    .fetch_one(&gateway.pool)
    .await
    .expect("fetch fallback streaming usage log");

    assert_eq!(row.0, Some(21));
    assert_eq!(row.1, Some(13));
    assert_eq!(row.2, Some(8));
    assert_eq!(row.3, Some(34));
}

#[tokio::test]
async fn persists_first_byte_for_streaming_openai_responses_fallback() {
    let upstream = spawn_upstream_mock().await;
    let gateway = spawn_openai_gateway(format!("http://{}/v1", upstream.addr)).await;

    let body = reqwest::Client::new()
        .post(format!("http://{}/responses", gateway.addr))
        .json(&json!({
            "model": "gpt-5-codex",
            "input": "ping",
            "stream": true
        }))
        .send()
        .await
        .expect("call gateway /responses")
        .text()
        .await
        .expect("read streaming fallback body");

    assert!(body.contains("response.completed"));

    let row = sqlx::query_as::<_, (Option<i64>, i64)>(
        "SELECT first_byte_ms, latency_ms FROM request_logs ORDER BY rowid DESC LIMIT 1",
    )
    .fetch_one(&gateway.pool)
    .await
    .expect("fetch fallback streaming first byte log");

    assert!(row.0.is_some());
    assert!(row.1 >= row.0.unwrap_or_default());
}

struct SpawnedServer {
    addr: SocketAddr,
}

struct SpawnedGateway {
    addr: SocketAddr,
    pool: sqlx::SqlitePool,
}

async fn spawn_openai_gateway(base_url: String) -> SpawnedGateway {
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
    .bind("gw_openai")
    .bind("Gateway OpenAI")
    .bind("127.0.0.1")
    .bind(18889_i64)
    .bind("openai")
    .bind("provider_default")
    .bind("provider_openai")
    .bind("gpt-5-codex")
    .execute(&pool)
    .await
    .expect("insert gateway");

    let app = build_openai_router(OpenAiRouteState::new(pool.clone(), "gw_openai"));
    let server = spawn_server(app).await;
    SpawnedGateway {
        addr: server.addr,
        pool,
    }
}

async fn spawn_upstream_mock() -> SpawnedServer {
    let app = Router::new()
        .route("/v1/responses", post(upstream_responses))
        .route("/healthz", get(|| async { "ok" }));
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

async fn upstream_responses(request: Request) -> impl IntoResponse {
    let path = request.uri().path().to_string();
    let body = to_bytes(request.into_body(), usize::MAX)
        .await
        .expect("collect upstream request body");

    let payload: Value = serde_json::from_slice::<Value>(&body).expect("decode upstream payload");

    if payload.get("stream").and_then(Value::as_bool) == Some(true) {
        let chunks = vec![
            Ok::<Bytes, std::convert::Infallible>(Bytes::from(
                "event: response.created\ndata: {\"type\":\"response.created\",\"response\":{\"id\":\"resp_mock_stream_001\",\"object\":\"response\",\"model\":\"gpt-5-codex\"}}\n\n",
            )),
            Ok(Bytes::from(
                "event: response.output_text.delta\ndata: {\"type\":\"response.output_text.delta\",\"delta\":\"pong\"}\n\n",
            )),
            Ok(Bytes::from(
                "event: response.completed\ndata: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp_mock_stream_001\",\"object\":\"response\",\"model\":\"gpt-5-codex\",\"usage\":{\"input_tokens\":21,\"output_tokens\":13,\"total_tokens\":34,\"input_tokens_details\":{\"cached_tokens\":8}}}}\n\n",
            )),
            Ok(Bytes::from("data: [DONE]\n\n")),
        ];

        return (
            [(header::CONTENT_TYPE, "text/event-stream; charset=utf-8")],
            Body::from_stream(stream::iter(chunks)),
        )
            .into_response();
    }

    axum::Json(json!({
        "id": "resp_mock_001",
        "object": "response",
        "path": path,
        "input_echo": payload.get("input").cloned().unwrap_or(Value::Null),
        "usage": {
            "input_tokens": 11,
            "output_tokens": 7,
            "total_tokens": 18,
            "input_tokens_details": {
                "cached_tokens": 5
            }
        }
    }))
    .into_response()
}
