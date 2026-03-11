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
            "enabled": true,
            "auto_start": true
        }))
        .send()
        .await
        .expect("create gateway request");
    assert_eq!(gateway_resp.status(), reqwest::StatusCode::CREATED);
    let created_gateway: serde_json::Value = gateway_resp.json().await.expect("decode created gateway");
    assert_eq!(created_gateway.get("auto_start"), Some(&json!(true)));

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

    let update_gateway_resp = client
        .put(format!("{base}/admin/gateways/gateway_admin_1"))
        .json(&json!({
            "name": "Admin Gateway Updated",
            "listen_host": "127.0.0.1",
            "listen_port": next_free_port(),
            "inbound_protocol": "openai",
            "upstream_protocol": "provider_default",
            "protocol_config_json": {"compatibility_mode":"compatible"},
            "default_provider_id": "provider_admin_1",
            "default_model": "gpt-4.1-mini",
            "enabled": false,
            "auto_start": false
        }))
        .send()
        .await
        .expect("update gateway request");
    assert_eq!(update_gateway_resp.status(), reqwest::StatusCode::OK);

    let updated_gateway: serde_json::Value = update_gateway_resp
        .json()
        .await
        .expect("decode updated gateway");
    assert_eq!(updated_gateway.get("id"), Some(&json!("gateway_admin_1")));
    assert_eq!(updated_gateway.get("name"), Some(&json!("Admin Gateway Updated")));
    assert_eq!(updated_gateway.get("enabled"), Some(&json!(false)));
    assert_eq!(updated_gateway.get("auto_start"), Some(&json!(false)));

    let logs_resp = client
        .get(format!("{base}/admin/logs"))
        .send()
        .await
        .expect("list logs request");
    assert_eq!(logs_resp.status(), reqwest::StatusCode::OK);

    let logs: serde_json::Value = logs_resp.json().await.expect("decode logs");
    assert!(logs.get("items").and_then(serde_json::Value::as_array).is_some());
    assert!(logs.get("has_more").is_some());

    let update_provider_resp = client
        .put(format!("{base}/admin/providers/provider_admin_1"))
        .json(&json!({
            "name": "Admin Provider Updated",
            "kind": "openai",
            "base_url": "https://api.openai.com/v1",
            "api_key": "sk-admin-updated",
            "models": ["gpt-4.1-mini"],
            "enabled": false
        }))
        .send()
        .await
        .expect("update provider request");
    assert_eq!(update_provider_resp.status(), reqwest::StatusCode::OK);

    let updated_provider: serde_json::Value = update_provider_resp
        .json()
        .await
        .expect("decode updated provider");
    assert_eq!(updated_provider.get("id"), Some(&json!("provider_admin_1")));
    assert_eq!(updated_provider.get("name"), Some(&json!("Admin Provider Updated")));
    assert_eq!(updated_provider.get("enabled"), Some(&json!(false)));

    let not_found_update_resp = client
        .put(format!("{base}/admin/providers/provider_not_found"))
        .json(&json!({
            "name": "Unknown Provider",
            "kind": "openai",
            "base_url": "https://api.openai.com/v1",
            "api_key": "sk-unknown",
            "models": ["gpt-4.1-mini"],
            "enabled": true
        }))
        .send()
        .await
        .expect("update missing provider request");
    assert_eq!(not_found_update_resp.status(), reqwest::StatusCode::NOT_FOUND);

    let not_found_gateway_update_resp = client
        .put(format!("{base}/admin/gateways/gateway_not_found"))
        .json(&json!({
            "name": "Unknown Gateway",
            "listen_host": "127.0.0.1",
            "listen_port": next_free_port(),
            "inbound_protocol": "openai",
            "upstream_protocol": "provider_default",
            "protocol_config_json": {},
            "default_provider_id": "provider_admin_1",
            "default_model": "gpt-4.1-mini",
            "enabled": true,
            "auto_start": true
        }))
        .send()
        .await
        .expect("update missing gateway request");
    assert_eq!(
        not_found_gateway_update_resp.status(),
        reqwest::StatusCode::NOT_FOUND
    );
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
            "enabled": true,
            "auto_start": true
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
    assert_eq!(gateway.get("auto_start"), Some(&json!(true)));
    assert!(gateway.get("runtime_status").is_some());
    assert!(gateway.get("last_error").is_some());

    let logs: serde_json::Value = client
        .get(format!("{base}/admin/logs"))
        .send()
        .await
        .expect("list logs request")
        .json()
        .await
        .expect("decode logs");
    let log_item = logs
        .get("items")
        .and_then(serde_json::Value::as_array)
        .and_then(|items| items.first())
        .expect("logs contains one item");
    assert!(log_item.get("request_id").is_some());
    assert!(log_item.get("gateway_id").is_some());
    assert!(log_item.get("provider_id").is_some());
    assert!(log_item.get("model").is_some());
    assert!(log_item.get("inbound_protocol").is_some());
    assert!(log_item.get("upstream_protocol").is_some());
    assert!(log_item.get("model_requested").is_some());
    assert!(log_item.get("model_effective").is_some());
    assert!(log_item.get("status_code").is_some());
    assert!(log_item.get("latency_ms").is_some());
    assert!(log_item.get("stream").is_some());
    assert!(log_item.get("first_byte_ms").is_some());
    assert!(log_item.get("input_tokens").is_some());
    assert!(log_item.get("output_tokens").is_some());
    assert!(log_item.get("total_tokens").is_some());
    assert!(log_item.get("usage_json").is_some());
    assert!(log_item.get("error_stage").is_some());
    assert!(log_item.get("error_type").is_some());
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
async fn admin_api_defaults_gateway_auto_start_to_false_when_omitted() {
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
            "id": "provider_auto_default",
            "name": "Provider Auto Default",
            "kind": "openai",
            "base_url": "https://api.openai.com/v1",
            "api_key": "sk-auto-default",
            "models": ["gpt-4o-mini"],
            "enabled": true
        }))
        .send()
        .await
        .expect("create provider request");

    let gateway: serde_json::Value = client
        .post(format!("{base}/admin/gateways"))
        .json(&json!({
            "id": "gateway_auto_default",
            "name": "Gateway Auto Default",
            "listen_host": "127.0.0.1",
            "listen_port": next_free_port(),
            "inbound_protocol": "openai",
            "default_provider_id": "provider_auto_default",
            "default_model": "gpt-4o-mini",
            "enabled": true
        }))
        .send()
        .await
        .expect("create gateway request")
        .json()
        .await
        .expect("decode gateway");

    assert_eq!(gateway.get("auto_start"), Some(&json!(false)));
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


