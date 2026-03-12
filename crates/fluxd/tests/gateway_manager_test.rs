use std::net::TcpListener as StdTcpListener;

use fluxd::domain::gateway::CreateGatewayInput;
use fluxd::repo::gateway_repo::GatewayRepo;
use fluxd::runtime::gateway_manager::{
    GatewayAutoStartSummary, GatewayManager, GatewayRuntimeStatus,
};
use fluxd::storage::migrate::run_migrations;
use serde_json::json;

#[tokio::test]
async fn starts_multiple_gateways_on_different_ports() {
    let pool = sqlx::SqlitePool::connect("sqlite::memory:")
        .await
        .expect("connect sqlite memory db");
    run_migrations(&pool).await.expect("run migrations");

    sqlx::query(
        "INSERT INTO providers (id, name, kind, base_url, api_key, enabled) VALUES (?1, ?2, ?3, ?4, ?5, 1)",
    )
    .bind("provider_default")
    .bind("Default")
    .bind("openai")
    .bind("https://api.openai.com/v1")
    .bind("sk-test")
    .execute(&pool)
    .await
    .expect("insert default provider");

    let repo = GatewayRepo::new(pool.clone());
    let gw1 = repo
        .create(CreateGatewayInput {
            id: "gw_1".to_string(),
            name: "Gateway 1".to_string(),
            listen_host: "127.0.0.1".to_string(),
            listen_port: next_free_port(),
            inbound_protocol: "openai".to_string(),
            upstream_protocol: "provider_default".to_string(),
            protocol_config_json: serde_json::json!({}),
            default_provider_id: "provider_default".to_string(),
            default_model: Some("gpt-4o-mini".to_string()),
            enabled: true,
            auto_start: false,
        })
        .await
        .expect("create gateway 1");

    let gw2 = repo
        .create(CreateGatewayInput {
            id: "gw_2".to_string(),
            name: "Gateway 2".to_string(),
            listen_host: "127.0.0.1".to_string(),
            listen_port: next_free_port(),
            inbound_protocol: "openai".to_string(),
            upstream_protocol: "provider_default".to_string(),
            protocol_config_json: serde_json::json!({}),
            default_provider_id: "provider_default".to_string(),
            default_model: Some("gpt-4.1".to_string()),
            enabled: true,
            auto_start: false,
        })
        .await
        .expect("create gateway 2");

    let manager = GatewayManager::new(pool);

    manager.start_gateway(&gw1.id).await.expect("start gw1");
    manager.start_gateway(&gw2.id).await.expect("start gw2");

    assert_eq!(manager.status(&gw1.id).await, GatewayRuntimeStatus::Running);
    assert_eq!(manager.status(&gw2.id).await, GatewayRuntimeStatus::Running);

    manager.stop_gateway(&gw1.id).await.expect("stop gw1");
    manager.stop_gateway(&gw2.id).await.expect("stop gw2");

    assert_eq!(manager.status(&gw1.id).await, GatewayRuntimeStatus::Stopped);
    assert_eq!(manager.status(&gw2.id).await, GatewayRuntimeStatus::Stopped);
}

