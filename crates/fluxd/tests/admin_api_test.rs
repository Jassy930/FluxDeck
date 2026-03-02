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