#[tokio::test]
async fn admin_api_lists_logs_as_paginated_object_with_default_limit() {
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
            "id": "provider_page",
            "name": "Page Provider",
            "kind": "openai",
            "base_url": "https://api.openai.com/v1",
            "api_key": "sk-page",
            "models": ["gpt-4o-mini"],
            "enabled": true
        }))
        .send()
        .await
        .expect("create provider request");

    client
        .post(format!("{base}/admin/gateways"))
        .json(&json!({
            "id": "gateway_page",
            "name": "Page Gateway",
            "listen_host": "127.0.0.1",
            "listen_port": next_free_port(),
            "inbound_protocol": "openai",
            "default_provider_id": "provider_page",
            "default_model": "gpt-4o-mini",
            "enabled": true
        }))
        .send()
        .await
        .expect("create gateway request");

    for index in 0..60 {
        let request_id = format!("req_page_{index:03}");
        let created_at = format!("2026-03-08T10:{:02}:00Z", index % 60);
        sqlx::query(
            r#"
            INSERT INTO request_logs (request_id, gateway_id, provider_id, model, status_code, latency_ms, error, created_at)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
            "#,
        )
        .bind(request_id)
        .bind("gateway_page")
        .bind("provider_page")
        .bind("gpt-4o-mini")
        .bind(200_i64)
        .bind(100_i64)
        .bind(Option::<String>::None)
        .bind(created_at)
        .execute(&pool)
        .await
        .expect("insert paginated log");
    }

    let logs: serde_json::Value = client
        .get(format!("{base}/admin/logs"))
        .send()
        .await
        .expect("list logs request")
        .json()
        .await
        .expect("decode logs response");

    let items = logs
        .get("items")
        .and_then(serde_json::Value::as_array)
        .expect("logs response has items array");
    assert_eq!(items.len(), 50);
    assert_eq!(logs.get("has_more"), Some(&json!(true)));
    assert!(logs.get("next_cursor").is_some());
}


