use std::net::SocketAddr;

use axum::{extract::Json, response::IntoResponse, routing::post, Router};
use fluxd::http::anthropic_routes::{build_anthropic_router, AnthropicRouteState};
use fluxd::protocol::adapters::anthropic::decode_anthropic_request;
use fluxd::protocol::token_count::estimate_tokens;
use fluxd::storage::migrate::run_migrations;
use serde_json::{json, Value};
use tokio::net::TcpListener;

#[tokio::test]
async fn count_tokens_uses_upstream_native_result_when_supported() {
    let upstream = spawn_upstream_with_count_tokens_mock().await;
    // 不设置 default_model，保持原始模型名称
    let gateway = setup_gateway_with_provider_base_url_and_protocol_config_no_default_model(
        format!("http://{}/v1", upstream.addr),
        json!({}),
    )
    .await;

    let payload = json!({
        "model": "claude-3-7-sonnet",
        "messages": [{"role": "user", "content": "hello"}]
    });

    let resp = reqwest::Client::new()
        .post(format!("http://{}/v1/messages/count_tokens", gateway.addr))
        .json(&payload)
        .send()
        .await
        .expect("call gateway");

    assert_eq!(resp.status(), reqwest::StatusCode::OK);
    let body: Value = resp.json().await.expect("decode gateway response");
    assert_eq!(body["input_tokens"], 321);
    assert_eq!(body["estimated"], false);
}

#[tokio::test]
async fn count_tokens_falls_back_to_local_estimator_when_upstream_not_supported() {
    let upstream = spawn_upstream_without_count_tokens_mock().await;
    // 不设置 default_model，保持原始模型名称
    let gateway = setup_gateway_with_provider_base_url_and_protocol_config_no_default_model(
        format!("http://{}/v1", upstream.addr),
        json!({}),
    )
    .await;

    let payload = json!({
        "model": "claude-3-7-sonnet",
        "system": "You are a concise assistant.",
        "messages": [{"role": "user", "content": "Please summarize this paragraph."}]
    });

    let resp = reqwest::Client::new()
        .post(format!("http://{}/v1/messages/count_tokens", gateway.addr))
        .json(&payload)
        .send()
        .await
        .expect("call gateway");

    assert_eq!(resp.status(), reqwest::StatusCode::OK);
    let body: Value = resp.json().await.expect("decode gateway response");

    let ir = decode_anthropic_request(&payload).expect("decode anthropic request");
    let expected = estimate_tokens(&ir);

    assert_eq!(body["input_tokens"], expected);
    assert_eq!(body["estimated"], true);
    assert!(expected > 0);
}

#[tokio::test]
async fn count_tokens_rewrites_model_with_fallback_mapping() {
    let upstream = spawn_upstream_with_count_tokens_rewrite_mock().await;
    // 不设置 default_model，这样 fallback_model 才会被使用
    let gateway = setup_gateway_with_provider_base_url_and_protocol_config_no_default_model(
        format!("http://{}/v1", upstream.addr),
        json!({
            "model_mapping": {
                "fallback_model": "qwen3-coder-plus"
            }
        }),
    )
    .await;

    let payload = json!({
        "model": "claude-3-7-sonnet",
        "messages": [{"role": "user", "content": "hello"}]
    });

    let resp = reqwest::Client::new()
        .post(format!("http://{}/v1/messages/count_tokens", gateway.addr))
        .json(&payload)
        .send()
        .await
        .expect("call gateway");

    assert_eq!(resp.status(), reqwest::StatusCode::OK);
    let body: Value = resp.json().await.expect("decode gateway response");
    assert_eq!(body["input_tokens"], 777);
    assert_eq!(body["estimated"], false);
}

#[tokio::test]
async fn count_tokens_keeps_original_model_when_no_fallback_mapping() {
    let upstream = spawn_upstream_with_count_tokens_mock().await;
    let gateway = setup_gateway_with_provider_base_url_and_protocol_config_no_default_model(
        format!("http://{}/v1", upstream.addr),
        json!({
            "model_mapping": {
                "rules": [
                    {"from": "claude-opus-*", "to": "qwen3-coder-plus"}
                ]
            }
        }),
    )
    .await;

    let payload = json!({
        "model": "claude-3-7-sonnet",
        "messages": [{"role": "user", "content": "hello"}]
    });

    let resp = reqwest::Client::new()
        .post(format!("http://{}/v1/messages/count_tokens", gateway.addr))
        .json(&payload)
        .send()
        .await
        .expect("call gateway");

    assert_eq!(resp.status(), reqwest::StatusCode::OK);
    let body: Value = resp.json().await.expect("decode gateway response");
    assert_eq!(body["input_tokens"], 321);
    assert_eq!(body["estimated"], false);
}

