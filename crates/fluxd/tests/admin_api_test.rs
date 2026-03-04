use std::net::{SocketAddr, TcpListener as StdTcpListener};

use axum::Router;
use fluxd::http::admin_routes::{build_admin_router, AdminApiState};
use fluxd::storage::migrate::run_migrations;
use serde_json::json;
use tokio::net::TcpListener;

#[tokio::test]
async fn admin_api_manages_resources() {
    let pool = sqlx::SqlitePool::connect("sqlite::memory:")
        .await
        .expect("connect sqlite memory db");
    run_migrations(&pool).await.expect("run migrations");

    let app = build_admin_router(AdminApiState::new(pool));
    let server = spawn_server(app).await;
    let base = format!("http://{}", server.addr);
    let client = reqwest::Client::new();

    let provider_resp = client
        .post(format!("{base}/admin/providers"))
        .json(&json!({
            "id": "provider_admin_1",
            "name": "Admin Provider",
            "kind": "openai",
            "base_url": "https://api.openai.com/v1",
            "api_key": "sk-admin",
            "models": ["gpt-4o-mini"],
            "enabled": true
        }))
        .send()
        .await
        .expect("create provider request");
    assert_eq!(provider_resp.status(), reqwest::StatusCode::CREATED);

    let gateway_resp = client
        .post(format!("{base}/admin/gateways"))
        .json(&json!({
            "id": "gateway_admin_1",
            "name": "Admin Gateway",
            "listen_host": "127.0.0.1",
            "listen_port": next_free_port(),
            "inbound_protocol": "openai",
            "default_provider_id": "provider_admin_1",
            "default_model": "gpt-4o-mini",
            "enabled": true
        }))
        .send()
        .await
        .expect("create gateway request");
    assert_eq!(gateway_resp.status(), reqwest::StatusCode::CREATED);

    let start_resp = client
        .post(format!("{base}/admin/gateways/gateway_admin_1/start"))
        .send()
        .await
        .expect("start gateway request");
    assert_eq!(start_resp.status(), reqwest::StatusCode::OK);

    let stop_resp = client
        .post(format!("{base}/admin/gateways/gateway_admin_1/stop"))
        .send()
        .await
        .expect("stop gateway request");
    assert_eq!(stop_resp.status(), reqwest::StatusCode::OK);

    let logs_resp = client
        .get(format!("{base}/admin/logs"))
        .send()
        .await
        .expect("list logs request");
    assert_eq!(logs_resp.status(), reqwest::StatusCode::OK);

    let logs: serde_json::Value = logs_resp.json().await.expect("decode logs");
    assert!(logs.is_array());
}