#[tokio::test]
async fn admin_api_logs_support_cursor_and_filters() {
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
            "id": "provider_filter_a",
            "name": "Filter Provider A",
            "kind": "openai",
            "base_url": "https://api.openai.com/v1",
            "api_key": "sk-filter-a",
            "models": ["gpt-4o-mini"],
            "enabled": true
        }))
        .send()
        .await
        .expect("create provider a request");

    client
        .post(format!("{base}/admin/providers"))
        .json(&json!({
            "id": "provider_filter_b",
            "name": "Filter Provider B",
            "kind": "openai",
            "base_url": "https://api.openai.com/v1",
            "api_key": "sk-filter-b",
            "models": ["gpt-4.1-mini"],
            "enabled": true
        }))
        .send()
        .await
        .expect("create provider b request");

    client
        .post(format!("{base}/admin/gateways"))
        .json(&json!({
            "id": "gateway_filter_a",
            "name": "Filter Gateway A",
            "listen_host": "127.0.0.1",
            "listen_port": next_free_port(),
            "inbound_protocol": "openai",
            "default_provider_id": "provider_filter_a",
            "default_model": "gpt-4o-mini",
            "enabled": true
        }))
        .send()
        .await
        .expect("create gateway a request");

    client
        .post(format!("{base}/admin/gateways"))
        .json(&json!({
            "id": "gateway_filter_b",
            "name": "Filter Gateway B",
            "listen_host": "127.0.0.1",
            "listen_port": next_free_port(),
            "inbound_protocol": "openai",
            "default_provider_id": "provider_filter_b",
            "default_model": "gpt-4.1-mini",
            "enabled": true
        }))
        .send()
        .await
        .expect("create gateway b request");

    insert_request_log(&pool, "req_filter_005", "gateway_filter_a", "provider_filter_a", 200, None, "2026-03-08T10:05:00Z").await;
    insert_request_log(&pool, "req_filter_004", "gateway_filter_b", "provider_filter_b", 502, None, "2026-03-08T10:04:00Z").await;
    insert_request_log(&pool, "req_filter_003", "gateway_filter_a", "provider_filter_a", 200, Some("degraded to estimate"), "2026-03-08T10:03:00Z").await;
    insert_request_log(&pool, "req_filter_002", "gateway_filter_a", "provider_filter_b", 404, None, "2026-03-08T10:02:00Z").await;
    insert_request_log(&pool, "req_filter_001", "gateway_filter_b", "provider_filter_a", 200, None, "2026-03-08T10:01:00Z").await;

    let first_page: serde_json::Value = client
        .get(format!("{base}/admin/logs?limit=2"))
        .send()
        .await
        .expect("list logs first page request")
        .json()
        .await
        .expect("decode first page logs");
    let first_items = first_page
        .get("items")
        .and_then(serde_json::Value::as_array)
        .expect("first page items");
    assert_eq!(first_items.len(), 2);
    assert_eq!(first_items[0].get("request_id"), Some(&json!("req_filter_005")));
    assert_eq!(first_items[1].get("request_id"), Some(&json!("req_filter_004")));
    assert_eq!(first_page.get("has_more"), Some(&json!(true)));

    let cursor = first_page
        .get("next_cursor")
        .and_then(serde_json::Value::as_object)
        .expect("first page next cursor");
    let cursor_created_at = cursor
        .get("created_at")
        .and_then(serde_json::Value::as_str)
        .expect("cursor created_at");
    let cursor_request_id = cursor
        .get("request_id")
        .and_then(serde_json::Value::as_str)
        .expect("cursor request_id");

    let second_page: serde_json::Value = client
        .get(format!(
            "{base}/admin/logs?limit=2&cursor_created_at={cursor_created_at}&cursor_request_id={cursor_request_id}"
        ))
        .send()
        .await
        .expect("list logs second page request")
        .json()
        .await
        .expect("decode second page logs");
    let second_items = second_page
        .get("items")
        .and_then(serde_json::Value::as_array)
        .expect("second page items");
    assert_eq!(second_items[0].get("request_id"), Some(&json!("req_filter_003")));
    assert_eq!(second_items[1].get("request_id"), Some(&json!("req_filter_002")));

    let filtered_errors: serde_json::Value = client
        .get(format!("{base}/admin/logs?gateway_id=gateway_filter_a&errors_only=true"))
        .send()
        .await
        .expect("list filtered logs request")
        .json()
        .await
        .expect("decode filtered logs");
    let filtered_items = filtered_errors
        .get("items")
        .and_then(serde_json::Value::as_array)
        .expect("filtered items");
    assert_eq!(filtered_items.len(), 2);
    assert_eq!(filtered_items[0].get("request_id"), Some(&json!("req_filter_003")));
    assert_eq!(filtered_items[1].get("request_id"), Some(&json!("req_filter_002")));
}