#[tokio::test]
async fn routes_gateway_runtime_by_inbound_protocol() {
    let pool = sqlx::SqlitePool::connect("sqlite::memory:")
        .await
        .expect("connect sqlite memory db");
    run_migrations(&pool).await.expect("run migrations");

    sqlx::query(
        "INSERT INTO providers (id, name, kind, base_url, api_key, enabled) VALUES (?1, ?2, ?3, ?4, ?5, 1)",
    )
    .bind("provider_default")
    .bind("Default")
    .bind("openai")
    .bind("http://127.0.0.1:9/v1")
    .bind("sk-test")
    .execute(&pool)
    .await
    .expect("insert default provider");

    let repo = GatewayRepo::new(pool.clone());
    let openai_gateway = repo
        .create(CreateGatewayInput {
            id: "gw_openai".to_string(),
            name: "Gateway OpenAI".to_string(),
            listen_host: "127.0.0.1".to_string(),
            listen_port: next_free_port(),
            inbound_protocol: "openai".to_string(),
            upstream_protocol: "provider_default".to_string(),
            protocol_config_json: serde_json::json!({}),
            default_provider_id: "provider_default".to_string(),
            default_model: Some("gpt-4o-mini".to_string()),
            enabled: true,
            auto_start: false,
        })
        .await
        .expect("create openai gateway");

    let anthropic_gateway = repo
        .create(CreateGatewayInput {
            id: "gw_anthropic".to_string(),
            name: "Gateway Anthropic".to_string(),
            listen_host: "127.0.0.1".to_string(),
            listen_port: next_free_port(),
            inbound_protocol: "anthropic".to_string(),
            upstream_protocol: "provider_default".to_string(),
            protocol_config_json: serde_json::json!({}),
            default_provider_id: "provider_default".to_string(),
            default_model: Some("claude-3-7-sonnet".to_string()),
            enabled: true,
            auto_start: false,
        })
        .await
        .expect("create anthropic gateway");

    let manager = GatewayManager::new(pool);
    manager
        .start_gateway(&openai_gateway.id)
        .await
        .expect("start openai gateway");
    manager
        .start_gateway(&anthropic_gateway.id)
        .await
        .expect("start anthropic gateway");

    let client = reqwest::Client::new();

    let openai_resp = client
        .post(format!(
            "http://127.0.0.1:{}/v1/messages",
            openai_gateway.listen_port
        ))
        .json(&json!({}))
        .send()
        .await
        .expect("call openai gateway");
    assert_eq!(openai_resp.status(), reqwest::StatusCode::BAD_GATEWAY);

    let anthropic_resp = client
        .post(format!(
            "http://127.0.0.1:{}/v1/messages",
            anthropic_gateway.listen_port
        ))
        .json(&json!({}))
        .send()
        .await
        .expect("call anthropic gateway");
    assert_ne!(anthropic_resp.status(), reqwest::StatusCode::NOT_FOUND);

    manager
        .stop_gateway(&openai_gateway.id)
        .await
        .expect("stop openai gateway");
    manager
        .stop_gateway(&anthropic_gateway.id)
        .await
        .expect("stop anthropic gateway");
}

#[tokio::test]
async fn starts_openai_response_gateway_runtime() {
    let pool = sqlx::SqlitePool::connect("sqlite::memory:")
        .await
        .expect("connect sqlite memory db");
    run_migrations(&pool).await.expect("run migrations");

    sqlx::query(
        "INSERT INTO providers (id, name, kind, base_url, api_key, enabled) VALUES (?1, ?2, ?3, ?4, ?5, 1)",
    )
    .bind("provider_response")
    .bind("OpenAI Response")
    .bind("openai-response")
    .bind("http://127.0.0.1:9/v1")
    .bind("sk-test")
    .execute(&pool)
    .await
    .expect("insert response provider");

    let repo = GatewayRepo::new(pool.clone());
    let response_gateway = repo
        .create(CreateGatewayInput {
            id: "gw_openai_response".to_string(),
            name: "Gateway OpenAI Response".to_string(),
            listen_host: "127.0.0.1".to_string(),
            listen_port: next_free_port(),
            inbound_protocol: "openai-response".to_string(),
            upstream_protocol: "provider_default".to_string(),
            protocol_config_json: serde_json::json!({}),
            default_provider_id: "provider_response".to_string(),
            default_model: Some("gpt-5-codex".to_string()),
            enabled: true,
            auto_start: false,
        })
        .await
        .expect("create openai-response gateway");

    let manager = GatewayManager::new(pool);
    manager
        .start_gateway(&response_gateway.id)
        .await
        .expect("start openai-response gateway");

    assert_eq!(
        manager.status(&response_gateway.id).await,
        GatewayRuntimeStatus::Running
    );

    manager
        .stop_gateway(&response_gateway.id)
        .await
        .expect("stop openai-response gateway");
}