#[tokio::test]
async fn count_tokens_uses_default_model_as_fallback() {
    // 当没有 rules 匹配且没有 fallback_model 时，应使用 gateway 的 default_model
    let upstream = spawn_upstream_with_count_tokens_expect_default_model_mock().await;
    let gateway = setup_gateway_with_provider_base_url_and_protocol_config_no_default_model_with_explicit_default(
        format!("http://{}/v1", upstream.addr),
        json!({
            "model_mapping": {
                "rules": [
                    {"from": "claude-opus-*", "to": "qwen3-coder-plus"}
                ]
            }
        }),
        "gpt-4o-mini", // gateway 的 default_model
    )
    .await;

    let payload = json!({
        "model": "claude-3-7-sonnet",
        "messages": [{"role": "user", "content": "hello"}]
    });

    let resp = reqwest::Client::new()
        .post(format!("http://{}/v1/messages/count_tokens", gateway.addr))
        .json(&payload)
        .send()
        .await
        .expect("call gateway");

    assert_eq!(resp.status(), reqwest::StatusCode::OK);
    let body: Value = resp.json().await.expect("decode gateway response");
    assert_eq!(body["input_tokens"], 888);
    assert_eq!(body["estimated"], false);
}

struct SpawnedServer {
    addr: SocketAddr,
}

async fn spawn_upstream_with_count_tokens_mock() -> SpawnedServer {
    let app = Router::new().route("/v1/messages/count_tokens", post(upstream_count_tokens));
    spawn_server(app).await
}

async fn spawn_upstream_without_count_tokens_mock() -> SpawnedServer {
    let app = Router::new().route("/v1/chat/completions", post(upstream_chat_completions_placeholder));
    spawn_server(app).await
}

async fn spawn_upstream_with_count_tokens_rewrite_mock() -> SpawnedServer {
    let app = Router::new().route(
        "/v1/messages/count_tokens",
        post(upstream_count_tokens_expect_rewritten_model),
    );
    spawn_server(app).await
}

async fn spawn_upstream_with_count_tokens_expect_default_model_mock() -> SpawnedServer {
    let app = Router::new().route(
        "/v1/messages/count_tokens",
        post(upstream_count_tokens_expect_default_model),
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

async fn setup_gateway_with_provider_base_url_and_protocol_config_no_default_model(
    base_url: String,
    protocol_config_json: Value,
) -> SpawnedServer {
    setup_gateway_with_provider_base_url_and_protocol_config_internal(base_url, protocol_config_json, None::<&str>).await
}

async fn setup_gateway_with_provider_base_url_and_protocol_config_no_default_model_with_explicit_default(
    base_url: String,
    protocol_config_json: Value,
    default_model: &str,
) -> SpawnedServer {
    setup_gateway_with_provider_base_url_and_protocol_config_internal(base_url, protocol_config_json, Some(default_model)).await
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
    spawn_server(app).await
}

async fn upstream_count_tokens(Json(payload): Json<Value>) -> impl IntoResponse {
    assert_eq!(payload["model"], "claude-3-7-sonnet");
    assert_eq!(payload["messages"][0]["role"], "user");
    assert_eq!(payload["messages"][0]["content"], "hello");
    Json(json!({ "input_tokens": 321 }))
}

async fn upstream_chat_completions_placeholder(_: Json<Value>) -> impl IntoResponse {
    Json(json!({
        "id": "chatcmpl_placeholder",
        "object": "chat.completion",
        "choices": [{
            "index": 0,
            "message": {"role": "assistant", "content": "ok"},
            "finish_reason": "stop"
        }]
    }))
}

async fn upstream_count_tokens_expect_rewritten_model(Json(payload): Json<Value>) -> impl IntoResponse {
    assert_eq!(payload["model"], "qwen3-coder-plus");
    Json(json!({ "input_tokens": 777 }))
}

async fn upstream_count_tokens_expect_default_model(Json(payload): Json<Value>) -> impl IntoResponse {
    // 验证模型被重写为 gateway 的 default_model
    assert_eq!(payload["model"], "gpt-4o-mini");
    Json(json!({ "input_tokens": 888 }))
}
