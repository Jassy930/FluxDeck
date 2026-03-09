use std::net::SocketAddr;

use axum::{extract::Json, response::IntoResponse, routing::post, Router};
use fluxd::http::anthropic_routes::{build_anthropic_router, AnthropicRouteState};
use fluxd::storage::migrate::run_migrations;
use serde_json::{json, Value};
use tokio::net::TcpListener;

#[tokio::test]
async fn forwards_anthropic_messages_to_anthropic_upstream() {
    let gateway = setup_anthropic_native_gateway().await;

    let response = call_anthropic_messages(gateway.addr).await;

    assert_eq!(response["type"], "message");
    assert_eq!(response["role"], "assistant");
}

struct SpawnedServer {
    addr: SocketAddr,
}

async fn setup_anthropic_native_gateway() -> SpawnedServer {
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
    .bind(format!("http://{}/v1", upstream.addr))
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
    .bind(18891_i64)
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

async fn call_anthropic_messages(addr: SocketAddr) -> Value {
    reqwest::Client::new()
        .post(format!("http://{addr}/v1/messages"))
        .json(&json!({
            "model": "claude-3-7-sonnet",
            "max_tokens": 64,
            "messages": [{"role": "user", "content": "hello"}]
        }))
        .send()
        .await
        .expect("call gateway")
        .json()
        .await
        .expect("decode response")
}

async fn spawn_native_upstream_mock() -> SpawnedServer {
    let app = Router::new().route("/v1/messages", post(native_upstream_messages));
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
    assert_eq!(payload["messages"][0]["role"], "user");
    assert_eq!(payload["messages"][0]["content"], "hello");

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
}