#[tokio::test]
async fn auto_start_only_starts_enabled_gateways_and_records_failures() {
    let pool = sqlx::SqlitePool::connect("sqlite::memory:")
        .await
        .expect("connect sqlite memory db");
    run_migrations(&pool).await.expect("run migrations");

    sqlx::query(
        "INSERT INTO providers (id, name, kind, base_url, api_key, enabled) VALUES (?1, ?2, ?3, ?4, ?5, 1)",
    )
    .bind("provider_default")
    .bind("Default")
    .bind("openai")
    .bind("https://api.openai.com/v1")
    .bind("sk-test")
    .execute(&pool)
    .await
    .expect("insert default provider");

    let repo = GatewayRepo::new(pool.clone());
    let running_gateway = repo
        .create(CreateGatewayInput {
            id: "gw_auto_running".to_string(),
            name: "Gateway Auto Running".to_string(),
            listen_host: "127.0.0.1".to_string(),
            listen_port: next_free_port(),
            inbound_protocol: "openai".to_string(),
            upstream_protocol: "provider_default".to_string(),
            protocol_config_json: serde_json::json!({}),
            default_provider_id: "provider_default".to_string(),
            default_model: Some("gpt-4o-mini".to_string()),
            enabled: true,
            auto_start: true,
        })
        .await
        .expect("create running gateway");

    let manual_gateway = repo
        .create(CreateGatewayInput {
            id: "gw_manual".to_string(),
            name: "Gateway Manual".to_string(),
            listen_host: "127.0.0.1".to_string(),
            listen_port: next_free_port(),
            inbound_protocol: "openai".to_string(),
            upstream_protocol: "provider_default".to_string(),
            protocol_config_json: serde_json::json!({}),
            default_provider_id: "provider_default".to_string(),
            default_model: Some("gpt-4o-mini".to_string()),
            enabled: true,
            auto_start: false,
        })
        .await
        .expect("create manual gateway");

    let disabled_gateway = repo
        .create(CreateGatewayInput {
            id: "gw_disabled".to_string(),
            name: "Gateway Disabled".to_string(),
            listen_host: "127.0.0.1".to_string(),
            listen_port: next_free_port(),
            inbound_protocol: "openai".to_string(),
            upstream_protocol: "provider_default".to_string(),
            protocol_config_json: serde_json::json!({}),
            default_provider_id: "provider_default".to_string(),
            default_model: Some("gpt-4o-mini".to_string()),
            enabled: false,
            auto_start: true,
        })
        .await
        .expect("create disabled gateway");

    let occupied_listener = StdTcpListener::bind("127.0.0.1:0").expect("bind occupied port");
    let occupied_port = occupied_listener
        .local_addr()
        .expect("read occupied local addr")
        .port() as i64;

    let conflict_gateway = repo
        .create(CreateGatewayInput {
            id: "gw_conflict".to_string(),
            name: "Gateway Conflict".to_string(),
            listen_host: "127.0.0.1".to_string(),
            listen_port: occupied_port,
            inbound_protocol: "openai".to_string(),
            upstream_protocol: "provider_default".to_string(),
            protocol_config_json: serde_json::json!({}),
            default_provider_id: "provider_default".to_string(),
            default_model: Some("gpt-4o-mini".to_string()),
            enabled: true,
            auto_start: true,
        })
        .await
        .expect("create conflict gateway");

    let manager = GatewayManager::new(pool);
    let summary = manager
        .start_auto_start_gateways()
        .await
        .expect("start auto-start gateways");

    assert_eq!(
        summary,
        GatewayAutoStartSummary {
            eligible: 2,
            started: 1,
            failed: 1,
        }
    );
    assert_eq!(
        manager.status(&running_gateway.id).await,
        GatewayRuntimeStatus::Running
    );
    assert_eq!(
        manager.status(&manual_gateway.id).await,
        GatewayRuntimeStatus::Stopped
    );
    assert_eq!(
        manager.status(&disabled_gateway.id).await,
        GatewayRuntimeStatus::Stopped
    );
    assert_eq!(
        manager.status(&conflict_gateway.id).await,
        GatewayRuntimeStatus::Stopped
    );
    assert_eq!(manager.last_error(&running_gateway.id).await, None);
    assert!(manager.last_error(&conflict_gateway.id).await.is_some());

    drop(occupied_listener);

    manager
        .stop_gateway(&running_gateway.id)
        .await
        .expect("stop running gateway");
}

fn next_free_port() -> i64 {
    let listener = StdTcpListener::bind("127.0.0.1:0").expect("bind random port");
    let port = listener.local_addr().expect("read local addr").port() as i64;
    drop(listener);
    port
}