#[tokio::test]
async fn admin_api_response_shape_is_stable() {
    let pool = sqlx::SqlitePool::connect("sqlite::memory:")
        .await
        .expect("connect sqlite memory db");
    run_migrations(&pool).await.expect("run migrations");

    let app = build_admin_router(AdminApiState::new(pool.clone()));
    let server = spawn_server(app).await;
    let base = format!("http://{}", server.addr);
    let client = reqwest::Client::new();

    client
        .post(format!("{base}/admin/providers"))
        .json(&json!({
            "id": "provider_contract_1",
            "name": "Contract Provider",
            "kind": "openai",
            "base_url": "https://api.openai.com/v1",
            "api_key": "sk-contract",
            "models": ["gpt-4o-mini"],
            "enabled": true
        }))
        .send()
        .await
        .expect("create provider request");

    client
        .post(format!("{base}/admin/gateways"))
        .json(&json!({
            "id": "gateway_contract_1",
            "name": "Contract Gateway",
            "listen_host": "127.0.0.1",
            "listen_port": next_free_port(),
            "inbound_protocol": "openai",
            "default_provider_id": "provider_contract_1",
            "default_model": "gpt-4o-mini",
            "enabled": true
        }))
        .send()
        .await
        .expect("create gateway request");

    sqlx::query(
        r#"
        INSERT INTO request_logs (request_id, gateway_id, provider_id, model, status_code, latency_ms, error)
        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
        "#,
    )
    .bind("req_contract_1")
    .bind("gateway_contract_1")
    .bind("provider_contract_1")
    .bind("gpt-4o-mini")
    .bind(200_i64)
    .bind(12_i64)
    .bind(Option::<String>::None)
    .execute(&pool)
    .await
    .expect("insert test log");

    let providers: serde_json::Value = client
        .get(format!("{base}/admin/providers"))
        .send()
        .await
        .expect("list providers request")
        .json()
        .await
        .expect("decode providers");
    let provider = providers
        .as_array()
        .and_then(|items| items.first())
        .expect("providers contains one item");
    assert!(provider.get("id").is_some());
    assert!(provider.get("name").is_some());
    assert!(provider.get("kind").is_some());
    assert!(provider.get("base_url").is_some());
    assert!(provider.get("models").is_some());
    assert!(provider.get("enabled").is_some());

    let gateways: serde_json::Value = client
        .get(format!("{base}/admin/gateways"))
        .send()
        .await
        .expect("list gateways request")
        .json()
        .await
        .expect("decode gateways");
    let gateway = gateways
        .as_array()
        .and_then(|items| items.first())
        .expect("gateways contains one item");
    assert!(gateway.get("id").is_some());
    assert!(gateway.get("name").is_some());
    assert!(gateway.get("listen_host").is_some());
    assert!(gateway.get("listen_port").is_some());
    assert!(gateway.get("inbound_protocol").is_some());
    assert_eq!(
        gateway
            .get("upstream_protocol")
            .and_then(serde_json::Value::as_str),
        Some("provider_default")
    );
    assert!(
        gateway
            .get("protocol_config_json")
            .and_then(serde_json::Value::as_object)
            .is_some()
    );
    assert_eq!(gateway.get("protocol_config_json"), Some(&json!({})));
    assert!(gateway.get("default_provider_id").is_some());
    assert!(gateway.get("enabled").is_some());

    let logs: serde_json::Value = client
        .get(format!("{base}/admin/logs"))
        .send()
        .await
        .expect("list logs request")
        .json()
        .await
        .expect("decode logs");
    let log_item = logs
        .as_array()
        .and_then(|items| items.first())
        .expect("logs contains one item");
    assert!(log_item.get("request_id").is_some());
    assert!(log_item.get("gateway_id").is_some());
    assert!(log_item.get("provider_id").is_some());
    assert!(log_item.get("model").is_some());
    assert!(log_item.get("status_code").is_some());
    assert!(log_item.get("latency_ms").is_some());
    assert!(log_item.get("error").is_some());
    assert!(log_item.get("created_at").is_some());
}

#[tokio::test]
async fn admin_api_returns_gateway_runtime_status() {
    let pool = sqlx::SqlitePool::connect("sqlite::memory:")
        .await
        .expect("connect sqlite memory db");
    run_migrations(&pool).await.expect("run migrations");

    let app = build_admin_router(AdminApiState::new(pool));
    let server = spawn_server(app).await;
    let base = format!("http://{}", server.addr);
    let client = reqwest::Client::new();

    client
        .post(format!("{base}/admin/providers"))
        .json(&json!({
            "id": "provider_status_1",
            "name": "Status Provider",
            "kind": "openai",
            "base_url": "https://api.openai.com/v1",
            "api_key": "sk-status",
            "models": ["gpt-4o-mini"],
            "enabled": true
        }))
        .send()
        .await
        .expect("create provider request");

    client
        .post(format!("{base}/admin/gateways"))
        .json(&json!({
            "id": "gateway_status_1",
            "name": "Status Gateway",
            "listen_host": "127.0.0.1",
            "listen_port": next_free_port(),
            "inbound_protocol": "openai",
            "default_provider_id": "provider_status_1",
            "default_model": "gpt-4o-mini",
            "enabled": true
        }))
        .send()
        .await
        .expect("create gateway request");

    let before_start: serde_json::Value = client
        .get(format!("{base}/admin/gateways"))
        .send()
        .await
        .expect("list gateways request before start")
        .json()
        .await
        .expect("decode gateways before start");
    let gateway_before = before_start
        .as_array()
        .and_then(|items| items.first())
        .expect("gateway exists before start");
    assert_eq!(gateway_before.get("runtime_status"), Some(&json!("stopped")));

    let start_resp = client
        .post(format!("{base}/admin/gateways/gateway_status_1/start"))
        .send()
        .await
        .expect("start gateway request");
    assert_eq!(start_resp.status(), reqwest::StatusCode::OK);

    let after_start: serde_json::Value = client
        .get(format!("{base}/admin/gateways"))
        .send()
        .await
        .expect("list gateways request after start")
        .json()
        .await
        .expect("decode gateways after start");
    let gateway_after_start = after_start
        .as_array()
        .and_then(|items| items.first())
        .expect("gateway exists after start");
    assert_eq!(gateway_after_start.get("runtime_status"), Some(&json!("running")));

    let stop_resp = client
        .post(format!("{base}/admin/gateways/gateway_status_1/stop"))
        .send()
        .await
        .expect("stop gateway request");
    assert_eq!(stop_resp.status(), reqwest::StatusCode::OK);

    let after_stop: serde_json::Value = client
        .get(format!("{base}/admin/gateways"))
        .send()
        .await
        .expect("list gateways request after stop")
        .json()
        .await
        .expect("decode gateways after stop");
    let gateway_after_stop = after_stop
        .as_array()
        .and_then(|items| items.first())
        .expect("gateway exists after stop");
    assert_eq!(gateway_after_stop.get("runtime_status"), Some(&json!("stopped")));
}

