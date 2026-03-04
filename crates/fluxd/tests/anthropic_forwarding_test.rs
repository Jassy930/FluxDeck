use std::net::SocketAddr;

use axum::{extract::Json, response::IntoResponse, routing::post, Router};
use fluxd::http::anthropic_routes::{build_anthropic_router, AnthropicRouteState};
use fluxd::storage::migrate::run_migrations;
use serde_json::{json, Value};
use tokio::net::TcpListener;

#[tokio::test]
async fn forwards_anthropic_messages_to_openai_upstream() {
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

    let app = build_anthropic_router(AnthropicRouteState::new(pool.clone(), "gw_anthropic"));
    let gateway = spawn_gateway(app).await;

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
