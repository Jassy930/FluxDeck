use std::net::SocketAddr;

use axum::{extract::Json, response::IntoResponse, routing::post, Router};
use fluxd::http::openai_routes::{build_openai_router, OpenAiRouteState};
use fluxd::storage::migrate::run_migrations;
use serde_json::{json, Value};
use tokio::net::TcpListener;

#[tokio::test]
async fn forwards_chat_completions_to_upstream() {
    let upstream = spawn_upstream_mock().await;

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
    let gateway = spawn_gateway(app).await;

    let resp = reqwest::Client::new()
        .post(format!("http://{}/v1/chat/completions", gateway.addr))
        .json(&json!({
            "model": "gpt-4o-mini",
            "messages": [{"role": "user", "content": "hello"}]
        }))
        .send()
        .await
        .expect("call gateway");

    assert_eq!(resp.status(), reqwest::StatusCode::OK);

    let body: Value = resp.json().await.expect("decode gateway response");
    assert_eq!(body["id"], "chatcmpl_mock_001");
    assert_eq!(body["object"], "chat.completion");
}

struct SpawnedServer {
    addr: SocketAddr,
}

async fn spawn_upstream_mock() -> SpawnedServer {
    let app = Router::new().route("/v1/chat/completions", post(upstream_chat_completions));
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

async fn upstream_chat_completions(Json(payload): Json<Value>) -> impl IntoResponse {
    let model = payload
        .get("model")
        .and_then(Value::as_str)
        .unwrap_or("unknown");

    Json(json!({
        "id": "chatcmpl_mock_001",
        "object": "chat.completion",
        "model": model,
        "choices": [
            {
                "index": 0,
                "message": {"role": "assistant", "content": "pong"},
                "finish_reason": "stop"
            }
        ]
    }))
}