#[tokio::test]
async fn admin_api_accepts_gateway_protocol_config_fields() {
    let pool = sqlx::SqlitePool::connect("sqlite::memory:")
        .await
        .expect("connect sqlite memory db");
    run_migrations(&pool).await.expect("run migrations");

    let app = build_admin_router(AdminApiState::new(pool));
    let server = spawn_server(app).await;
    let base = format!("http://{}", server.addr);
    let client = reqwest::Client::new();

    client
        .post(format!("{base}/admin/providers"))
        .json(&json!({
            "id": "provider_protocol_1",
            "name": "Protocol Provider",
            "kind": "openai",
            "base_url": "https://api.openai.com/v1",
            "api_key": "sk-protocol",
            "models": ["gpt-4o-mini"],
            "enabled": true
        }))
        .send()
        .await
        .expect("create provider request");

    let create_gateway_resp = client
        .post(format!("{base}/admin/gateways"))
        .json(&json!({
            "id": "gateway_protocol_1",
            "name": "Protocol Gateway",
            "listen_host": "127.0.0.1",
            "listen_port": next_free_port(),
            "inbound_protocol": "anthropic",
            "upstream_protocol": "openai",
            "protocol_config_json": {
                "compatibility_mode": "compatible"
            },
            "default_provider_id": "provider_protocol_1",
            "default_model": "claude-3-7-sonnet",
            "enabled": true
        }))
        .send()
        .await
        .expect("create gateway request");
    assert_eq!(create_gateway_resp.status(), reqwest::StatusCode::CREATED);
    let created_gateway: serde_json::Value = create_gateway_resp
        .json()
        .await
        .expect("decode create gateway response");
    assert_eq!(created_gateway.get("inbound_protocol"), Some(&json!("anthropic")));
    assert_eq!(created_gateway.get("upstream_protocol"), Some(&json!("openai")));
    assert_eq!(
        created_gateway.get("protocol_config_json"),
        Some(&json!({ "compatibility_mode": "compatible" }))
    );
}

struct SpawnedServer {
    addr: SocketAddr,
}

async fn spawn_server(app: Router) -> SpawnedServer {
    let listener = TcpListener::bind("127.0.0.1:0").await.expect("bind random port");
    let addr = listener.local_addr().expect("read listener addr");

    tokio::spawn(async move {
        axum::serve(listener, app).await.expect("serve admin app");
    });

    SpawnedServer { addr }
}

fn next_free_port() -> i64 {
    let listener = StdTcpListener::bind("127.0.0.1:0").expect("bind random port");
    let port = listener.local_addr().expect("read local addr").port() as i64;
    drop(listener);
    port
}
