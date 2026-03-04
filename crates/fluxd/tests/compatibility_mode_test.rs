use std::net::SocketAddr;

use axum::{
    extract::Json,
    http::StatusCode,
    response::IntoResponse,
    routing::post,
    Router,
};
use fluxd::http::anthropic_routes::{build_anthropic_router, AnthropicRouteState};
use fluxd::storage::migrate::run_migrations;
use serde_json::{json, Value};
use tokio::net::TcpListener;

#[tokio::test]
async fn compatibility_mode_controls_degrade_or_reject() {
    strict_mode_rejects_extension_fields().await;
    compatible_mode_downgrades_count_tokens_with_notice().await;
    permissive_mode_passes_extension_to_upstream().await;
}

async fn strict_mode_rejects_extension_fields() {
    let upstream = spawn_upstream_router(
        Router::new().route("/v1/chat/completions", post(upstream_chat_echo_basic)),
    )
    .await;
    let gateway = setup_gateway(upstream.addr, "strict", "gw_strict").await;

    let payload = json!({
        "model": "claude-3-7-sonnet",
        "messages": [{"role": "user", "content": "hello"}],
        "x_passthrough": {"trace_id": "strict-1"}
    });

    let resp = reqwest::Client::new()
        .post(format!("http://{}/v1/messages", gateway.addr))
        .json(&payload)
        .send()
        .await
        .expect("call strict gateway");

    assert_eq!(resp.status(), reqwest::StatusCode::UNPROCESSABLE_ENTITY);
    let body: Value = resp.json().await.expect("decode strict response");
    assert_eq!(body["error"]["type"], "capability_error");
}

async fn compatible_mode_downgrades_count_tokens_with_notice() {
    let upstream = spawn_upstream_router(
        Router::new().route("/v1/chat/completions", post(upstream_chat_echo_basic)),
    )
    .await;
    let gateway = setup_gateway(upstream.addr, "compatible", "gw_compatible").await;

    let payload = json!({
        "model": "claude-3-7-sonnet",
        "messages": [{"role": "user", "content": "hello"}]
    });

    let resp = reqwest::Client::new()
        .post(format!("http://{}/v1/messages/count_tokens", gateway.addr))
        .json(&payload)
        .send()
        .await
        .expect("call compatible gateway");

    assert_eq!(resp.status(), reqwest::StatusCode::OK);
    let body: Value = resp.json().await.expect("decode compatible response");
    assert_eq!(body["estimated"], true);
    assert_eq!(body["notice"], "degraded_to_estimate");
}

async fn permissive_mode_passes_extension_to_upstream() {
    let upstream = spawn_upstream_router(
        Router::new().route(
            "/v1/chat/completions",
            post(upstream_chat_requires_passthrough),
        ),
    )
    .await;
    let gateway = setup_gateway(upstream.addr, "permissive", "gw_permissive").await;

    let payload = json!({
        "model": "claude-3-7-sonnet",
        "messages": [{"role": "user", "content": "hello"}],
        "x_passthrough": {"trace_id": "permissive-1"}
    });

    let resp = reqwest::Client::new()
        .post(format!("http://{}/v1/messages", gateway.addr))
        .json(&payload)
        .send()
        .await
        .expect("call permissive gateway");

    assert_eq!(resp.status(), reqwest::StatusCode::OK);
    let body: Value = resp.json().await.expect("decode permissive response");
    assert_eq!(body["content"][0]["text"], "permissive-ok");
}

struct SpawnedServer {
    addr: SocketAddr,
}

async fn setup_gateway(upstream_addr: SocketAddr, mode: &str, gateway_id: &str) -> SpawnedServer {
    let pool = sqlx::SqlitePool::connect("sqlite::memory:")
        .await
        .expect("connect sqlite memory db");
    run_migrations(&pool).await.expect("run migrations");

    sqlx::query(
        "INSERT INTO providers (id, name, kind, base_url, api_key, enabled) VALUES (?1, ?2, ?3, ?4, ?5, 1)",
    )
    .bind("provider_openai")
    .bind("OpenAI Provider")
    .bind("openai")
    .bind(format!("http://{}/v1", upstream_addr))
    .bind("sk-test")
    .execute(&pool)
    .await
    .expect("insert provider");

    sqlx::query(
        "INSERT INTO gateways (id, name, listen_host, listen_port, inbound_protocol, upstream_protocol, protocol_config_json, default_provider_id, default_model, enabled) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, 1)",
    )
    .bind(gateway_id)
    .bind(format!("Gateway {mode}"))
    .bind("127.0.0.1")
    .bind(18880_i64)
    .bind("anthropic")
    .bind("openai")
    .bind(json!({ "compatibility_mode": mode }).to_string())
    .bind("provider_openai")
    .bind("claude-3-7-sonnet")
    .execute(&pool)
    .await
    .expect("insert gateway");

    let app = build_anthropic_router(AnthropicRouteState::new(pool, gateway_id));
    spawn_upstream_router(app).await
}

async fn spawn_upstream_router(app: Router) -> SpawnedServer {
    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind random port");
    let addr = listener.local_addr().expect("read listener addr");

    tokio::spawn(async move {
        axum::serve(listener, app).await.expect("serve app");
    });

    SpawnedServer { addr }
}

async fn upstream_chat_echo_basic(Json(payload): Json<Value>) -> impl IntoResponse {
    let model = payload
        .get("model")
        .and_then(Value::as_str)
        .unwrap_or("unknown");
    Json(json!({
        "id": "chatcmpl_mode_basic",
        "object": "chat.completion",
        "model": model,
        "choices": [{
            "index": 0,
            "message": { "role": "assistant", "content": "ok" },
            "finish_reason": "stop"
        }]
    }))
}

async fn upstream_chat_requires_passthrough(Json(payload): Json<Value>) -> impl IntoResponse {
    if payload.get("x_passthrough").is_none() {
        return (
            StatusCode::BAD_REQUEST,
            Json(json!({
                "error": {
                    "message": "missing x_passthrough",
                    "type": "invalid_request_error"
                }
            })),
        )
            .into_response();
    }

    Json(json!({
        "id": "chatcmpl_mode_perm",
        "object": "chat.completion",
        "model": "gpt-4o-mini",
        "choices": [{
            "index": 0,
            "message": { "role": "assistant", "content": "permissive-ok" },
            "finish_reason": "stop"
        }]
    }))
    .into_response()
}