#[tokio::test]
async fn admin_logs_expose_forwarding_protocol_and_usage_fields() {
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
            "id": "provider_logs_fields",
            "name": "Logs Fields Provider",
            "kind": "openai",
            "base_url": "https://api.openai.com/v1",
            "api_key": "sk-logs-fields",
            "models": ["gpt-4o-mini"],
            "enabled": true
        }))
        .send()
        .await
        .expect("create provider request");

    client
        .post(format!("{base}/admin/gateways"))
        .json(&json!({
            "id": "gateway_logs_fields",
            "name": "Logs Fields Gateway",
            "listen_host": "127.0.0.1",
            "listen_port": next_free_port(),
            "inbound_protocol": "anthropic",
            "upstream_protocol": "openai",
            "default_provider_id": "provider_logs_fields",
            "default_model": "qwen3-coder-plus",
            "enabled": true
        }))
        .send()
        .await
        .expect("create gateway request");

    sqlx::query(
        r#"
        INSERT INTO request_logs (
            request_id, gateway_id, provider_id, model, status_code, latency_ms, error,
            inbound_protocol, upstream_protocol, model_requested, model_effective,
            stream, first_byte_ms, input_tokens, output_tokens, total_tokens, usage_json,
            error_stage, error_type
        )
        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19)
        "#,
    )
    .bind("req_logs_fields_001")
    .bind("gateway_logs_fields")
    .bind("provider_logs_fields")
    .bind("qwen3-coder-plus")
    .bind(200_i64)
    .bind(42_i64)
    .bind(Option::<String>::None)
    .bind("anthropic")
    .bind("openai")
    .bind("claude-3-7-sonnet")
    .bind("qwen3-coder-plus")
    .bind(0_i64)
    .bind(12_i64)
    .bind(128_i64)
    .bind(64_i64)
    .bind(192_i64)
    .bind(json!({"prompt_tokens": 128, "completion_tokens": 64}).to_string())
    .bind(Option::<String>::None)
    .bind(Option::<String>::None)
    .execute(&pool)
    .await
    .expect("insert log with forwarding fields");

    let response: serde_json::Value = client
        .get(format!("{base}/admin/logs"))
        .send()
        .await
        .expect("fetch logs request")
        .json()
        .await
        .expect("decode logs response");
    let first = &response["items"][0];

    assert!(first.get("inbound_protocol").is_some());
    assert!(first.get("upstream_protocol").is_some());
    assert!(first.get("input_tokens").is_some());
}

#[tokio::test]
async fn admin_stats_include_recent_logs_even_when_average_latency_is_fractional() {
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
            "id": "provider_stats_fractional",
            "name": "Stats Provider",
            "kind": "openai",
            "base_url": "https://api.openai.com/v1",
            "api_key": "sk-stats",
            "models": ["gpt-4o-mini"],
            "enabled": true
        }))
        .send()
        .await
        .expect("create provider request");

    client
        .post(format!("{base}/admin/gateways"))
        .json(&json!({
            "id": "gateway_stats_fractional",
            "name": "Stats Gateway",
            "listen_host": "127.0.0.1",
            "listen_port": next_free_port(),
            "inbound_protocol": "openai",
            "default_provider_id": "provider_stats_fractional",
            "default_model": "gpt-4o-mini",
            "enabled": true
        }))
        .send()
        .await
        .expect("create gateway request");

    sqlx::query(
        r#"
        INSERT INTO request_logs (request_id, gateway_id, provider_id, model, status_code, latency_ms, error, created_at)
        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, datetime('now', '-5 minutes'))
        "#,
    )
    .bind("req_stats_fractional_1")
    .bind("gateway_stats_fractional")
    .bind("provider_stats_fractional")
    .bind("gpt-4o-mini")
    .bind(200_i64)
    .bind(100_i64)
    .bind(Option::<String>::None)
    .execute(&pool)
    .await
    .expect("insert first stats log");

    sqlx::query(
        r#"
        INSERT INTO request_logs (request_id, gateway_id, provider_id, model, status_code, latency_ms, error, created_at)
        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, datetime('now', '-4 minutes'))
        "#,
    )
    .bind("req_stats_fractional_2")
    .bind("gateway_stats_fractional")
    .bind("provider_stats_fractional")
    .bind("gpt-4o-mini")
    .bind(200_i64)
    .bind(101_i64)
    .bind(Option::<String>::None)
    .execute(&pool)
    .await
    .expect("insert second stats log");

    let overview: serde_json::Value = client
        .get(format!("{base}/admin/stats/overview?period=1h"))
        .send()
        .await
        .expect("fetch stats overview")
        .json()
        .await
        .expect("decode stats overview");

    assert_eq!(overview.get("total_requests"), Some(&json!(2)));
    assert_eq!(overview.get("successful_requests"), Some(&json!(2)));
    assert_eq!(overview.get("error_requests"), Some(&json!(0)));
    assert_eq!(
        overview["by_gateway"][0].get("gateway_id"),
        Some(&json!("gateway_stats_fractional"))
    );

    let trend: serde_json::Value = client
        .get(format!("{base}/admin/stats/trend?period=1h&interval=5m"))
        .send()
        .await
        .expect("fetch stats trend")
        .json()
        .await
        .expect("decode stats trend");

    let trend_data = trend
        .get("data")
        .and_then(serde_json::Value::as_array)
        .expect("stats trend data array");
    assert!(!trend_data.is_empty());
    let total_trend_requests: i64 = trend_data
        .iter()
        .filter_map(|point| point.get("request_count").and_then(serde_json::Value::as_i64))
        .sum();
    assert_eq!(total_trend_requests, 2);
    assert!(trend_data[0].get("avg_latency").is_some());
}


async fn insert_request_log(
    pool: &sqlx::SqlitePool,
    request_id: &str,
    gateway_id: &str,
    provider_id: &str,
    status_code: i64,
    error: Option<&str>,
    created_at: &str,
) {
    sqlx::query(
        r#"
        INSERT INTO request_logs (request_id, gateway_id, provider_id, model, status_code, latency_ms, error, created_at)
        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
        "#,
    )
    .bind(request_id)
    .bind(gateway_id)
    .bind(provider_id)
    .bind("gpt-4o-mini")
    .bind(status_code)
    .bind(100_i64)
    .bind(error)
    .bind(created_at)
    .execute(pool)
    .await
    .expect("insert request log");
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
